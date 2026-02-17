// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {console2} from "forge-std/console2.sol";

import {Strings} from "openzeppelin5/utils/Strings.sol";

import {IERC3156FlashLender} from "silo-core/contracts/interfaces/IERC3156FlashLender.sol";
import {IGeneralSwapModule} from "silo-core/contracts/interfaces/IGeneralSwapModule.sol";
import {IPartialLiquidationByDefaulting} from "silo-core/contracts/interfaces/IPartialLiquidationByDefaulting.sol";
import {PausableWithAccessControl} from "common/utils/PausableWithAccessControl.sol";
import {RescueModule} from "silo-core/contracts/leverage/modules/RescueModule.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {Actor} from "silo-core/test/invariants/utils/Actor.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";

// Libraries

// Test Contracts
import {BaseHandlerDefaulting} from "../../base/BaseHandlerDefaulting.t.sol";
import {TestERC20} from "silo-core/test/invariants/utils/mocks/TestERC20.sol";
import {TestWETH} from "silo-core/test/echidna-leverage/utils/mocks/TestWETH.sol";
import {MockSiloOracle} from "silo-core/test/invariants/utils/mocks/MockSiloOracle.sol";

/*
- if LTV > LT_MARGIN, defaulting never reverts (notice: cap)
- 1 wei debt liquidation: possible! keeper will not get any rewards - DO UNIT TEST FOR THIS!

Potential risks:
- liquidation breaks VAULT standard 
- there is no user input, so there is no risk from "outside" 
- "weird" liquidation eg 1 wei do weird stuff
*/

