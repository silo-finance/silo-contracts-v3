// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";

import {MintableToken} from "../_common/MintableToken.sol";
import {SiloLittleHelper} from "../_common/SiloLittleHelper.sol";
import {SiloConfigOverride} from "../_common/fixtures/SiloFixture.sol";
import {SiloFixture} from "../_common/fixtures/SiloFixture.sol";
import {DummyOracle} from "../_common/DummyOracle.sol";

/*
    forge test -vv --ffi --mc SiloLensWithOracleTest
*/
contract SiloLensWithOracleTest is SiloLittleHelper, Test {
    ISiloConfig siloConfig;
    address immutable DEPOSITOR;
    address immutable BORROWER;

    DummyOracle immutable SOLVENCY_ORACLE0;
    DummyOracle immutable MAX_LTV_ORACLE0;

    constructor() {
        DEPOSITOR = makeAddr("Depositor");
        BORROWER = makeAddr("Borrower");

        token0 = new MintableToken(18);
        token1 = new MintableToken(18);

        SOLVENCY_ORACLE0 = new DummyOracle(1e18, address(token1));
        MAX_LTV_ORACLE0 = new DummyOracle(1e18, address(token1));

        SOLVENCY_ORACLE0.setExpectBeforeQuote(true);
        MAX_LTV_ORACLE0.setExpectBeforeQuote(true);

        SiloConfigOverride memory overrides;
        overrides.token0 = address(token0);
        overrides.token1 = address(token1);
        overrides.solvencyOracle0 = address(SOLVENCY_ORACLE0);
        overrides.maxLtvOracle0 = address(MAX_LTV_ORACLE0);
        overrides.configName = SiloConfigsNames.SILO_LOCAL_BEFORE_CALL;

        SiloFixture siloFixture = new SiloFixture();

        address hook;
        (, silo0, silo1,,, hook) = siloFixture.deploy_local(overrides);
        partialLiquidation = IPartialLiquidation(hook);
    }

    /*
        FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_SiloLensOracle_calculateProfitableLiquidation_priceDrop
    */
    function test_SiloLensOracle_calculateProfitableLiquidation_priceDrop() public {
        _depositForBorrow(100e18, DEPOSITOR);

        _deposit(100e18, BORROWER);
        _borrow(75e18, BORROWER);

        uint256 ltv = SILO_LENS.getLtv(silo0, BORROWER);
        assertEq(ltv, 0.75e18, "price is 1:1 so LTV is 75%");

        SOLVENCY_ORACLE0.setPrice(0.5e18);
        ltv = SILO_LENS.getLtv(silo0, BORROWER);
        assertEq(ltv, 1.5e18, "price drop");

        (uint256 collateralToLiquidate, uint256 debtToCover) =
            SILO_LENS.calculateProfitableLiquidation(silo0, BORROWER);

        // we underestimate collateral by 2
        assertEq(collateralToLiquidate, 100e18 - 2, "collateralToLiquidate is 0 when position is solvent");

        _madeProfitableLiquidation(collateralToLiquidate, debtToCover);

        _assertColateralHasBiggerValue(collateralToLiquidate, debtToCover);
    }

    /*
        FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_SiloLensOracle_calculateProfitableLiquidation_fuzz
    */
    function test_SiloLensOracle_calculateProfitableLiquidation_fuzz(uint256 _price) public {
        vm.assume(_price > 1000 && _price < 2e18); // some reasonable numbers

        _depositForBorrow(100_000e18, DEPOSITOR);

        _deposit(100e18, BORROWER);
        _borrow(75e18, BORROWER);

        uint256 ltv = SILO_LENS.getLtv(silo0, BORROWER);
        assertEq(ltv, 0.75e18, "price is 1:1 so LTV is 75%");

        SOLVENCY_ORACLE0.setPrice(_price);

        (uint256 collateralToLiquidate, uint256 debtToCover) =
            SILO_LENS.calculateProfitableLiquidation(silo0, BORROWER);

        (uint256 collateralToLiquidate1, uint256 debtToCover1) =
            SILO_LENS.calculateProfitableLiquidation(silo1, BORROWER);

        assertEq(collateralToLiquidate1, collateralToLiquidate, "collateralToLiquidate is the same for both silos");
        assertEq(debtToCover1, debtToCover, "debt result same for both silos");

        _madeProfitableLiquidation(collateralToLiquidate, debtToCover);

        _assertColateralHasBiggerValue(collateralToLiquidate, debtToCover);
    }

    function _madeProfitableLiquidation(uint256 _collateralToLiquidate, uint256 _debtToCover) internal {
        vm.assume(!silo1.isSolvent(BORROWER));

        uint256 balance0before = token0.balanceOf(address(this));
        uint256 balance1before = token1.balanceOf(address(this));

        token1.mint(address(this), _debtToCover);
        token1.approve(address(partialLiquidation), _debtToCover);

        try partialLiquidation.liquidationCall({
            _collateralAsset: address(token0),
            _debtAsset: address(token1),
            _user: BORROWER,
            _maxDebtToCover: _debtToCover,
            _receiveSToken: false
        }) {
            // OK
        } catch (bytes memory data) {
            // then only acceptable error is FullLiquidationRequired
            // Safe: extracting first 4 bytes from error bytes to compare with error selector.
            // Error selectors are always 4 bytes, so casting is safe.
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes4 errorType = bytes4(data);
            bytes4 expectedError = bytes4(keccak256(abi.encodePacked("FullLiquidationRequired()")));

            if (errorType == expectedError) {
                vm.assume(false);
            } else {
                revert(string(data));
            }
        }

        uint256 balance0after = token0.balanceOf(address(this));
        uint256 balance1after = token1.balanceOf(address(this));

        console2.log("          balance0before", balance0before);
        console2.log("           balance0after", balance0after);
        console2.log("   collateralToLiquidate", _collateralToLiquidate);
        emit log_named_decimal_uint("convertToAssets", silo0.convertToAssets(1e18), 18);

        // -2 for rounding errors
        assertLe(balance0before, balance0after, "collateral should be received");
        assertEq(balance1before, balance1after, "debt balance does not change");

        // estimation might be off by some rounding errors, so assert actual values
        _assertColateralHasBiggerValue(balance0after - balance0before, _debtToCover);
    }

    function _assertColateralHasBiggerValue(uint256 _collateralToLiquidate, uint256 _debtToCover) internal view {
        (ISiloConfig.ConfigData memory collateralConfig, ISiloConfig.ConfigData memory debtConfig) =
            silo1.config().getConfigsForSolvency(BORROWER);

        uint256 collateralValue = collateralConfig.solvencyOracle == address(0)
            ? _collateralToLiquidate
            : ISiloOracle(collateralConfig.solvencyOracle).quote(_collateralToLiquidate, collateralConfig.token);

        uint256 debtValue = debtConfig.solvencyOracle == address(0)
            ? _debtToCover
            : ISiloOracle(debtConfig.solvencyOracle).quote(_debtToCover, debtConfig.token);

        assertGt(collateralValue, debtValue, "collateral should have bigger value");
    }
}
