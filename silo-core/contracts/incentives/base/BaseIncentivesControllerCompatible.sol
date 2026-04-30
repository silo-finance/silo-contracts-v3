// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {ISiloIncentivesController} from "../interfaces/ISiloIncentivesController.sol";
import {IBackwardsCompatibleGaugeLike} from "../interfaces/IBackwardsCompatibleGaugeLike.sol";
import {DistributionTypes} from "../lib/DistributionTypes.sol";

abstract contract BaseIncentivesControllerCompatible is IBackwardsCompatibleGaugeLike, ISiloIncentivesController {
    /// @notice Whether the gauge is killed
    /// @dev This flag is not used in the SiloIncentivesController,
    /// but it is used in the Gauge hook receiver (versions <= 3.7.0).
    bool internal _isKilled;

    event GaugeKilled();
    event GaugeUnKilled();

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    function killGauge() external virtual onlyOwner {
        _isKilled = true;
        emit GaugeKilled();
    }

    function unkillGauge() external virtual onlyOwner {
        _isKilled = false;
        emit GaugeUnKilled();
    }

    // solhint-disable-next-line func-name-mixedcase
    function is_killed() external view virtual returns (bool) {
        return _isKilled;
    }

    function setDistributionEnd(string calldata, uint40) external pure {
        // do nothing
    }

    function getDistributionEnd(string calldata) external pure returns (uint256) {
        return 0;
    }

    function getUserData(address, string calldata) external pure returns (uint256) {
        return 0;
    }

    function incentivesProgram(string calldata) external pure returns (IncentiveProgramDetails memory details) {
        // do nothing
    }

    function getAllProgramsNames() external pure returns (string[] memory programsNames) {
        programsNames = new string[](0);
    }

    function getProgramName(bytes32) external pure returns (string memory programName) {
        programName = "";
    }

    function getProgramId(string calldata) external pure returns (bytes32 programId) {
        programId = bytes32(0);
    }

    function immediateDistribution(address, uint256) external pure returns (bytes32 programId) {
        programId = bytes32(0);
    }

    function rescueRewards(address) external pure {
        // do nothing
    }

    function setClaimer(address, address) external pure {
        // do nothing
    }

    function createIncentivesProgram(DistributionTypes.IncentivesProgramCreationInput memory) external pure {
        // do nothing
    }

    function updateIncentivesProgram(string calldata, uint40, uint256) external pure {
        // do nothing
    }

    function claimRewards(address) external pure returns (AccruedRewards[] memory accruedRewards) {
        accruedRewards = new AccruedRewards[](0);
    }

    function claimRewards(address, string[] calldata) external pure returns (AccruedRewards[] memory accruedRewards) {
        // do nothing
    }

    function claimRewardsOnBehalf(address, address, string[] calldata)
        external
        pure
        returns (AccruedRewards[] memory accruedRewards)
    {
        // do nothing
    }

    function getClaimer(address) external pure returns (address) {
        return address(0);
    }

    function getRewardsBalance(address, string calldata) external pure returns (uint256 unclaimedRewards) {
        unclaimedRewards = 0;
    }

    function getRewardsBalance(address, string[] calldata) external pure returns (uint256 unclaimedRewards) {
        unclaimedRewards = 0;
    }

    function getUserUnclaimedRewards(address, string calldata) external pure returns (uint256) {
        return 0;
    }

    function afterTokenTransfer(
        address _sender,
        uint256 _senderBalance,
        address _recipient,
        uint256 _recipientBalance,
        uint256 _totalSupply,
        uint256 _amount
    ) public virtual override(IBackwardsCompatibleGaugeLike, ISiloIncentivesController);

    function _onlyOwner() internal view virtual;
}
