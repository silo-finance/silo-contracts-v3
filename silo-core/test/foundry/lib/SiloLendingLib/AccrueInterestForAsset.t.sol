// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {SiloLendingLib} from "silo-core/contracts/lib/SiloLendingLib.sol";
import {SiloStorageLib} from "silo-core/contracts/lib/SiloStorageLib.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {InterestRateModelMock} from "../../_mocks/InterestRateModelMock.sol";

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
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_accrueInterestForAsset_feeDroppedWhenIntegralInterestCrossesFeeBoundary

    accrueInterestForAsset only needs rcomp from the IRM. Sibling tests already mock it; a kink JSON
    silo deploy would not exercise this library path any more faithfully.
    */
    function test_accrueInterestForAsset_feeDroppedWhenIntegralInterestCrossesFeeBoundary() public {
        uint256 daoFee = 0.1e18;
        uint256 deployerFee = 0;
        uint256 debt = 1;
        uint256 rcomp1 = DECIMAL_POINTS - 1;

        InterestRateModelMock irm = new InterestRateModelMock();
        ISilo.SiloStorage storage $ = _$();

        $.totalAssets[ISilo.AssetType.Collateral] = 1_000;
        $.totalAssets[ISilo.AssetType.Debt] = debt;
        $.interestRateTimestamp = 111;

        // Accrual #1: integer interest is 0, remainder fills fractions.interest to 1e18 - 1.
        irm.getCompoundInterestRateAndUpdateMock(rcomp1);
        vm.warp(222);
        console2.log("----------- call accrual #1 -----------");
        uint256 accrued1 = SiloLendingLib.accrueInterestForAsset({
            _interestRateModel: irm.ADDRESS(),
            _daoFee: daoFee,
            _deployerFee: deployerFee
        });

        console2.log("\t accrued1", accrued1);
        emit log_named_decimal_uint("rcomp1", rcomp1, 16);
        _logStorage("\nafter accrual #1\n");

        uint64 interestFractionAfterFirst = $.fractions.interest;

        // Accrual #2: integer interest A = 9, remainder 1 overflows the stored fraction → I = 1.
        uint256 rcomp2 = 9 * DECIMAL_POINTS + 1;
        irm.getCompoundInterestRateAndUpdateMock(rcomp2);
        vm.warp(333);
        console2.log("----------- call accrual #2 -----------");
        uint256 accrued2 = SiloLendingLib.accrueInterestForAsset({
            _interestRateModel: irm.ADDRESS(),
            _daoFee: daoFee,
            _deployerFee: deployerFee
        });

        console2.log("\taccrued2 %s at %s%", accrued2, rcomp2);
        emit log_named_decimal_uint("rcomp2", rcomp2, 16);
        _logStorage("\nafter accrual #2\n");

        uint256 expectedFeesOnFullInterest = accrued2 * daoFee / DECIMAL_POINTS;

        // #region agent log
        console2.log({p0: "accrued1", p1: accrued1});
        console2.log({p0: "interestFractionAfterFirst", p1: uint256(interestFractionAfterFirst)});
        console2.log({p0: "accrued2", p1: accrued2});
        console2.log({p0: "daoAndDeployerRevenue", p1: uint256($.daoAndDeployerRevenue)});
        console2.log({p0: "expectedFeesOnFullInterest", p1: expectedFeesOnFullInterest});
        console2.log({p0: "revenueFraction", p1: uint256($.fractions.revenue)});
        console2.log({p0: "post-fix totalDebt", p1: $.totalAssets[ISilo.AssetType.Debt]});
        console2.log({p0: "post-fix totalCollateral", p1: $.totalAssets[ISilo.AssetType.Collateral]});
        console2.log({
            p0: "post-fix identity deltaColl+fees",
            p1: $.totalAssets[ISilo.AssetType.Collateral] - 1_000 + uint256($.daoAndDeployerRevenue)
        });
        // #endregion

        assertEq({left: accrued1, right: 0, err: "first accrual is fraction-only"});
        assertEq({left: interestFractionAfterFirst, right: DECIMAL_POINTS - 1, err: "interest fraction primed"});
        assertEq({left: accrued2, right: 10, err: "A=9 plus integralInterest=1"});
        assertEq({left: expectedFeesOnFullInterest, right: 1, err: "10 * 10% is an exact 1 wei fee"});
        assertEq({left: $.fractions.revenue, right: 0, err: "fee remainder consumed into integral revenue"});
        assertEq({
            left: uint256($.daoAndDeployerRevenue),
            right: expectedFeesOnFullInterest,
            err: "fee on A+I credited via fraction overflow"
        });
        assertEq({
            left: $.totalAssets[ISilo.AssetType.Collateral] - 1_000 + uint256($.daoAndDeployerRevenue),
            right: $.totalAssets[ISilo.AssetType.Debt] - debt,
            err: "deltaDebt = deltaColl + fees"
        });
    }

    function _logStorage(string memory _msg) internal {
        ISilo.SiloStorage storage $ = _$();

        console2.log(_msg);
        console2.log("[debug] totalAssets[ISilo.AssetType.Collateral]", $.totalAssets[ISilo.AssetType.Collateral]);
        console2.log("[debug] totalAssets[ISilo.AssetType.Debt]", $.totalAssets[ISilo.AssetType.Debt]);
        emit log_named_decimal_uint("[debug] fractions.interest", $.fractions.interest, 18);
        emit log_named_decimal_uint("[debug] fractions.revenue", $.fractions.revenue, 18);
        emit log_named_decimal_uint("[debug] daoAndDeployerRevenue", $.daoAndDeployerRevenue, 18);
    }

    function _$() internal pure returns (ISilo.SiloStorage storage $) {
        return SiloStorageLib.getSiloStorage();
    }
}
