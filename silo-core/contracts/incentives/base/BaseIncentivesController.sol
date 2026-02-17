// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.28;

// solhint-disable func-name-mixedcase, ordering

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "openzeppelin5/utils/structs/EnumerableSet.sol";

import {DistributionTypes} from "../lib/DistributionTypes.sol";
import {DistributionManager} from "./DistributionManager.sol";
import {ISiloIncentivesController} from "../interfaces/ISiloIncentivesController.sol";

/**
 * @title BaseIncentivesController
 * @notice Abstract contract template to build Distributors contracts for ERC20 rewards to protocol participants
 * @author Aave
  */
abstract contract BaseIncentivesController is DistributionManager, ISiloIncentivesController {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using SafeERC20 for IERC20;

    uint256 public constant MAX_EMISSION_PER_SECOND = 1e30;

    mapping(address user => mapping(bytes32 programId => uint256 unclaimedRewards)) internal _usersUnclaimedRewards;

    // this mapping allows whitelisted addresses to claim on behalf of others
    // useful for contracts that hold tokens to be rewarded but don't have any native logic to claim Liquidity Mining
    // rewards
    mapping(address user => address claimer) internal _authorizedClaimers;

    modifier onlyAuthorizedClaimers(address claimer, address user) {
        if (_authorizedClaimers[user] != claimer) revert ClaimerUnauthorized();

        _;
    }

    modifier inputsValidation(address _user, address _to) {
        if (_user == address(0)) revert InvalidUserAddress();
        if (_to == address(0)) revert InvalidToAddress();

        _;
    }

    constructor(address _owner, address _notifier) DistributionManager(_owner, _notifier) {}

    /// @inheritdoc ISiloIncentivesController
    function createIncentivesProgram(DistributionTypes.IncentivesProgramCreationInput memory _incentivesProgramInput)
        external
        virtual
        onlyOwner
    {
        uint256 programNameLength = bytes(_incentivesProgramInput.name).length;

        require(programNameLength <= 32, TooLongProgramName());
        require(_incentivesProgramInput.emissionPerSecond < MAX_EMISSION_PER_SECOND, EmissionPerSecondTooHigh());
        require(_incentivesProgramInput.distributionEnd >= block.timestamp, InvalidDistributionEnd());

        bytes32 programId = getProgramId(_incentivesProgramInput.name);

        _createIncentiveProgram(programId, _incentivesProgramInput);
    }

    /// @inheritdoc ISiloIncentivesController
    function updateIncentivesProgram(
        string calldata _incentivesProgram,
        uint40 _distributionEnd,
        uint256 _emissionPerSecond
    ) external virtual onlyOwner {
        require(_distributionEnd >= block.timestamp, InvalidDistributionEnd());
        require(_emissionPerSecond < MAX_EMISSION_PER_SECOND, EmissionPerSecondTooHigh());

        bytes32 programId = getProgramId(_incentivesProgram);

        require(_incentivesProgramIds.contains(programId), IncentivesProgramNotFound());

        uint256 totalSupply = _shareToken().totalSupply();

        _updateAssetStateInternal(programId, totalSupply);

        incentivesPrograms[programId].distributionEnd = _distributionEnd;
        incentivesPrograms[programId].emissionPerSecond = _emissionPerSecond;

        emit IncentivesProgramUpdated(_incentivesProgram);
    }

    /// @inheritdoc ISiloIncentivesController
    function getRewardsBalance(address _user, string calldata _programName)
        external
        view
        virtual
        returns (uint256 unclaimedRewards)
    {
        bytes32 programId = getProgramId(_programName);

        (uint256 stakedByUser, uint256 totalStaked) = _getScaledUserBalanceAndSupply(_user);

        unclaimedRewards = _getRewardsBalance(_user, programId, stakedByUser, totalStaked);
    }

    /// @inheritdoc ISiloIncentivesController
    function getRewardsBalance(address _user, string[] calldata _programNames)
        external
        view
        virtual
        returns (uint256 unclaimedRewards)
    {
        address rewardsToken;

        (uint256 stakedByUser, uint256 totalStaked) = _getScaledUserBalanceAndSupply(_user);

        for (uint256 i = 0; i < _programNames.length; i++) {
            bytes32 programId = getProgramId(_programNames[i]);

            address programRewardsToken = incentivesPrograms[programId].rewardToken;

            if (rewardsToken == address(0)) {
                rewardsToken = programRewardsToken;
            } else if (rewardsToken != programRewardsToken) {
                revert DifferentRewardsTokens();
            }

            unclaimedRewards += _getRewardsBalance(_user, programId, stakedByUser, totalStaked);
        }
    }

    /// @dev Internal function to get the rewards balance for a user and a program
    function _getRewardsBalance(address _user, bytes32 _programId, uint256 _stakedByUser, uint256 _totalStaked)
        internal
        view
        virtual
        returns (uint256 unclaimedRewards)
    {
        unclaimedRewards = _usersUnclaimedRewards[_user][_programId];
        unclaimedRewards += _getUnclaimedRewards(_programId, _user, _stakedByUser, _totalStaked);
    }

    /// @inheritdoc ISiloIncentivesController
    function claimRewards(address _to) external virtual returns (AccruedRewards[] memory accruedRewards) {
        if (_to == address(0)) revert InvalidToAddress();

        accruedRewards = _accrueRewards(msg.sender);
        _claimRewards(msg.sender, msg.sender, _to, accruedRewards);
    }

    /// @inheritdoc ISiloIncentivesController
    function claimRewards(address _to, string[] calldata _programNames)
        external
        virtual
        returns (AccruedRewards[] memory accruedRewards)
    {
        if (_to == address(0)) revert InvalidToAddress();

        bytes32[] memory programIds = _getProgramsIds(_programNames);

        _requireExistingPrograms(programIds);

        accruedRewards = _accrueRewardsForPrograms(msg.sender, programIds);
        _claimRewards(msg.sender, msg.sender, _to, accruedRewards);
    }

    /// @inheritdoc ISiloIncentivesController
    function claimRewardsOnBehalf(address _user, address _to, string[] calldata _programNames)
        external
        virtual
        onlyAuthorizedClaimers(msg.sender, _user)
        inputsValidation(_user, _to)
        returns (AccruedRewards[] memory accruedRewards)
    {
        bytes32[] memory programIds = _getProgramsIds(_programNames);

        _requireExistingPrograms(programIds);

        accruedRewards = _accrueRewardsForPrograms(_user, programIds);
        _claimRewards(msg.sender, _user, _to, accruedRewards);
    }

    /// @inheritdoc ISiloIncentivesController
    function setClaimer(address _user, address _caller) external virtual onlyOwner {
        require(_user != address(0), ZeroAddress());
        require(_caller != address(0), ZeroAddress());

        _authorizedClaimers[_user] = _caller;
        emit ClaimerSet(_user, _caller);
    }

    /// @inheritdoc ISiloIncentivesController
    function getClaimer(address _user) external view virtual returns (address) {
        return _authorizedClaimers[_user];
    }

    /// @inheritdoc ISiloIncentivesController
    function getUserUnclaimedRewards(address _user, string calldata _programName)
        external
        view
        virtual
        returns (uint256)
    {
        bytes32 programId = getProgramId(_programName);
        return _usersUnclaimedRewards[_user][programId];
    }

    /**
     * @dev Called by the corresponding asset on any update that affects the rewards distribution
     * @param _incentivesProgramId The id of the incentives program being updated
     * @param _user The address of the user
     * @param _totalSupply The total supply of the asset in the lending pool
     * @param _userBalance The balance of the user of the asset in the lending pool
     */
    function _handleAction(
        bytes32 _incentivesProgramId,
        address _user,
        uint256 _totalSupply,
        uint256 _userBalance
    ) internal virtual {
        uint256 accruedRewards = _updateUserAssetInternal(_incentivesProgramId, _user, _userBalance, _totalSupply);

        if (accruedRewards != 0) {
            uint256 newUnclaimedRewards = _usersUnclaimedRewards[_user][_incentivesProgramId] + accruedRewards;
            _usersUnclaimedRewards[_user][_incentivesProgramId] = newUnclaimedRewards;

            emit RewardsAccrued(
                _user,
                incentivesPrograms[_incentivesProgramId].rewardToken,
                getProgramName(_incentivesProgramId),
                newUnclaimedRewards
            );
        }
    }

    /**
     * @dev Claims rewards on the user's behalf, on all the assets of the lending pool, accumulating the pending rewards
     * @param claimer Address to check and claim rewards
     * @param user Address to check and claim rewards
     * @param to Address that will be receiving the rewards
     */
    function _claimRewards(
        address claimer,
        address user,
        address to,
        AccruedRewards[] memory accruedRewards
    ) internal virtual {
        for (uint256 i = 0; i < accruedRewards.length; i++) {
            uint256 unclaimedRewards = _usersUnclaimedRewards[user][accruedRewards[i].programId];

            uint256 amountToClaim = accruedRewards[i].amount + unclaimedRewards;

            if (amountToClaim != 0) {
                if (accruedRewards[i].amount != 0) {
                    emit RewardsAccrued(
                        user,
                        accruedRewards[i].rewardToken,
                        getProgramName(accruedRewards[i].programId),
                        accruedRewards[i].amount
                    );
                }

                _usersUnclaimedRewards[user][accruedRewards[i].programId] = 0;

                _transferRewards(accruedRewards[i].rewardToken, to, amountToClaim);

                emit RewardsClaimed(
                    user,
                    to,
                    accruedRewards[i].rewardToken,
                    accruedRewards[i].programId,
                    claimer,
                    amountToClaim
                );

                // updating the accrued rewards amount to include unclaimed rewards
                accruedRewards[i].amount = amountToClaim;
            }
        }
    }

    /**
     * @dev Creates a new incentive program
     * @param _incentivesProgramInput The incentives program creation input
     */
    function _createIncentiveProgram(
        bytes32 _programId,
        DistributionTypes.IncentivesProgramCreationInput memory _incentivesProgramInput
    ) internal virtual {
        require(_incentivesProgramInput.rewardToken != address(0), InvalidRewardToken());
        require(_incentivesProgramIds.add(_programId), IncentivesProgramAlreadyExists());

        incentivesPrograms[_programId].rewardToken = _incentivesProgramInput.rewardToken;
        incentivesPrograms[_programId].distributionEnd = _incentivesProgramInput.distributionEnd;
        incentivesPrograms[_programId].emissionPerSecond = _incentivesProgramInput.emissionPerSecond;
        incentivesPrograms[_programId].lastUpdateTimestamp = uint40(block.timestamp);

        emit IncentivesProgramCreated(_incentivesProgramInput.name);
    }

    /**
     * @dev Checks if the programs exist
     * Reverts if any of the programs does not exist in the `_incentivesProgramIds` list
     * @param _programIds The program ids
     */
    function _requireExistingPrograms(bytes32[] memory _programIds) internal view virtual {
        for (uint256 i = 0; i < _programIds.length; i++) {
            require(_incentivesProgramIds.contains(_programIds[i]), IncentivesProgramNotFound());
        }
    }

    /**
     * @dev Returns the program ids for a list of program names
     * @param _programNames The program names
     * @return programIds The program ids
     */
    function _getProgramsIds(string[] calldata _programNames)
        internal
        pure
        virtual
        returns (bytes32[] memory programIds)
    {
        programIds = new bytes32[](_programNames.length);

        for (uint256 i = 0; i < _programNames.length; i++) {
            programIds[i] = getProgramId(_programNames[i]);
        }
    }

    /**
     * @dev Abstract function to transfer rewards to the desired account
     * @param rewardToken Reward token address
     * @param to Account address to send the rewards
     * @param amount Amount of rewards to transfer
     */
    function _transferRewards(address rewardToken, address to, uint256 amount) internal virtual {
        IERC20(rewardToken).safeTransfer(to, amount);
    }
}
