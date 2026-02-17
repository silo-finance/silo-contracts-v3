// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {IERC20Errors} from "openzeppelin5/interfaces/draft-IERC6093.sol";

import {MintableToken} from "../../_common/MintableToken.sol";
import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";
import {ShareTokenDecimalsPowLib} from "../../_common/ShareTokenDecimalsPowLib.sol";

/*
    forge test -vv --ffi --mc DepositTest
*/
contract DepositTest is SiloLittleHelper, Test {
    using ShareTokenDecimalsPowLib for uint256;

    ISiloConfig siloConfig;

    MintableToken weth;
    MintableToken usdc;

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event DepositProtected(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    function setUp() public {
        siloConfig = _setUpLocalFixture();

        weth = token0;
        usdc = token1;
    }

    /*
    forge test -vv --ffi --mt test_deposit_revertsZeroAssets
    */
    function test_deposit_revertsZeroAssets() public {
        uint256 _assets;
        ISilo.CollateralType _type;
        address depositor = makeAddr("Depositor");

        vm.expectRevert(ISilo.InputZeroShares.selector);
        silo0.deposit(_assets, depositor);

        vm.expectRevert(ISilo.InputZeroShares.selector);
        silo0.deposit(_assets, depositor, _type);
    }

    /*
    forge test -vv --ffi --mt test_deposit_reverts_WrongAssetType
    */
    function test_deposit_reverts_WrongAssetType() public {
        uint256 _assets = 1;
        address depositor = makeAddr("Depositor");

        vm.expectRevert();
        silo0.deposit(_assets, depositor, ISilo.CollateralType(uint8(ISilo.AssetType.Debt)));
    }

    /*
    forge test -vv --ffi --mt test_deposit_everywhere
    */
    function test_deposit_everywhere() public {
        uint256 assets = 1;
        address depositor = makeAddr("Depositor");

        _makeDeposit(silo0, token0, assets, depositor, ISilo.CollateralType.Collateral);
        _makeDeposit(silo0, token0, assets, depositor, ISilo.CollateralType.Protected);
        _makeDeposit(silo1, token1, assets, depositor, ISilo.CollateralType.Collateral);
        _makeDeposit(silo1, token1, assets, depositor, ISilo.CollateralType.Protected);

        ISiloConfig.ConfigData memory collateral = silo0.config().getConfig(address(silo0));
        ISiloConfig.ConfigData memory debt = silo0.config().getConfig(address(silo1));

        assertEq(token0.balanceOf(address(silo0)), assets * 2);
        assertEq(silo0.getCollateralAssets(), assets);
        assertEq(silo0.getTotalAssetsStorage(ISilo.AssetType.Protected), assets);
        assertEq(silo0.getDebtAssets(), 0);

        assertEq(
            IShareToken(collateral.collateralShareToken).balanceOf(depositor),
            assets.decimalsOffsetPow(),
            "collateral shares"
        );

        assertEq(
            IShareToken(collateral.protectedShareToken).balanceOf(depositor),
            assets.decimalsOffsetPow(),
            "protected shares"
        );

        assertEq(token1.balanceOf(address(silo1)), assets * 2);
        assertEq(silo1.getCollateralAssets(), assets);
        assertEq(silo1.getTotalAssetsStorage(ISilo.AssetType.Protected), assets);
        assertEq(silo1.getDebtAssets(), 0);

        assertEq(
            IShareToken(debt.collateralShareToken).balanceOf(depositor),
            assets.decimalsOffsetPow(),
            "collateral shares (on other silo)"
        );

        assertEq(
            IShareToken(debt.protectedShareToken).balanceOf(depositor),
            assets.decimalsOffsetPow(),
            "protected shares (on other silo)"
        );
    }

    /*
    forge test -vv --ffi --mt test_deposit_withDebt
    */
    function test_deposit_withDebt() public {
        uint256 assets = 1e18;
        address depositor = makeAddr("Depositor");

        _makeDeposit(silo0, token0, assets, depositor, ISilo.CollateralType.Collateral);
        _makeDeposit(silo0, token0, assets, depositor, ISilo.CollateralType.Protected);
        _makeDeposit(silo1, token1, assets, depositor, ISilo.CollateralType.Collateral);
        _makeDeposit(silo1, token1, assets, depositor, ISilo.CollateralType.Protected);

        uint256 maxBorrow = silo1.maxBorrow(depositor);
        _borrow(maxBorrow, depositor);

        _makeDeposit(silo0, token0, assets, depositor, ISilo.CollateralType.Collateral);
        _makeDeposit(silo0, token0, assets, depositor, ISilo.CollateralType.Protected);
        _makeDeposit(silo1, token1, assets, depositor, ISilo.CollateralType.Collateral);
        _makeDeposit(silo1, token1, assets, depositor, ISilo.CollateralType.Protected);
    }

    /*
    forge test -vv --ffi --mt test_deposit_toWrongSilo
    */
    function test_deposit_toWrongSilo() public {
        uint256 assets = 1;
        address depositor = makeAddr("Depositor");

        vm.prank(depositor);
        token1.approve(address(silo0), assets);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, silo0, 0, assets));
        vm.prank(depositor);
        silo0.deposit(assets, depositor, ISilo.CollateralType.Collateral);
    }

    /*
    forge test -vv --ffi --mt test_deposit_emitEvents
    */
    function test_deposit_emitEvents() public {
        uint256 assets = 1e18;
        address depositor = makeAddr("Depositor");

        token0.mint(depositor, assets * 2);
        vm.prank(depositor);
        token0.approve(address(silo0), assets * 2);

        vm.expectEmit(true, true, true, true);
        emit Deposit(depositor, depositor, assets, assets.decimalsOffsetPow());

        vm.prank(depositor);
        silo0.deposit(assets, depositor, ISilo.CollateralType.Collateral);

        vm.expectEmit(true, true, true, true);
        emit DepositProtected(depositor, depositor, assets, assets.decimalsOffsetPow());

        vm.prank(depositor);
        silo0.deposit(assets, depositor, ISilo.CollateralType.Protected);
    }

    /*
    forge test -vv --ffi --mt test_deposit_withWrongAssetType
    */
    function test_deposit_withWrongAssetType() public {
        uint256 assets = 1e18;
        address depositor = makeAddr("Depositor");

        token0.mint(depositor, assets * 2);
        vm.prank(depositor);
        token0.approve(address(silo0), assets * 2);

        uint8 invalidCollateralType = 3;

        vm.prank(depositor);

        (bool success,) = address(silo0).call(
            abi.encodeWithSelector(ISilo.deposit.selector, assets, depositor, invalidCollateralType)
        );

        assertFalse(success, "Expect deposit to fail");

        // deposit with correct type

        uint8 collateralType = 1;

        vm.expectEmit(true, true, true, true);
        emit Deposit(depositor, depositor, assets, assets.decimalsOffsetPow());

        vm.prank(depositor);

        (success,) =
            address(silo0).call(abi.encodeWithSelector(ISilo.deposit.selector, assets, depositor, collateralType));

        assertTrue(success, "Expect deposit to succeed");
    }

    /*
    forge test -vv --ffi --mt test_deposit_totalAssets
    */
    function test_deposit_totalAssets() public {
        _deposit(123, makeAddr("Depositor"));

        assertEq(silo0.totalAssets(), 123, "totalAssets 0");
        assertEq(silo1.totalAssets(), 0, "totalAssets 1");
    }
}
