// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {Strings} from "openzeppelin5/utils/Strings.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {PartialLiquidationExecLib} from "silo-core/contracts/hooks/liquidation/lib/PartialLiquidationExecLib.sol";

import {SiloMock} from "../../../../../_mocks/SiloMock.sol";
import {InterestRateModelMock} from "../../../../../_mocks/InterestRateModelMock.sol";
import {TokenMock} from "../../../../../_mocks/TokenMock.sol";
import {GetExactLiquidationAmountsTestData} from
    "../../../../../data-readers/GetExactLiquidationAmountsTestData.sol";

// this is not test contract, just a helper
contract GetExactLiquidationAmountsHelper is Test {
    uint256 constant DECIMALS_POINTS = 1e18;

    uint256 constant LT = 0.8e18;

    SiloMock immutable SILO_A;
    SiloMock immutable SILO_B;

    TokenMock immutable TOKEN_A;
    TokenMock immutable C_SHARE_TOKEN_A;
    TokenMock immutable D_SHARE_TOKEN_A;
    TokenMock immutable P_SHARE_TOKEN_A;

    TokenMock immutable TOKEN_B;
    TokenMock immutable C_SHARE_TOKEN_B;
    TokenMock immutable D_SHARE_TOKEN_B;
    TokenMock immutable P_SHARE_TOKEN_B;

    InterestRateModelMock immutable INTEREST_RATE_MODEL;

    constructor() {
        SILO_A = new SiloMock(makeAddr("SILO_A"));
        SILO_B = new SiloMock(makeAddr("SILO_B"));

        TOKEN_A = new TokenMock(makeAddr("TOKEN_A"));
        C_SHARE_TOKEN_A = new TokenMock(makeAddr("C_SHARE_TOKEN_A"));
        D_SHARE_TOKEN_A = new TokenMock(makeAddr("D_SHARE_TOKEN_A"));
        P_SHARE_TOKEN_A = new TokenMock(makeAddr("P_SHARE_TOKEN_A"));

        TOKEN_B = new TokenMock(makeAddr("TOKEN_B"));
        C_SHARE_TOKEN_B = new TokenMock(makeAddr("C_SHARE_TOKEN_B"));
        D_SHARE_TOKEN_B = new TokenMock(makeAddr("D_SHARE_TOKEN_B"));
        P_SHARE_TOKEN_B = new TokenMock(makeAddr("P_SHARE_TOKEN_B"));

        INTEREST_RATE_MODEL = new InterestRateModelMock();
    }

    function getExactLiquidationAmounts(
        uint128 _maxDebtToCover,
        uint128 _collateralUserBalanceOf,
        uint128 _debtUserBalanceOf,
        uint32 _liquidationFee
    )
        external
        returns (uint256 fromCollateral, uint256 fromProtected, uint256 repayDebtAssets, bytes4 customError)
    {
        (ISiloConfig.ConfigData memory collateralConfig, ISiloConfig.ConfigData memory debtConfig) = _configs();
        uint256 sharesOffset = 10 ** 2;

        P_SHARE_TOKEN_A.balanceOfAndTotalSupplyMock(makeAddr("borrower"), 0, 0);
        SILO_A.getCollateralAndProtectedAssetsMock(2 ** 128 - 1, 0);

        C_SHARE_TOKEN_A.balanceOfAndTotalSupplyMock(
            makeAddr("borrower"), _collateralUserBalanceOf * sharesOffset, (2 ** 128 - 1) * sharesOffset
        );

        D_SHARE_TOKEN_B.balanceOfAndTotalSupplyMock(
            makeAddr("borrower"), _debtUserBalanceOf * sharesOffset, _debtUserBalanceOf * sharesOffset
        );

        SILO_B.totalMock(ISilo.AssetType.Debt, _debtUserBalanceOf);

        return PartialLiquidationExecLib.getExactLiquidationAmounts(
            collateralConfig, debtConfig, makeAddr("borrower"), _maxDebtToCover, _liquidationFee
        );
    }

    function _configs()
        internal
        view
        returns (ISiloConfig.ConfigData memory collateralConfig, ISiloConfig.ConfigData memory debtConfig)
    {
        collateralConfig.silo = SILO_A.ADDRESS();
        collateralConfig.token = TOKEN_A.ADDRESS();
        collateralConfig.collateralShareToken = C_SHARE_TOKEN_A.ADDRESS();
        collateralConfig.protectedShareToken = P_SHARE_TOKEN_A.ADDRESS();
        collateralConfig.debtShareToken = D_SHARE_TOKEN_A.ADDRESS();
        collateralConfig.interestRateModel = INTEREST_RATE_MODEL.ADDRESS();

        collateralConfig.lt = LT;

        debtConfig.silo = SILO_B.ADDRESS();
        debtConfig.token = TOKEN_B.ADDRESS();
        debtConfig.collateralShareToken = C_SHARE_TOKEN_B.ADDRESS();
        debtConfig.protectedShareToken = P_SHARE_TOKEN_B.ADDRESS();
        debtConfig.debtShareToken = D_SHARE_TOKEN_B.ADDRESS();
        debtConfig.interestRateModel = INTEREST_RATE_MODEL.ADDRESS();
    }
}

