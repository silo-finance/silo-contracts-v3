// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SiloLendingLib} from "silo-core/contracts/lib/SiloLendingLib.sol";
import {SiloStorageLib} from "silo-core/contracts/lib/SiloStorageLib.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {InterestRateModelMock} from "../../_mocks/InterestRateModelMock.sol";
import {RevertingIRM} from "../../_mocks/RevertingIRM.sol";
import {IInterestRateModel} from "silo-core/contracts/interfaces/IInterestRateModel.sol";

// forge test -vv --mc AccrueInterestForAssetTest
contract AccrueInterestForAssetTest is Test {
    uint256 constant DECIMAL_POINTS = 1e18;

    /*
    forge test -vv --mt test_accrueInterestForAsset_initialCall_noData
    */
    function test_accrueInterestForAsset_initialCall_noData() public {
        uint256 accruedInterest = SiloLendingLib.accrueInterestForAsset(address(0), 0, 0);

        ISilo.SiloStorage storage $ = _$();

        assertEq(accruedInterest, 0, "zero when no data");
        assertEq($.totalAssets[ISilo.AssetType.Collateral], 0, "totalCollateral 0");
        assertEq($.totalAssets[ISilo.AssetType.Debt], 0, "totalDebt 0");
    }

    /*
    forge test -vv --mt test_accrueInterestForAsset_whenTimestampNotChanged
    */
    function test_accrueInterestForAsset_whenTimestampNotChanged() public {
        uint64 currentTimestamp = 222;
        vm.warp(currentTimestamp);

        ISilo.SiloStorage storage $ = _$();

        $.interestRateTimestamp = currentTimestamp;

        $.totalAssets[ISilo.AssetType.Collateral] = 1e18;
        $.totalAssets[ISilo.AssetType.Debt] = 1e18;

        uint256 accruedInterest = SiloLendingLib.accrueInterestForAsset(address(0), 0, 0);

        assertEq(accruedInterest, 0, "zero timestamp did not change");
        assertEq($.totalAssets[ISilo.AssetType.Collateral], 1e18, "totalCollateral - timestamp did not change");
        assertEq($.totalAssets[ISilo.AssetType.Debt], 1e18, "totalDebt - timestamp did not change");
    }

    /*
    forge test -vv --mt test_accrueInterestForAsset_withDataNoFee
    */
    function test_accrueInterestForAsset_withDataNoFee() public {
        uint64 oldTimestamp = 111;
        uint64 currentTimestamp = 222;
        vm.warp(currentTimestamp);

        uint256 rcomp = 0.01e18;

        InterestRateModelMock irm = new InterestRateModelMock();
        irm.getCompoundInterestRateAndUpdateMock(rcomp);

        ISilo.SiloStorage storage $ = _$();

        $.totalAssets[ISilo.AssetType.Collateral] = 1e18;
        $.totalAssets[ISilo.AssetType.Debt] = 0.5e18;
        $.interestRateTimestamp = oldTimestamp;

        uint256 accruedInterest = SiloLendingLib.accrueInterestForAsset(irm.ADDRESS(), 0, 0);

        assertEq(accruedInterest, 0.005e18, "accruedInterest");
        assertEq($.totalAssets[ISilo.AssetType.Collateral], 1.005e18, "totalCollateral");
        assertEq($.totalAssets[ISilo.AssetType.Debt], 0.505e18, "totalDebt");
        assertEq($.interestRateTimestamp, currentTimestamp, "interestRateTimestamp");
        assertEq($.daoAndDeployerRevenue, 0, "daoAndDeployerRevenue");
    }

    /*
    forge test -vv --mt test_accrueInterestForAsset_withDataWithFees
    */
    function test_accrueInterestForAsset_withDataWithFees() public {
        uint64 oldTimestamp = 111;
        uint64 currentTimestamp = 222;
        vm.warp(currentTimestamp);

        uint256 rcomp = 0.01e18;
        uint256 daoFee = 0.02e18;
        uint256 deployerFee = 0.03e18;

        InterestRateModelMock irm = new InterestRateModelMock();
        irm.getCompoundInterestRateAndUpdateMock(rcomp);

        ISilo.SiloStorage storage $ = _$();

        $.totalAssets[ISilo.AssetType.Collateral] = 1e18;
        $.totalAssets[ISilo.AssetType.Debt] = 0.5e18;
        $.interestRateTimestamp = oldTimestamp;

        uint256 accruedInterest = SiloLendingLib.accrueInterestForAsset(irm.ADDRESS(), daoFee, deployerFee);

        assertEq(accruedInterest, 0.005e18, "accruedInterest");
        assertEq(
            $.totalAssets[ISilo.AssetType.Collateral],
            1e18 + accruedInterest * (DECIMAL_POINTS - daoFee - deployerFee) / DECIMAL_POINTS,
            "totalCollateral"
        );
        assertEq($.totalAssets[ISilo.AssetType.Debt], 0.505e18, "totalDebt");
        assertEq($.interestRateTimestamp, currentTimestamp, "interestRateTimestamp");
        assertEq(
            $.daoAndDeployerRevenue,
            accruedInterest * (daoFee + deployerFee) / DECIMAL_POINTS,
            "daoAndDeployerRevenue"
        );
    }


    /*
    forge test -vv --mt test_accrueInterestForAsset_whenIrmReverts_timestampUnchanged
    */
    function test_accrueInterestForAsset_whenIrmReverts_timestampUnchanged() public {
        uint64 oldTimestamp = 111;
        uint64 currentTimestamp = 222;
        vm.warp(currentTimestamp);

        RevertingIRM irm = new RevertingIRM(RevertingIRM.RevertReasons.StandardRevert);

        ISilo.SiloStorage storage $ = _$();

        $.totalAssets[ISilo.AssetType.Collateral] = 1e18;
        $.totalAssets[ISilo.AssetType.Debt] = 0.5e18;
        $.interestRateTimestamp = oldTimestamp;

        vm.expectEmit();
        emit IInterestRateModel.InterestRateModelError();

        uint256 accruedInterest = SiloLendingLib.accrueInterestForAsset(address(irm), 0, 0);

        assertEq(accruedInterest, 0, "no interest when IRM fails");
        assertEq($.interestRateTimestamp, oldTimestamp, "timestamp must not advance on IRM failure");
        assertEq($.totalAssets[ISilo.AssetType.Collateral], 1e18, "collateral unchanged");
        assertEq($.totalAssets[ISilo.AssetType.Debt], 0.5e18, "debt unchanged");
    }

    function _$() internal pure returns (ISilo.SiloStorage storage $) {
        return SiloStorageLib.getSiloStorage();
    }
}
