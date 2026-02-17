// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";

import {SiloLittleHelper} from "../_common/SiloLittleHelper.sol";
import {SiloConfigOverride} from "../_common/fixtures/SiloFixture.sol";
import {SiloFixture} from "../_common/fixtures/SiloFixture.sol";

import {MintableToken} from "../_common/MintableToken.sol";

contract Oracle is ISiloOracle {
    uint256 immutable baseDecimals;
    uint256 priceOfOneBaseToken;

    address public quoteToken;

    constructor(uint8 _baseDecimals, address _quoteToken) {
        baseDecimals = _baseDecimals;
        quoteToken = _quoteToken;
    }

    function beforeQuote(address) external {}

    function setPrice(uint256 _priceOfOne) external {
        priceOfOneBaseToken = _priceOfOne;
    }

    function quote(uint256 _baseAmount, address /* _baseToken */ ) external view returns (uint256 quoteAmount) {
        return _baseAmount * priceOfOneBaseToken / (10 ** baseDecimals);
    }
}

/*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc SiloDecimalsTest
*/
contract SiloDecimalsTest is SiloLittleHelper, Test {
    Oracle token0Oracle;

    address borrower;
    address depositor;

    constructor() {
        borrower = makeAddr("borrower");
        depositor = makeAddr("depositor");
    }

    function _setUp(uint8 _token0Decimals, uint8 _token1Decimals, bool _oracle) internal {
        SiloFixture siloFixture = new SiloFixture();
        SiloConfigOverride memory configOverride;

        token0 = new MintableToken(_token0Decimals);
        token1 = new MintableToken(_token1Decimals);

        configOverride.token0 = address(token0);
        configOverride.token1 = address(token1);

        if (_oracle) {
            token0Oracle = new Oracle(_token0Decimals, address(token1));
            configOverride.solvencyOracle0 = address(token0Oracle);
            configOverride.maxLtvOracle0 = address(token0Oracle);
        }

        address hook;
        (, silo0, silo1,,, hook) = siloFixture.deploy_local(configOverride);
        partialLiquidation = IPartialLiquidation(hook);
    }

    /*
        FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_decimals_6_18_noOracle
    */
    function test_decimals_6_18_noOracle() public {
        _setUp(6, 18, false);

        _deposit(100e5, borrower);
        _depositForBorrow(100e5, depositor);

        assertEq(silo1.maxBorrow(borrower), 75e5 - 1, "maxBorrow");
        _borrow(silo1.maxBorrow(borrower), borrower);

        assertEq(silo0.maxWithdraw(borrower), 1176468, "maxWithdraw");
        _withdraw(silo0.maxWithdraw(borrower), borrower);

        vm.warp(10 days);

        assertFalse(silo0.isSolvent(borrower), "NOT Solvent");

        _repay(1e5, borrower);

        (uint256 collateral, uint256 debt, bool receiveSToken) = partialLiquidation.maxLiquidation(borrower);
        assertEq(collateral, 41_37808, "collateral");
        assertEq(debt, 39_40772, "debt");
        assertFalse(receiveSToken, "receiveSToken");

        token1.approve(address(partialLiquidation), debt);
        token1.mint(address(this), debt);

        partialLiquidation.liquidationCall(address(token0), address(token1), borrower, debt, receiveSToken);
    }

    /*
        FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_decimals_ETH_USDC_oracle
    */
    function test_decimals_ETH_USDC_oracle() public {
        _setUp(18, 6, true);
        token0Oracle.setPrice(2500e6);

        assertEq(token0Oracle.quote(1e18, address(token0)), 2500e6, "price of 1 ETH in USDC");

        _deposit(1e18, borrower);
        _depositForBorrow(2000e6, depositor);

        assertEq(silo1.maxBorrow(borrower), 1875e6 - 1, "maxBorrow maxLTV is 75% (2500 * 0.75 => 1875)");
        _borrow(silo1.maxBorrow(borrower), borrower);

        // LT is 85%, so 1875 / 0.85 = 2205 of value in collateral is needed.
        // we have 1ETH (2500USDC), 2500 - 2205 = 295.
        // 295 / 2500 = 0.118% can be removed, => ~118000000000000000
        assertEq(silo0.maxWithdraw(borrower), 117647058447058822, "maxWithdraw (-1 underestimate for fractions)");
        _withdraw(silo0.maxWithdraw(borrower), borrower);

        vm.warp(1 days);

        assertFalse(silo0.isSolvent(borrower), "NOT Solvent");

        _repay(1e6, borrower);

        (uint256 collateral, uint256 debt, bool receiveSToken) = partialLiquidation.maxLiquidation(borrower);
        assertEq(collateral, 417011079366804430, "collateral");
        assertEq(debt, 992883522, "debt");
        assertFalse(receiveSToken, "receiveSToken");

        token1.approve(address(partialLiquidation), debt);
        token1.mint(address(this), debt);

        partialLiquidation.liquidationCall(address(token0), address(token1), borrower, debt, receiveSToken);
    }

    /*
        FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_decimals_USDC_ETH_oracle
    */
    function test_decimals_USDC_ETH_oracle() public {
        _setUp(6, 18, true);
        token0Oracle.setPrice(0.0004e18); // 1/2500

        assertEq(token0Oracle.quote(2500e6, address(token0)), 1e18, "value of 2500 USDC in ETH");

        _deposit(2500e6, borrower);
        _depositForBorrow(1e18, depositor);

        // -3e8 is because we decrease the user collateral by 1wei during maxBorrow calculation due to fractions
        assertEq(
            silo1.maxBorrow(borrower), 0.75e18 - 3e8, "maxBorrow, maxLTV is 75% (-3e8 because of the fractions)"
        );
        _borrow(silo1.maxBorrow(borrower), borrower);

        // LT is 85%, so 0.75e18 / 0.85 = 882352941176470700 of value in collateral is needed.
        // we have 1ETH, 1e18 - 882352941176470700 = 117647058823529340.
        // 117647058823529340 / 1e18 = 0.118% can be removed, => 2500e6 * 0.118 = 295000000
        assertEq(silo0.maxWithdraw(borrower), 294117645, "maxWithdraw");
        _withdraw(silo0.maxWithdraw(borrower), borrower);

        vm.warp(1 days);

        assertFalse(silo0.isSolvent(borrower), "NOT Solvent");

        _repay(10, borrower);

        (uint256 collateral, uint256 debt, bool receiveSToken) = partialLiquidation.maxLiquidation(borrower);
        assertEq(collateral, 100_4885414, "collateral");
        assertEq(debt, 382813492061162048, "debt");
        assertFalse(receiveSToken, "receiveSToken");

        token1.approve(address(partialLiquidation), debt);
        token1.mint(address(this), debt);

        partialLiquidation.liquidationCall(address(token0), address(token1), borrower, debt, receiveSToken);
    }

    /*
        FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_decimals_HALF_USDC_oracle
    */
    function test_decimals_HALF_USDC_oracle() public {
        _setUp(6, 6, true);
        token0Oracle.setPrice(0.5e6);

        assertEq(token0Oracle.quote(1e6, address(token0)), 0.5e6, "half of USDC");

        _deposit(1e6, borrower);
        _depositForBorrow(1e6, depositor);

        assertEq(silo1.maxBorrow(borrower), 0.75e6 / 2 - 1, "maxBorrow, maxLTV is 75% => 375000");
        _borrow(silo1.maxBorrow(borrower), borrower);

        // LT is 85%, so (375000 - 1) / 0.85 = 441175 of value in collateral is needed.
        // we have 1HALF, 1e6 - (441175 * 2) = 117650.
        // 117650 / 1e6 = 0.11765 can be removed, => 1e6 * 0.117648 = 117650
        assertEq(silo0.maxWithdraw(borrower), 117643, "maxWithdraw (-1 underestimate for fractions)");
        _withdraw(silo0.maxWithdraw(borrower), borrower);

        vm.warp(1 days);

        assertFalse(silo0.isSolvent(borrower), "NOT Solvent");

        _repay(10, borrower);

        (uint256 collateral, uint256 debt, bool receiveSToken) = partialLiquidation.maxLiquidation(borrower);
        assertEq(collateral, 400686, "collateral");
        assertEq(debt, 190804, "debt");
        assertFalse(receiveSToken, "receiveSToken");

        token1.approve(address(partialLiquidation), debt);
        token1.mint(address(this), debt);

        partialLiquidation.liquidationCall(address(token0), address(token1), borrower, debt, receiveSToken);
    }
}