// forge test -vv --mc GetExactLiquidationAmountsTest
contract GetExactLiquidationAmountsTest is GetExactLiquidationAmountsHelper {
    /*
    forge test -vv --mt test_getExactLiquidationAmounts_noOracle_zero
    */
    function test_getExactLiquidationAmounts_noOracle_zero() public {
        (ISiloConfig.ConfigData memory collateralConfig, ISiloConfig.ConfigData memory debtConfig) = _configs();

        address user;
        uint256 maxDebtToCover;
        uint256 liquidationFee;

        P_SHARE_TOKEN_A.balanceOfAndTotalSupplyMock(user, 0, 0);
        SILO_A.getCollateralAndProtectedAssetsMock(0, 0);

        C_SHARE_TOKEN_A.balanceOfAndTotalSupplyMock(user, 0, 0);

        D_SHARE_TOKEN_B.balanceOfAndTotalSupplyMock(user, 0, 0);
        SILO_B.totalMock(ISilo.AssetType.Debt, 0);

        (uint256 fromCollateral, uint256 fromProtected, uint256 repayDebtAssets,) = PartialLiquidationExecLib
            .getExactLiquidationAmounts(collateralConfig, debtConfig, user, maxDebtToCover, liquidationFee);

        assertEq(fromCollateral, 0);
        assertEq(fromProtected, 0);
        assertEq(repayDebtAssets, 0);
    }

    /*
    forge test -vv --mt test_getExactLiquidationAmounts_noOracle_loop
    */
    function test_getExactLiquidationAmounts_noOracle_loop() public {
        (ISiloConfig.ConfigData memory collateralConfig, ISiloConfig.ConfigData memory debtConfig) = _configs();

        GetExactLiquidationAmountsTestData.GELAData[] memory testDatas =
            new GetExactLiquidationAmountsTestData().getData();

        for (uint256 i; i < testDatas.length; i++) {
            GetExactLiquidationAmountsTestData.GELAData memory testData = testDatas[i];

            P_SHARE_TOKEN_A.balanceOfAndTotalSupplyMock(
                testData.input.user,
                testData.mocks.protectedUserSharesBalanceOf,
                testData.mocks.protectedSharesTotalSupply
            );

            SILO_A.getCollateralAndProtectedAssetsMock(
                testData.mocks.siloTotalCollateralAssets, testData.mocks.siloTotalProtectedAssets
            );

            C_SHARE_TOKEN_A.balanceOfAndTotalSupplyMock(
                testData.input.user,
                testData.mocks.collateralUserSharesBalanceOf,
                testData.mocks.collateralSharesTotalSupply
            );

            D_SHARE_TOKEN_B.balanceOfAndTotalSupplyMock(
                testData.input.user, testData.mocks.debtUserSharesBalanceOf, testData.mocks.debtSharesTotalSupply
            );

            SILO_B.totalMock(ISilo.AssetType.Debt, testData.mocks.siloTotalDebtAssets);

            (uint256 fromCollateral, uint256 fromProtected, uint256 repayDebtAssets,) = PartialLiquidationExecLib
                .getExactLiquidationAmounts(
                collateralConfig,
                debtConfig,
                testData.input.user,
                testData.input.maxDebtToCover,
                testData.input.liquidationFee
            );

            assertEq(fromProtected, testData.output.fromProtected, _concatMsg(i, testData.name, "fromProtected"));
            assertEq(fromCollateral, testData.output.fromCollateral, _concatMsg(i, testData.name, "fromCollateral"));
            assertEq(
                repayDebtAssets, testData.output.repayDebtAssets, _concatMsg(i, testData.name, "repayDebtAssets")
            );
        }
    }

    /*
    forge test -vv --mt test_getExactLiquidationAmounts_liquidation_fuzz
    goal here is to check if we can get unexpected reverts
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_getExactLiquidationAmounts_liquidation_fuzz(
        uint128 _maxDebtToCover,
        uint128 _collateralUserBalanceOf,
        uint128 _debtUserBalanceOf
    ) public {
        vm.assume(_maxDebtToCover != 0);
        vm.assume(_maxDebtToCover <= _debtUserBalanceOf);
        vm.assume(_collateralUserBalanceOf != 0);

        // in this test we assume share is 1:1 assets 1:1 value
        uint256 ltvBefore = uint256(_debtUserBalanceOf) * DECIMALS_POINTS / _collateralUserBalanceOf;

        // investigate "normal" cases, where LTV is <= 100%, if we have bad debt then this is already lost cause
        vm.assume(ltvBefore >= LT);
        vm.assume(ltvBefore <= DECIMALS_POINTS);

        (uint256 collateralToLiquidate,, bool success, bytes4 errorType) =
            _tryGetExactLiquidationAmounts(_maxDebtToCover, _collateralUserBalanceOf, _debtUserBalanceOf, 1);

        // we want cases where we do not revert
        vm.assume(success);
        // we want cases where we doing liquidation
        vm.assume(collateralToLiquidate != 0);

        assertEq(bytes4(errorType), bytes4(0), "expect no other errors");
    }

    function _tryGetExactLiquidationAmounts(
        uint128 _maxDebtToCover,
        uint128 _collateralUserBalanceOf,
        uint128 _debtUserBalanceOf,
        uint32 _liquidationFee
    ) internal returns (uint256 collateralToLiquidate, uint256 ltvAfter, bool success, bytes4 errorType) {
        try GetExactLiquidationAmountsHelper(this).getExactLiquidationAmounts(
            _maxDebtToCover, _collateralUserBalanceOf, _debtUserBalanceOf, _liquidationFee
        ) returns (
            uint256 fromCollateral, uint256 fromProtected, uint256 repayDebtAssets, bytes4 /* customError */
        ) {
            collateralToLiquidate = fromCollateral + fromProtected;
            success = true;

            ltvAfter = _collateralUserBalanceOf - fromCollateral == 0
                ? 0
                : uint256(_debtUserBalanceOf - repayDebtAssets) * DECIMALS_POINTS
                    / uint256(_collateralUserBalanceOf - fromCollateral);
        } catch (bytes memory data) {
            errorType = bytes4(data);
        }
    }

    function _concatMsg(uint256 _i, string memory _name, string memory _msg)
        internal
        pure
        returns (string memory)
    {
        return string.concat("[", Strings.toString(_i), "] ", _name, ": ", _msg);
    }
}
