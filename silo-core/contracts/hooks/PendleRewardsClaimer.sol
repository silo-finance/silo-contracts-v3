// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {Math} from "openzeppelin5/utils/math/Math.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IHookReceiver} from "silo-core/contracts/interfaces/IHookReceiver.sol";
import {IPendleMarketLike} from "silo-core/contracts/interfaces/IPendleMarketLike.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {IPendleRewardsClaimer} from "silo-core/contracts/interfaces/IPendleRewardsClaimer.sol";
import {GaugeHookReceiver} from "silo-core/contracts/hooks/gauge/GaugeHookReceiver.sol";
import {PartialLiquidation} from "silo-core/contracts/hooks/liquidation/PartialLiquidation.sol";
import {BaseHookReceiver} from "silo-core/contracts/hooks/_common/BaseHookReceiver.sol";
import {Hook} from "silo-core/contracts/lib/Hook.sol";
import {ShareTokenLib} from "silo-core/contracts/lib/ShareTokenLib.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";

/// @title PendleRewardsClaimer
/// @notice This hook allows to redeem rewards from Pendle for the silo.
contract PendleRewardsClaimer is GaugeHookReceiver, PartialLiquidation, IPendleRewardsClaimer {
    using SafeERC20 for IERC20;
    using Hook for uint256;

    IPendleMarketLike public pendleMarket;
    ISilo public pendleMarketSilo;
    IShareToken public protectedShareToken;

    /// @notice The flag that show if the rewards were claimed.
    /// @dev Due to the Pendle incentives distribution mechanism, rewards can only be claimed once per block.
    bool transient internal _rewardsClaimed;

    /// @inheritdoc IHookReceiver
    function initialize(ISiloConfig _config, bytes calldata _data)
        public
        initializer
        virtual
    {
        (address owner) = abi.decode(_data, (address));

        BaseHookReceiver.__BaseHookReceiver_init(_config);
        GaugeHookReceiver.__GaugeHookReceiver_init(owner);
        PendleRewardsClaimer.__PendleRewardsClaimer_init();
    }

    /// @notice Redeem rewards from Pendle
    /// @dev Redeem rewards from Pendle and transfer them to the incentives controller for immediate distribution.
    /// This function is designed to be called by the hook from the silo via delegatecall.
    /// @param _market Pendle market address
    /// @param _incentivesController Incentives controller address
    /// @return rewardTokens Reward tokens
    /// @return rewards Rewards for collateral token
    function redeemRewardsFromPendle(
        IPendleMarketLike _market,
        ISiloIncentivesController _incentivesController
    )
        external
        virtual
        returns (
            address[] memory rewardTokens,
            uint256[] memory rewards
        )
    {
        rewardTokens = _market.getRewardTokens();
        _market.redeemRewards({user: address(this)}); // address(this) is a Silo as we do a delegatecall.
        rewards = new uint256[](rewardTokens.length);

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];
            // Pendle should never distribute rewards in the Pendle market LP tokens.
            // However, we have this check in place as a safety measure,
            // so we will ensure that we do not transfer assets from the Silo balance.
            if (rewardToken == address(_market)) continue;

            uint256 rewardAmount = IERC20(rewardToken).balanceOf(address(this));
            if (rewardAmount == 0) continue;

            IERC20(rewardToken).safeTransfer(address(_incentivesController), rewardAmount);
            rewards[i] = rewardAmount;
        }
    }

    /// @inheritdoc IHookReceiver
    function beforeAction(address /* _silo */, uint256 _action, bytes calldata /* _inputAndOutput */)
        public
        virtual
        onlySilo()
        override
    {
        uint256 collateralDepositAction = Hook.depositAction(ISilo.CollateralType.Collateral);
        uint256 protectedTransitionAction = Hook.transitionCollateralAction(ISilo.CollateralType.Protected);

        require(!_action.matchAction(collateralDepositAction), CollateralDepositNotAllowed());
        require(!_action.matchAction(protectedTransitionAction), TransitionProtectedCollateralNotAllowed());

        redeemRewards();
    }

    /// @inheritdoc IHookReceiver
    function afterAction(address _silo, uint256 _action, bytes calldata _inputAndOutput)
        public
        virtual
        onlySiloOrShareToken()
        override(GaugeHookReceiver, IHookReceiver)
    {
        // As we have configured all before actions to be executed,
        // we expect that rewards be redeemed in the before action. But, share tokens do not have before action hook.
        // Therefore, we need to verify if this is a protected share token transfer,
        // and if so, we must redeem the rewards.
        uint256 protectedTransferAction = Hook.shareTokenTransfer(Hook.PROTECTED_TOKEN);
        if (protectedTransferAction.matchAction(_action)) redeemRewards();

        GaugeHookReceiver.afterAction(_silo, _action, _inputAndOutput);
    }

    /// @notice Redeem rewards from Pendle for the Silo
    /// @dev Redeem rewards from Pendle and transfer them to the incentives controller for immediate distribution.
    /// @return rewardTokens Reward tokens
    /// @return rewards Rewards for collateral token
    function redeemRewards() public virtual returns (address[] memory rewardTokens, uint256[] memory rewards) {
        if (_rewardsClaimed) return (rewardTokens, rewards);

        ISilo silo = pendleMarketSilo;
        ISiloIncentivesController controller = _getIncentivesControllerSafe();
        bytes memory input = abi.encodeWithSelector(this.redeemRewardsFromPendle.selector, pendleMarket, controller);

        // We limit the gas to 5M to prevent the silo from being locked in the case of any issues in the Pendle market.
        // From our tests, we observe that for the market with two reward tokens,
        // when we accrue rewards in one of these tokens, this call requires ~200,000 gas.
        (bool success, bytes memory data) = silo.callOnBehalfOfSilo{gas: 5_000_000}({
            _target: address(this),
            _value: 0,
            _callType: ISilo.CallType.Delegatecall,
            _input: input
        });

        if (!success) {
            emit FailedToClaimIncentives(silo);
            return (rewardTokens, rewards);
        }

        (rewardTokens, rewards) = abi.decode(data, (address[], uint256[]));

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            uint256 rewardAmount = rewards[i];
            if (rewardAmount == 0) continue;

            controller.immediateDistribution(rewardTokens[i], rewardAmount);
        }

        _rewardsClaimed = true;
    }

    /// @notice Initialize the `PendleRewardsClaimer`
    /// @dev Initialize the `PendleRewardsClaimer` by detecting the Pendle market and Silo.
    /// Also, configure the hooks for the Silo.
    function __PendleRewardsClaimer_init() internal onlyInitializing virtual {
        (address silo, IPendleMarketLike market) = _getPendleMarketSilo();

        _configureHooks(silo);

        (address siloProtectedShareToken,,) = siloConfig.getShareTokens(silo);

        pendleMarketSilo = ISilo(silo);
        pendleMarket = market;
        protectedShareToken = IShareToken(siloProtectedShareToken);
    }

    /// @notice Get the Pendle market and Silo
    /// @dev The Pendle market is always should be assets of the Silo0.
    function _getPendleMarketSilo() private returns (address silo, IPendleMarketLike market) {
        (silo,) = siloConfig.getSilos();

        market = IPendleMarketLike(ISilo(silo).asset());
        // Sanity calls to the Pendle market
        market.getRewardTokens();
        market.redeemRewards(address(this));
    }

    /// @notice Configure the hooks for the silo
    /// @param _silo Silo address
    function _configureHooks(address _silo) private {
        // We require all before actions to be configured
        uint24 hooksBefore = type(uint24).max;

        uint256 hooksAfter = _getHooksAfter(_silo);
        uint256 protectedTransferAction = Hook.shareTokenTransfer(Hook.PROTECTED_TOKEN);
        hooksAfter = hooksAfter.addAction(protectedTransferAction);

        _setHookConfig(_silo, hooksBefore, uint24(hooksAfter));
    }

    /// @notice Get the incentives controller from the `GaugeHookReceiver` configuration.
    /// @dev Reverts if the incentives controller is not configured.
    /// @return controller
    function _getIncentivesControllerSafe() private view returns (ISiloIncentivesController controller) {
        controller = ISiloIncentivesController(address(configuredGauges[protectedShareToken]));
        require(address(controller) != address(0), IncentivesControllerRequired());
    }
}
