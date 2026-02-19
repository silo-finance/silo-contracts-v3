// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Math} from "openzeppelin5/utils/math/Math.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";
import {SiloConfigOverride, SiloFixture} from "../../_common/fixtures/SiloFixture.sol";
import {MintableToken} from "silo-core/test/foundry/_common/MintableToken.sol";

/*
FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc PartialLiquidation1weiTest
*/
contract PartialLiquidation1weiTest is SiloLittleHelper, Test {
    ISiloConfig siloConfig;

    address oracle = makeAddr("Oracle");

    function setUp() public {
        token0 = new MintableToken(8);
        token1 = new MintableToken(18);

        token0.setOnDemand(true);
        token1.setOnDemand(true);

        vm.mockCall(oracle, abi.encodeWithSelector(ISiloOracle.quoteToken.selector), abi.encode(address(token1)));

        SiloConfigOverride memory overrides;
        overrides.token0 = address(token0);
        overrides.token1 = address(token1);
        overrides.solvencyOracle0 = oracle;
        overrides.maxLtvOracle0 = oracle;

        SiloFixture siloFixture = new SiloFixture();

        address hook;
        (siloConfig, silo0, silo1,,, hook) = siloFixture.deploy_local(overrides);

        partialLiquidation = IPartialLiquidation(hook);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_1wei_collateral_borrowNotPossible_burn_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 9998
    function test_1wei_collateral_borrowNotPossible_burn_fuzz(uint32 _amount) public {
        // (uint32 _amount, uint32 _burn) = (46200, 0);
        _1wei_collateral_borrowNotPossible_fuzz(_amount, 1);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_1wei_collateral_borrowNotPossible_noBurn_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 9999
    function test_1wei_collateral_borrowNotPossible_noBurn_fuzz(uint32 _amount) public {
        // (uint32 _amount, uint32 _burn) = (46200, 0);
        _1wei_collateral_borrowNotPossible_fuzz(_amount, 0);
    }

    function _1wei_collateral_borrowNotPossible_fuzz(uint32 _amount, uint32 _burn) internal {
        // if _burn != 0 then we will break 1:1000 ratio
        _depositAndBurn(_amount, _burn, ISilo.CollateralType.Collateral);

        uint256 price = 1e10;

        uint256 minAmount = _findMinDepositAmount(ISilo.CollateralType.Collateral);
        _mockQuote(minAmount, price * minAmount);
        console2.log("minAmount", minAmount);

        address borrower = makeAddr("Borrower");
        vm.prank(borrower);
        uint256 shares = silo0.deposit(minAmount, borrower);
        vm.stopPrank();

        _depositForBorrow(1e18, address(3));

        console2.log("got shares after deposit", shares);
        uint256 decimals0 = token0.decimals();
        emit log_named_decimal_uint("ratio 1.0 assets : %s shares", silo0.convertToShares(10 ** decimals0), decimals0);

        emit log_named_decimal_uint(
            "collateral value", SILO_LENS.calculateCollateralValue(siloConfig, borrower), decimals0
        );

        uint256 maxWithdraw = silo0.maxWithdraw(borrower);
        console2.log("maxWithdraw", maxWithdraw);
        // if we burn 1 wei, then getting max withdraw of 1 is not possible
        if (_burn == 0) vm.assume(maxWithdraw <= 1);

        uint256 maxRedeem = silo0.maxRedeem(borrower);
        console2.log("maxRedeem", maxRedeem);
        uint256 maxBorrow = silo1.maxBorrow(borrower);
        console2.log("maxBorrow", maxBorrow);

        assertLe(maxWithdraw, minAmount, "maxWithdraw should be less or equal to deposit");
        assertLe(maxRedeem, shares, "maxRedeem should NOT be more than actual shares");
        assertEq(maxBorrow, 0, "maxBorrow should be 0, because collateral value will be rounded down to 0");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_1wei_asset_protected_fuzz

    this test fail with `NoRepayAssets` error and make liquidation not possible
    when we have 1 wei of protected collateral and we borrow agains it.
    with fix in `valueToAssetsByRatio` we can liquidate.
    */
    /// forge-config: core_test.fuzz.runs = 10000
    function test_1wei_asset_protected_fuzz(
        uint32 _amount, uint32 _burn
    ) public {
        // ( uint32 _amount, uint32 _burn) = (0, 291965790);
        _1wei_asset_protected_liquidation(_amount, _burn, false);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_1wei_asset_protected_receiveSToken_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 10000
    function test_1wei_asset_protected_receiveSToken_fuzz(uint32 _amount, uint32 _burn) public {
        // (uint32 _amount, uint32 _burn) = (1, 1000);
        _1wei_asset_protected_liquidation(_amount, _burn, true);
    }

    function _1wei_asset_protected_liquidation(uint32 _amount, uint32 _burn, bool _receiveSToken) public {
        _deposit(100, makeAddr("to always have some deposit"), ISilo.CollateralType.Protected);
        _depositAndBurn(_amount, _burn, ISilo.CollateralType.Protected);

        _depositForBorrow(1e18, address(3));

        // in BTC/USDC 1e8 BTC == 100000e18 USDC,
        // so 1 wei BTC = 100000e18 USDC / 1e8 = 1e10 USDC
        uint256 price = 1e10;

        uint256 minAmount = _findMinDepositAmount(ISilo.CollateralType.Protected);
        vm.assume(minAmount == 1);
        _mockQuote(minAmount, price * minAmount);
        console2.log("minAmount for quote(%s) = %s", minAmount, price * minAmount);

        address borrower = makeAddr("Borrower");
        vm.prank(borrower);
        uint256 shares = silo0.deposit(minAmount, borrower, ISilo.CollateralType.Protected);
        vm.stopPrank();

        uint256 maxWithdraw = silo0.maxWithdraw(borrower, ISilo.CollateralType.Protected);
        uint256 maxRedeem = silo0.maxRedeem(borrower, ISilo.CollateralType.Protected);
        console2.log("maxWithdraw", maxWithdraw);
        console2.log("maxRedeem", maxRedeem);

        // maxWithdraw might be 1 wei less than minAmount, so we have to cover it too
        _mockQuote(maxWithdraw, price * maxWithdraw);

        assertLe(maxWithdraw, 1, "maxWithdraw should be <= 1");
        assertLe(maxRedeem, shares, "maxRedeem should be not more than actual shares");

        uint256 maxBorrow = silo1.maxBorrow(borrower);
        console2.log("maxBorrow >>>>>>", maxBorrow);
        assertLt(maxBorrow, price, "maxBorrow should be not more than price of 1 wei");

        vm.assume(maxBorrow > 0);

        _borrow(maxBorrow, borrower);
        maxRedeem = silo0.maxRedeem(borrower, ISilo.CollateralType.Protected);
        console2.log("maxRedeem", maxRedeem);

        (address protectedShareToken,, address debtShareToken) = silo0.config().getShareTokens(address(silo0));

        emit log_named_decimal_uint("ltv", SILO_LENS.getLtv(silo0, borrower), 16);
        console2.log("shares", IShareToken(protectedShareToken).balanceOf(borrower));

        vm.prank(borrower);
        vm.expectRevert(IShareToken.SenderNotSolventAfterTransfer.selector);
        require(IShareToken(protectedShareToken).transfer(address(1), 1), "transfer failed");
        vm.stopPrank();

        emit log_named_decimal_uint("ltv after transfer", SILO_LENS.getLtv(silo0, borrower), 16);
        console2.log("shares", IShareToken(protectedShareToken).balanceOf(borrower));

        _mockQuote(minAmount, 8e9 * minAmount); // price DROP
        _mockQuote(maxWithdraw, 8e9 * maxWithdraw); // price DROP
        assertFalse(silo1.isSolvent(borrower), "borrower should be ready to liquidate");

        {
            emit log_named_decimal_uint("ltv", SILO_LENS.getLtv(silo0, borrower), 16);

            vm.expectRevert(abi.encodeWithSelector(IPartialLiquidation.NoRepayAssets.selector));
            partialLiquidation.liquidationCall(
                address(token0), address(token1), borrower, type(uint256).max, _receiveSToken
            );

            // when pride drop even more, collateral assets will grow to 1 wei and we will be able to liquidate
            _mockQuote(minAmount, 7.7e9 * minAmount); // price DROP
            _mockQuote(maxWithdraw, 7.7e9 * maxWithdraw); // price DROP

            emit log_named_decimal_uint("ltv", SILO_LENS.getLtv(silo0, borrower), 16);
        }

        partialLiquidation.liquidationCall(
            address(token0), address(token1), borrower, type(uint256).max, _receiveSToken
        );

        if (_receiveSToken) {
            assertGt(IShareToken(protectedShareToken).balanceOf(address(this)), 0, "protected liquidated");
            assertEq(IShareToken(protectedShareToken).balanceOf(borrower), 0, "borrower liquidated");
        } else {
            uint256 btcBalance = token0.balanceOf(address(this));
            console2.log("BTC balance", btcBalance);
            assertEq(btcBalance, 1, "BTC balance is collateral after liquidation");
        }

        assertEq(IShareToken(protectedShareToken).balanceOf(borrower), 0, "protected shares are liquidated fully");
        assertEq(IShareToken(debtShareToken).balanceOf(borrower), 0, "debt repaid fully");
    }

    function _mockQuote(uint256 _amountIn, uint256 _price) public {
        vm.mockCall(
            oracle, abi.encodeWithSelector(ISiloOracle.quote.selector, _amountIn, address(token0)), abi.encode(_price)
        );
    }

    function _depositAndBurn(uint256 _amount, uint256 _burn, ISilo.CollateralType _collateralType) public {
        if (_amount == 0) return;

        uint256 shares = _deposit(_amount, address(this), _collateralType);
        vm.assume(shares >= _burn);

        if (_burn != 0) {
            (address protectedShareToken, address collateralShareToken,) =
                silo0.config().getShareTokens(address(silo0));
            address token =
                _collateralType == ISilo.CollateralType.Protected ? protectedShareToken : collateralShareToken;

            vm.prank(address(silo0));
            IShareToken(token).burn(address(this), address(this), _burn);
        }
    }

    function _findMinDepositAmount(ISilo.CollateralType _collateralType) internal view returns (uint256 minAmount) {
        uint256 assets = 1e18;
        uint256 shares = silo0.previewDeposit(assets, _collateralType);

        if (shares >= assets) return 1;

        console2.log("shares", shares);
        console2.log("assets", assets);
        console2.log("previewDeposit(1)", silo0.previewDeposit(1, _collateralType));
        console2.log("previewDeposit(10)", silo0.previewDeposit(10, _collateralType));

        minAmount = Math.ceilDiv(assets, shares);
        assertEq(silo0.previewDeposit(minAmount - 1, _collateralType), 0, "we can deposit less");
    }
}
