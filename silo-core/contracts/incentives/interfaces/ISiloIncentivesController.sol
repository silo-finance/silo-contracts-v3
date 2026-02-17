// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.28;

import {IDistributionManager} from "./IDistributionManager.sol";
import {DistributionTypes} from "../lib/DistributionTypes.sol";

interface ISiloIncentivesController is IDistributionManager {
    event ClaimerSet(address indexed user, address indexed claimer);
    event IncentivesProgramCreated(string name);
    event IncentivesProgramUpdated(string name);
    event ImmediateDistribution(address indexed rewardToken, bytes32 indexed programId, uint256 amount);

    event RewardsAccrued(
        address indexed user,
        address indexed rewardToken,
        string indexed programName,
        uint256 amount
    );

    event RewardsClaimed(
        address indexed user,
        address indexed to,
        address indexed rewardToken,
        bytes32 programId,
        address claimer,
        uint256 amount
    );

    error InvalidDistributionEnd();
    error InvalidConfiguration();
    error IndexOverflowAtEmissionsPerSecond();
    error InvalidToAddress();
    error InvalidUserAddress();
    error ClaimerUnauthorized();
    error InvalidRewardToken();
    error IncentivesProgramAlreadyExists();
    error IncentivesProgramNotFound();
    error DifferentRewardsTokens();
    error EmissionPerSecondTooHigh();
    error EmptyShareToken();

    /**
     * @dev Silo share token event handler
     * @param _sender The address of the sender
     * @param _senderBalance The balance of the sender
     * @param _recipient The address of the recipient
     * @param _recipientBalance The balance of the recipient
     * @param _totalSupply The total supply of the asset in the lending pool
     * @param _amount The amount of the transfer
     */
    function afterTokenTransfer(
        address _sender,
        uint256 _senderBalance,
        address _recipient,
        uint256 _recipientBalance,
        uint256 _totalSupply,
        uint256 _amount
    ) external;

    /**
     * @dev Immediately distributes rewards to the incentives program
     * Expect an `_amount` to be transferred to the contract before calling this fn
     * @param _tokenToDistribute The token to distribute
     * @param _amount The amount of rewards to distribute
     * @return programId The id of the created or existing program, or bytes32(0) if _amount is 0
     */
    function immediateDistribution(address _tokenToDistribute, uint256 _amount) external returns (bytes32 programId);

    /// @dev It will transfer all the reward token balance to the owner.
    /// @param _rewardToken The reward token to rescue
    function rescueRewards(address _rewardToken) external;

    /**
     * @dev Whitelists an address to claim the rewards on behalf of another address
     * @param _user The address of the user
     * @param _claimer The address of the claimer
     */
    function setClaimer(address _user, address _claimer) external;

    /**
     * @dev Creates a new incentives program
     * @param _incentivesProgramInput The incentives program creation input
     */
    function createIncentivesProgram(DistributionTypes.IncentivesProgramCreationInput memory _incentivesProgramInput)
        external;

    /**
     * @dev Updates an existing incentives program
     * @param _incentivesProgram The incentives program name
     * @param _distributionEnd The distribution end
     * @param _emissionPerSecond The emission per second
     */
    function updateIncentivesProgram(
        string calldata _incentivesProgram,
        uint40 _distributionEnd,
        uint256 _emissionPerSecond
    ) external;

    /**
     * @dev Claims reward for an user to the desired address, on all the assets of the lending pool,
     * accumulating the pending rewards
     * @param _to Address that will be receiving the rewards
     * @return accruedRewards
     */
    function claimRewards(address _to) external returns (AccruedRewards[] memory accruedRewards);

    /**
     * @dev Claims reward for an user to the desired address, on all the assets of the lending pool,
     * accumulating the pending rewards
     * @param _to Address that will be receiving the rewards
     * @param _programNames The incentives program names
     * @return accruedRewards
     */
    function claimRewards(address _to, string[] calldata _programNames)
        external
        returns (AccruedRewards[] memory accruedRewards);

    /**
     * @dev Claims reward for an user on behalf, on all the assets of the lending pool, accumulating the pending
     * rewards. The caller must be whitelisted via "allowClaimOnBehalf" function by the RewardsAdmin role manager
     * @param _user Address to check and claim rewards
     * @param _to Address that will be receiving the rewards
     * @param _programNames The incentives program names
     * @return accruedRewards
     */
    function claimRewardsOnBehalf(address _user, address _to, string[] calldata _programNames)
        external
        returns (AccruedRewards[] memory accruedRewards);

    /**
     * @dev Returns the whitelisted claimer for a certain address (0x0 if not set)
     * @param _user The address of the user
     * @return The claimer address
     */
    function getClaimer(address _user) external view returns (address);

    /**
     * @dev Returns the total of rewards of an user, already accrued + not yet accrued
     * @param _user The address of the user
     * @param _programName The incentives program name
     * @return unclaimedRewards
     */
    function getRewardsBalance(address _user, string calldata _programName)
        external
        view
        returns (uint256 unclaimedRewards);

    /**
     * @dev Returns the total of rewards of an user, already accrued + not yet accrued
     * @param _user The address of the user
     * @param _programNames The incentives program names (should have the same rewards token)
     * @return unclaimedRewards
     */
    function getRewardsBalance(address _user, string[] calldata _programNames)
        external
        view
        returns (uint256 unclaimedRewards);

    /**
     * @dev returns the unclaimed rewards of the user
     * @param _user the address of the user
     * @param _programName The incentives program name
     * @return the unclaimed user rewards
     */
    function getUserUnclaimedRewards(address _user, string calldata _programName) external view returns (uint256);

    /// @notice SHARE_TOKEN is contract with IERC20 interface with users balances, based based on which
    /// rewards distribution is calculated. In Silo it is ususally collateral share token or debt share token.
    function SHARE_TOKEN() external view returns (address); // solhint-disable-line func-name-mixedcase
}
