// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.8.28;

// solhint-disable ordering

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "openzeppelin5/utils/math/Math.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";

import {Ownable2Step, Ownable} from "openzeppelin5/access/Ownable2Step.sol";
import {EnumerableSet} from "openzeppelin5/utils/structs/EnumerableSet.sol";

import {ISiloIncentivesController} from "../interfaces/ISiloIncentivesController.sol";
import {IDistributionManager} from "../interfaces/IDistributionManager.sol";
import {DistributionTypes} from "../lib/DistributionTypes.sol";
import {TokenHelper} from "../../lib/TokenHelper.sol";
import {AddressUtilsLib} from "../../lib/AddressUtilsLib.sol";
/**
 * @title DistributionManager
 * @notice Accounting contract to manage multiple staking distributions
 */
contract DistributionManager is IDistributionManager, Ownable2Step {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    EnumerableSet.Bytes32Set internal _incentivesProgramIds;

    mapping(bytes32 => bool) internal _isImmediateDistributionProgram;
    mapping(bytes32 => IncentivesProgram) public incentivesPrograms;

    /// @dev notifier is contract with IERC20 interface with users balances, based based on which
    /// rewards distribution is calculated
    address public immutable NOTIFIER; // solhint-disable-line var-name-mixedcase

    uint8 public constant PRECISION = 36;
    uint256 public constant TEN_POW_PRECISION = 10 ** PRECISION;

    modifier onlyNotifier() {
        if (msg.sender != NOTIFIER) revert OnlyNotifier();
        _;
    }

    modifier onlyNotifierOrOwner() {
        if (msg.sender != NOTIFIER && msg.sender != owner()) revert OnlyNotifierOrOwner();
        _;
    }

    /// @param _notifier is contract with IERC20 interface with users balances, based based on which
    /// rewards distribution is calculated
    constructor(address _owner, address _notifier) Ownable(_owner) {
        require(_notifier != address(0), ZeroAddress());

        NOTIFIER = _notifier;
    }

    /// @inheritdoc IDistributionManager
    function setDistributionEnd(
        string calldata _incentivesProgram,
        uint40 _distributionEnd
    ) external virtual onlyOwner {
        require(_distributionEnd >= block.timestamp, ISiloIncentivesController.InvalidDistributionEnd());

        bytes32 programId = getProgramId(_incentivesProgram);

        require(_incentivesProgramIds.contains(programId), ISiloIncentivesController.IncentivesProgramNotFound());

        uint256 totalSupply = _shareToken().totalSupply();

        _updateAssetStateInternal(programId, totalSupply);

        incentivesPrograms[programId].distributionEnd = _distributionEnd;

        emit DistributionEndUpdated(_incentivesProgram, _distributionEnd);
    }

    /// @inheritdoc IDistributionManager
    function getDistributionEnd(string calldata _incentivesProgram) external view virtual override returns (uint256) {
        bytes32 incentivesProgramId = getProgramId(_incentivesProgram);
        return incentivesPrograms[incentivesProgramId].distributionEnd;
    }

    /// @inheritdoc IDistributionManager
    function getUserData(address _user, string calldata _incentivesProgram)
        public
        view
        virtual
        override
        returns (uint256)
    {
        bytes32 incentivesProgramId = getProgramId(_incentivesProgram);
        return incentivesPrograms[incentivesProgramId].users[_user];
    }

    /// @inheritdoc IDistributionManager
    function incentivesProgram(string calldata _incentivesProgram)
        external
        view
        virtual
        returns (IncentiveProgramDetails memory details)
    {
        bytes32 incentivesProgramId = getProgramId(_incentivesProgram);

        details = IncentiveProgramDetails(
            incentivesPrograms[incentivesProgramId].index,
            incentivesPrograms[incentivesProgramId].rewardToken,
            incentivesPrograms[incentivesProgramId].emissionPerSecond,
            incentivesPrograms[incentivesProgramId].lastUpdateTimestamp,
            incentivesPrograms[incentivesProgramId].distributionEnd
        );
    }

    /// @inheritdoc IDistributionManager
    function getAllProgramsNames() external view virtual returns (string[] memory programsNames) {
        uint256 length = _incentivesProgramIds.values().length;
        programsNames = new string[](length);

        for (uint256 i = 0; i < length; i++) {
            programsNames[i] = getProgramName(_incentivesProgramIds.values()[i]);
        }
    }

    /// @inheritdoc IDistributionManager
    function getProgramId(string memory _programName) public pure virtual returns (bytes32) {
        uint256 length = bytes(_programName).length;

        if (length == 42) { // expecting a hex string representing an address
            return _getProgramIdForAddress(AddressUtilsLib.fromHexString(_programName));
        }

        // support any non empty string up to 32 characters
        require(length != 0 && length <= 32, InvalidIncentivesProgramName());

        return bytes32(abi.encodePacked(_programName));
    }

    /// @inheritdoc IDistributionManager
    function getProgramName(bytes32 _programId) public view virtual returns (string memory) {
        if (_isImmediateDistributionProgram[_programId]) {
            return Strings.toHexString(uint256(_programId), 20);
        }

        return string(TokenHelper.removeZeros(abi.encodePacked(_programId)));
    }

    /**
     * @dev Updates the state of one distribution, mainly rewards index and timestamp
     * @param incentivesProgramId The id of the incentives program being updated
     * @param totalStaked Current total of staked assets for this distribution
     * @return The new distribution index
     */
    function _updateAssetStateInternal(
        bytes32 incentivesProgramId,
        uint256 totalStaked
    ) internal virtual returns (uint256) {
        uint256 oldIndex = incentivesPrograms[incentivesProgramId].index;
        uint256 emissionPerSecond = incentivesPrograms[incentivesProgramId].emissionPerSecond;
        uint256 lastUpdateTimestamp = incentivesPrograms[incentivesProgramId].lastUpdateTimestamp;
        uint256 distributionEnd = incentivesPrograms[incentivesProgramId].distributionEnd;

        if (block.timestamp == lastUpdateTimestamp) {
            return oldIndex;
        }

        uint256 newIndex = _getIncentivesProgramIndex(
            oldIndex, emissionPerSecond, lastUpdateTimestamp, distributionEnd, totalStaked
        );

        if (newIndex != oldIndex) {
            incentivesPrograms[incentivesProgramId].index = newIndex;
            incentivesPrograms[incentivesProgramId].lastUpdateTimestamp = uint40(block.timestamp);

            emit IncentivesProgramIndexUpdated(getProgramName(incentivesProgramId), newIndex);
        } else {
            incentivesPrograms[incentivesProgramId].lastUpdateTimestamp = uint40(block.timestamp);
        }

        return newIndex;
    }

    /**
     * @dev Updates the state of an user in a distribution
     * @param incentivesProgramId The id of the incentives program being updated
     * @param user The user's address
     * @param stakedByUser Amount of tokens staked by the user in the distribution at the moment
     * @param totalStaked Total tokens staked in the distribution
     * @return The accrued rewards for the user until the moment
     */
    function _updateUserAssetInternal(
        bytes32 incentivesProgramId,
        address user,
        uint256 stakedByUser,
        uint256 totalStaked
    ) internal virtual returns (uint256) {
        uint256 userIndex = incentivesPrograms[incentivesProgramId].users[user];
        uint256 accruedRewards = 0;

        uint256 newIndex = _updateAssetStateInternal(incentivesProgramId, totalStaked);

        if (userIndex != newIndex) {
            if (stakedByUser != 0) {
                accruedRewards = _getRewards(stakedByUser, newIndex, userIndex);
            }

            incentivesPrograms[incentivesProgramId].users[user] = newIndex;

            emit UserIndexUpdated(user, getProgramName(incentivesProgramId), newIndex);
        }

        return accruedRewards;
    }

    /**
     * @dev Used by "frontend" stake contracts to update the data of an user when claiming rewards from there
     * @param _user The address of the user
     * @return accruedRewards The accrued rewards for the user until the moment
     */
    function _accrueRewards(address _user)
        internal
        virtual
        returns (AccruedRewards[] memory accruedRewards)
    {
        accruedRewards = _accrueRewardsForPrograms(_user, _incentivesProgramIds.values());
    }

    /**
     * @dev Accrues rewards for a list of programs
     * @param _user The address of the user
     * @param _programIds The ids of the programs
     * @return accruedRewards The accrued rewards for the user until the moment
     */
    function _accrueRewardsForPrograms(address _user, bytes32[] memory _programIds)
        internal
        virtual
        returns (AccruedRewards[] memory accruedRewards)
    {
        uint256 length = _programIds.length;
        accruedRewards = new AccruedRewards[](length);

        (uint256 userStaked, uint256 totalStaked) = _getScaledUserBalanceAndSupply(_user);

        for (uint256 i = 0; i < length; i++) {
            accruedRewards[i] = _accrueRewards(_user, _programIds[i], totalStaked, userStaked);
        }
    }

    function _accrueRewards(address _user, bytes32 _programId, uint256 _totalStaked, uint256 _userStaked)
        internal
        virtual
        returns (AccruedRewards memory accruedRewards)
    {
        uint256 rewards = _updateUserAssetInternal(
            _programId,
            _user,
            _userStaked,
            _totalStaked
        );

        accruedRewards = AccruedRewards({
            amount: rewards,
            programId: _programId,
            rewardToken: incentivesPrograms[_programId].rewardToken
        });
    }

    /**
     * @dev Return the accrued rewards for an user over a list of distribution
     * @param programId The id of the incentives program being updated
     * @param user The address of the user
     * @param stakedByUser Amount of tokens staked by the user in the distribution at the moment
     * @param totalStaked Total tokens staked in the distribution
     * @return accruedRewards The accrued rewards for the user until the moment
     */
    function _getUnclaimedRewards(bytes32 programId, address user, uint256 stakedByUser, uint256 totalStaked)
        internal
        view
        virtual
        returns (uint256 accruedRewards)
    {
        uint256 userIndex = incentivesPrograms[programId].users[user];

        uint256 incentivesProgramIndex = _getIncentivesProgramIndex(
            incentivesPrograms[programId].index,
            incentivesPrograms[programId].emissionPerSecond,
            incentivesPrograms[programId].lastUpdateTimestamp,
            incentivesPrograms[programId].distributionEnd,
            totalStaked
        );

        accruedRewards = _getRewards(stakedByUser, incentivesProgramIndex, userIndex);
    }

    /**
     * @dev Internal function for the calculation of user's rewards on a distribution
     * @param principalUserBalance Amount staked by the user on a distribution
     * @param reserveIndex Current index of the distribution
     * @param userIndex Index stored for the user, representation his staking moment
     * @return rewards The rewards
     */
    function _getRewards(
        uint256 principalUserBalance,
        uint256 reserveIndex,
        uint256 userIndex
    ) internal pure virtual returns (uint256 rewards) {
        rewards = Math.mulDiv(principalUserBalance, (reserveIndex - userIndex), TEN_POW_PRECISION);
    }

    /**
     * @dev Calculates the next value of an specific distribution index, with validations
     * @param currentIndex Current index of the distribution
     * @param emissionPerSecond Representing the total rewards distributed per second per asset unit,
     * on the distribution
     * @param lastUpdateTimestamp Last moment this distribution was updated
     * @param distributionEnd The end of the distribution
     * @param totalBalance of tokens considered for the distribution
     * @return newIndex The new index.
     */
    function _getIncentivesProgramIndex(
        uint256 currentIndex,
        uint256 emissionPerSecond,
        uint256 lastUpdateTimestamp,
        uint256 distributionEnd,
        uint256 totalBalance
    ) internal view virtual returns (uint256 newIndex) {
        if (
            emissionPerSecond == 0 ||
            totalBalance == 0 ||
            lastUpdateTimestamp == block.timestamp ||
            lastUpdateTimestamp >= distributionEnd
        ) {
            return currentIndex;
        }

        uint256 currentTimestamp = block.timestamp > distributionEnd ? distributionEnd : block.timestamp;
        uint256 timeDelta = currentTimestamp - lastUpdateTimestamp;

        require(emissionPerSecond <= type(uint256).max / timeDelta, EmissionForTimeDeltaOverflow());
        uint256 emissionForTimeDelta = emissionPerSecond * timeDelta;

        require(emissionForTimeDelta / totalBalance <= type(uint256).max / TEN_POW_PRECISION, IndexOverflow());
        newIndex = Math.mulDiv(emissionForTimeDelta, TEN_POW_PRECISION, totalBalance);

        require(newIndex < type(uint256).max - currentIndex, NewIndexOverflow());
        newIndex += currentIndex;
    }

    function _shareToken() internal view virtual returns (IERC20 shareToken) {
        shareToken = IERC20(NOTIFIER);
    }

    function _getScaledUserBalanceAndSupply(address _user)
        internal
        view
        virtual
        returns (uint256 userBalance, uint256 totalSupply)
    {
        userBalance = _shareToken().balanceOf(_user);
        totalSupply = _shareToken().totalSupply();
    }

    /**
     * @dev Returns the id of an incentives program (converts address to bytes32)
     * @param _addressAsName The address of the reward token for immediate distribution
     * @return The id of the incentives program
     */
    function _getProgramIdForAddress(address _addressAsName) internal pure virtual returns (bytes32) {
        return bytes32(uint256(uint160(_addressAsName)));
    }
}