/// @title DefaultingHandler
/// @notice Handler test contract for a set of actions
contract DefaultingHandler is BaseHandlerDefaulting {
    uint256 borrowerLtvBeforeLastLiquidation;

    function liquidationCallByDefaulting(RandomGenerator memory _random)
        external
        setupRandomActor(_random.i)
    {
        bool success;
        bytes memory returnData;

        // only actors can borrow
        address borrower = _getRandomActor(_random.j);

        _setTargetActor(_getRandomActor(_random.i));

        _before();

        borrowerLtvBeforeLastLiquidation = siloLens.getLtv(vault0, borrower);

        _printMaxLiquidation(borrower);
        _printLtv(borrower);

        (success, returnData) = actor.proxy(
            address(liquidationModule),
            abi.encodeWithSignature("liquidationCallByDefaulting(address)", borrower)
        );

        _after();

        if (success) {
            (, uint256 repayDebtAssets) = abi.decode(returnData, (uint256, uint256));
            assertGt(repayDebtAssets, 0, "repayDebtAssets should be greater than 0 on any liquidation");

            assertLt(
                defaultVarsAfter[address(vault1)].debtAssets,
                defaultVarsBefore[address(vault1)].debtAssets,
                "debt assets should decrease after liquidation"
            );
        }

        if (success) {
            _assert_defaulting_totalAssetsDoesNotChange();
            _assets_defaultingDoesNotCreateLossWhenNoBadDebt();
        }
    }

    function assert_claimRewardsCanBeAlwaysDone(uint8 _actorIndex) external setupRandomActor(_actorIndex) {
        bool success;
        bytes memory returnData;

        // we will NEVER claim rewards form actor[0], that one will be used for checking rule about rewards balance
        if (address(actor) == _getRandomActor(0)) return;

        (success, returnData) = actor.proxy(address(gauge), abi.encodeWithSignature("claimRewards(address)", actor));

        if (!success) revert("claimRewards failed");
    }

    /*
    total supply of collateral and protected must stay the same before and after liquidation
    */
    function _assert_defaulting_totalAssetsDoesNotChange() internal {
        assertEq(
            defaultVarsBefore[address(vault0)].totalAssets,
            defaultVarsAfter[address(vault0)].totalAssets,
            "[silo0] total collateral assets should not change after defaulting (on collateral silo)"
        );

        assertEq(
            defaultVarsBefore[address(vault0)].totalProtectedAssets,
            defaultVarsAfter[address(vault0)].totalProtectedAssets,
            "[silo0] total protected assets should not change after defaulting (on collateral silo)"
        );

        assertEq(
            defaultVarsBefore[address(vault1)].totalProtectedAssets,
            defaultVarsAfter[address(vault1)].totalProtectedAssets,
            "[silo1] total protected assets should not change after defaulting (on debt silo)"
        );
    }

    /*
    for defaulting we expect price to be 1:1, so that's why this asertions
    */
    function assert_defaulting_price1() external {
        assertEq(
            siloConfig.getConfig(address(vault0)).solvencyOracle,
            address(0),
            "price0 should be 1:1 for echidna setup for defaulting, cfg: HOOK_V2"
        );

        assertEq(
            siloConfig.getConfig(address(vault1)).solvencyOracle,
            address(0),
            "price1 should be 1:1 for echidna setup for defaulting, cfg: HOOK_V2"
        );
    }

    /*
    in case price 1:1 defaulting should not create any loss (if done before bad debt)
    */
    function _assets_defaultingDoesNotCreateLossWhenNoBadDebt() internal {
        if (borrowerLtvBeforeLastLiquidation >= 1e18) return;

        (address protected0, address collateral0, address debt0) = siloConfig.getShareTokens(address(vault0));
        (address protected1, address collateral1, address debt1) = siloConfig.getShareTokens(address(vault1));

        for (uint256 i; i < actorAddresses.length; i++) {
            address actor = actorAddresses[i];

            // we can sum up two assets only because price is 1:1!
            uint256 totalCollateralBefore =
                actorsBalanceBefore[actor][collateral0].assets + actorsBalanceBefore[actor][collateral1].assets;
            uint256 totalProtectedBefore =
                actorsBalanceBefore[actor][protected0].assets + actorsBalanceBefore[actor][protected1].assets;

            uint256 totalCollateralAfter =
                actorsBalanceAfter[actor][collateral0].assets + actorsBalanceAfter[actor][collateral1].assets;
            uint256 totalProtectedAfter =
                actorsBalanceAfter[actor][protected0].assets + actorsBalanceAfter[actor][protected1].assets;

            uint256 totalDebtBefore =
                actorsBalanceBefore[actor][debt0].assets + actorsBalanceBefore[actor][debt1].assets;
            uint256 totalDebtAfter = actorsBalanceAfter[actor][debt0].assets + actorsBalanceAfter[actor][debt1].assets;

            uint256 gaugeAssetsBefore = actorsBalanceBefore[actor][address(gauge)].assets;
            uint256 gaugeAssetsAfter = actorsBalanceAfter[actor][address(gauge)].assets;

            uint256 totalAssetsBefore = totalCollateralBefore + totalProtectedBefore + gaugeAssetsBefore;
            uint256 totalAssetsAfter = totalCollateralAfter + totalProtectedAfter + gaugeAssetsAfter;

            if (totalDebtBefore == 0) {
                assertGe(
                    totalCollateralAfter,
                    totalCollateralBefore,
                    "liquidity provider should nave no loss after defaulting"
                );
            } else {
                uint256 balanceBefore = totalAssetsBefore - totalDebtBefore;
                uint256 balanceAfter = totalAssetsAfter - totalDebtAfter;

                assertLt(
                    balanceAfter, balanceBefore, "borrower should not gain after defaulting, it should loss fees"
                );
            }
        }
    }

    /*
    - if LP provider does not claim, rewards balance can only grow
    */
    function assert_rewardsBalanceCanOnlyGrowWhenNoClaim() external setupRandomActor(0) {
        assertGe(
            gauge.getRewardsBalance(address(actor), _getImmediateProgramNames()),
            rewardsBalanceBefore[address(actor)],
            "rewards balance should not decrease when no claim"
        );
    }

    /*
    - after defaultin we should not reduce collateral total assets below actual available balance (liquidity)
    */
    function assert_defaulting_totalAssetsIsNotLessThanLiquidity() external {
        uint256 siloBalance = _asset1.balanceOf(address(vault0));
        if (siloBalance == 0) return;

        uint256 protected = vault1.getTotalAssetsStorage(ISilo.AssetType.Protected);
        uint256 available = siloBalance - protected;

        uint256 totalAssets = vault0.getTotalAssetsStorage(ISilo.AssetType.Collateral);
        assertGe(totalAssets, available, "total assets should not be less than available balance");

        uint256 liquidity = vault0.getLiquidity();
        assertGt(liquidity, available, "liquidity should be greater than available balance");
    }

    // TODO rules
}
