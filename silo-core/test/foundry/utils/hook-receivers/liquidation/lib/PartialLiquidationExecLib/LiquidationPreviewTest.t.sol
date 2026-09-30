// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {SiloSolvencyLib} from "silo-core/contracts/lib/SiloSolvencyLib.sol";
import {PartialLiquidationExecLib} from "silo-core/contracts/hooks/liquidation/lib/PartialLiquidationExecLib.sol";
import {PartialLiquidationLib} from "silo-core/contracts/hooks/liquidation/lib/PartialLiquidationLib.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {OraclesHelper} from "../../../../../_common/OraclesHelper.sol";
import {PartialLiquidationExecLibImpl} from "../../../../../_common/PartialLiquidationExecLibImpl.sol";

// forge test -vv --mc LiquidationPreviewTest
contract LiquidationPreviewTest is Test, OraclesHelper {
    // this must match value from PartialLiquidationLib
    uint256 internal constant _LT_LIQUIDATION_MARGIN = 0.9e18; // 90%

    /*
    forge test -vv --mt test_liquidationPreview_noOracle_zero
    */
    function test_liquidationPreview_noOracle_zero() public view {
        SiloSolvencyLib.LtvData memory ltvData;
        PartialLiquidationLib.LiquidationPreviewParams memory params;

        params.maxDebtToCover = 10;
        params.collateralLt = 0.75e18;

        uint256 receiveCollateral;
        uint256 repayDebt;
        bytes4 customError;

        (receiveCollateral, repayDebt, customError) = PartialLiquidationExecLib.liquidationPreview(ltvData, params);
        assertEq(receiveCollateral, 0, "zero collateral on empty values");
        assertEq(repayDebt, 0, "zero debt on empty values");
        assertEq(customError, IPartialLiquidation.NoDebtToCover.selector, "NoDebtToCover error");

        ltvData.borrowerCollateralAssets = 1;
        (receiveCollateral, repayDebt, customError) = PartialLiquidationExecLib.liquidationPreview(ltvData, params);
        assertEq(receiveCollateral, 0, "zero collateral on empty debt");
        assertEq(repayDebt, 0, "zero debt on empty debt");
        assertEq(customError, IPartialLiquidation.NoDebtToCover.selector, "NoDebtToCover error");

        ltvData.borrowerCollateralAssets = 0;
        ltvData.borrowerDebtAssets = 1;
        (receiveCollateral, repayDebt, customError) = PartialLiquidationExecLib.liquidationPreview(ltvData, params);
        assertEq(receiveCollateral, 0, "zero collateral on empty collateral");
        assertEq(repayDebt, ltvData.borrowerDebtAssets, "has debt on empty collateral");
        assertEq(customError, bytes4(0), "NoDebtToCover error");

        ltvData.borrowerCollateralAssets = 1000;
        ltvData.borrowerDebtAssets = 100;
        (receiveCollateral, repayDebt, customError) = PartialLiquidationExecLib.liquidationPreview(ltvData, params);
        assertEq(receiveCollateral, 0, "zero collateral on solvent borrower");
        assertEq(repayDebt, 0, "zero debt on solvent borrower");
        assertEq(customError, IPartialLiquidation.UserIsSolvent.selector, "NoDebtToCover error");
    }

    /*
    forge test -vv --mt test_liquidationPreview_zero
    */
    function test_liquidationPreview_zero() public {
        SiloSolvencyLib.LtvData memory ltvData;
        ltvData.collateralOracle = ISiloOracle(collateralOracle.ADDRESS());
        ltvData.debtOracle = ISiloOracle(debtOracle.ADDRESS());

        PartialLiquidationLib.LiquidationPreviewParams memory params;
        params.collateralConfigAsset = COLLATERAL_ASSET;
        params.debtConfigAsset = DEBT_ASSET;
        params.maxDebtToCover = 1;

        ltvData.borrowerCollateralAssets = 1;
        ltvData.borrowerDebtAssets = 1;

        uint256 collateralSum = ltvData.borrowerCollateralAssets + ltvData.borrowerProtectedAssets;
        collateralOracle.quoteMock(collateralSum, COLLATERAL_ASSET, 0);
        debtOracle.quoteMock(ltvData.borrowerDebtAssets, DEBT_ASSET, 0);

        (uint256 receiveCollateral, uint256 repayDebt,) =
            PartialLiquidationExecLib.liquidationPreview(ltvData, params);
        assertEq(receiveCollateral, 0, "zero collateral on empty values");
        assertEq(repayDebt, 0, "zero debt on empty values");
    }

    /*
    forge test -vv --mt test_liquidationPreview_revert_LiquidationTooBig
    */
    function test_liquidationPreview_revert_LiquidationTooBig() public {
        PartialLiquidationExecLibImpl impl = new PartialLiquidationExecLibImpl();

        SiloSolvencyLib.LtvData memory ltvData;
        ltvData.collateralOracle = ISiloOracle(collateralOracle.ADDRESS());
        ltvData.debtOracle = ISiloOracle(debtOracle.ADDRESS());
        ltvData.borrowerCollateralAssets = 1e18;
        ltvData.borrowerDebtAssets = 0.8e18;

        PartialLiquidationLib.LiquidationPreviewParams memory params;
        params.collateralConfigAsset = COLLATERAL_ASSET;
        params.debtConfigAsset = DEBT_ASSET;
        params.collateralLt = 0.8e18 - 1; // must be below LTV that is present in `ltvData`
        params.liquidationTargetLtv = params.collateralLt * 0.9e18 / 1e18;

        (uint256 maxCollateralToLiquidate, uint256 maxDebtToCover) = PartialLiquidationLib.maxLiquidation(
            ltvData.borrowerCollateralAssets,
            ltvData.borrowerCollateralAssets,
            ltvData.borrowerDebtAssets,
            ltvData.borrowerDebtAssets,
            params.liquidationTargetLtv,
            params.liquidationFee
        );

        emit log_named_decimal_uint("maxDebtToCover", maxDebtToCover, 18);

        params.maxDebtToCover = maxDebtToCover;
        // price is 1:1
        uint256 collateralSum = ltvData.borrowerCollateralAssets + ltvData.borrowerProtectedAssets;
        collateralOracle.quoteMock(collateralSum, COLLATERAL_ASSET, collateralSum);
        debtOracle.quoteMock(ltvData.borrowerDebtAssets, DEBT_ASSET, ltvData.borrowerDebtAssets);

        // does not revert - counter example first
        (uint256 receiveCollateralAssets, uint256 repayDebtAssets,) = impl.liquidationPreview(ltvData, params);
        // -2 because we underestimating max value
        assertEq(receiveCollateralAssets - 2, maxCollateralToLiquidate, "expect same collateral #1");
        assertEq(receiveCollateralAssets, maxDebtToCover, "same collateral, because price is 1:1 and no fee #1");
        assertEq(repayDebtAssets, maxDebtToCover, "repayDebtAssets match #1");

        // more debt should cause revert because of _LT_LIQUIDATION_MARGIN_IN_BP
        params.maxDebtToCover += 1;

        (receiveCollateralAssets, repayDebtAssets,) = impl.liquidationPreview(ltvData, params);
        assertEq(receiveCollateralAssets, maxDebtToCover, "receiveCollateralAssets #3 - cap to max");
        assertEq(repayDebtAssets, maxDebtToCover, "repayDebtAssets #3 - cap to max");
    }

    /*
    forge test -vv --mt test_liquidationPreview_whenNotSolvent
    */
    function test_liquidationPreview_whenNotSolvent() public view {
        SiloSolvencyLib.LtvData memory ltvData;
        ltvData.borrowerCollateralAssets = 1e18;
        ltvData.borrowerDebtAssets = 2e18; // 200% LTV

        PartialLiquidationLib.LiquidationPreviewParams memory params;
        params.collateralConfigAsset = COLLATERAL_ASSET;
        params.debtConfigAsset = DEBT_ASSET;
        params.collateralLt = 0.8e18;
        params.maxDebtToCover = 2;

        // ltv 200% - user NOT solvent
        // no oracle calls

        (uint256 receiveCollateral, uint256 repayDebt,) =
            PartialLiquidationExecLib.liquidationPreview(ltvData, params);
        assertEq(receiveCollateral, 2, "receiveCollateral");
        assertEq(repayDebt, 2, "repayDebt");
    }
}
