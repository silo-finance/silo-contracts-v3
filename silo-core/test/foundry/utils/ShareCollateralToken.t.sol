// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IERC20Metadata, IERC20} from "openzeppelin5/token/ERC20/ERC20.sol";

import {ShareCollateralToken} from "silo-core/contracts/utils/ShareCollateralToken.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {SiloLittleHelper} from "../_common/SiloLittleHelper.sol";

/*
FOUNDRY_PROFILE=core_test forge test --ffi -vv --mc ShareCollateralTokenTest
*/
contract ShareCollateralTokenTest is Test, SiloLittleHelper {
    ISiloConfig public siloConfig;
    ShareCollateralToken public shareCollateralToken0;
    ShareCollateralToken public shareProtectedToken0;
    ShareCollateralToken public shareCollateralToken1;
    ShareCollateralToken public shareProtectedToken1;

    address immutable depositor;
    address immutable receiver;

    constructor() {
        depositor = makeAddr("depositor");
        receiver = makeAddr("receiver");
    }

    function setUp() public {
        siloConfig = _setUpLocalFixture();
        (address protectedShareToken, address collateralShareToken,) = siloConfig.getShareTokens(address(silo0));
        shareCollateralToken0 = ShareCollateralToken(collateralShareToken);
        shareProtectedToken0 = ShareCollateralToken(protectedShareToken);

        (protectedShareToken, collateralShareToken,) = siloConfig.getShareTokens(address(silo1));
        shareCollateralToken1 = ShareCollateralToken(collateralShareToken);
        shareProtectedToken1 = ShareCollateralToken(protectedShareToken);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_collateralShareToken_decimals
    */
    function test_collateralShareToken_decimals() public view {
        _checkDecimals(shareCollateralToken0, token0);
        _checkDecimals(shareProtectedToken0, token0);

        _checkDecimals(shareCollateralToken1, token1);
        _checkDecimals(shareProtectedToken1, token1);
    }

    function _checkDecimals(ShareCollateralToken _share, IERC20 _token) private view {
        assertEq(
            (10 ** IERC20Metadata(address(_share)).decimals()),
            10 ** IERC20Metadata(address(_token)).decimals(),
            "expect valid collateral decimals"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_sToken_transfer_zero_whenDeposit_
    */
    function test_sToken_transfer_zero_whenDeposit_collateral() public {
        _sToken_transfer_zero_whenDeposit(ISilo.CollateralType.Collateral);
    }

    function test_sToken_transfer_zero_whenDeposit_protected() public {
        _sToken_transfer_zero_whenDeposit(ISilo.CollateralType.Protected);
    }

    function _sToken_transfer_zero_whenDeposit(ISilo.CollateralType _collateralType) private {
        _deposit(100, depositor, _collateralType);

        vm.expectRevert(IShareToken.ZeroTransfer.selector);
        _token1(_collateralType).transfer(receiver, 0);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_sToken_transfer_whenDeposit_
    */
    function test_sToken_transfer_whenDeposits_collateral() public {
        _sToken_transfer_withDeposits(ISilo.CollateralType.Collateral);
    }

    function test_sToken_transfer_whenDeposits_protected() public {
        _sToken_transfer_withDeposits(ISilo.CollateralType.Protected);
    }

    function _sToken_transfer_withDeposits(ISilo.CollateralType _collateralType) private {
        _depositForBorrow(100, depositor, _collateralType);
        _deposit(100, depositor, _collateralType);

        IShareToken token1 = _token1(_collateralType);

        vm.prank(depositor);
        token1.transfer(receiver, 1);

        assertEq(_token1(_collateralType).balanceOf(receiver), 1, "transfer success");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_sToken_transfer_whenSolvent_
    */

    function test_sToken_transfer_whenSolvent_collateral() public {
        _sToken_transfer_whenSolvent(ISilo.CollateralType.Collateral);
    }

    function test_sToken_transfer_whenSolvent_protected() public {
        _sToken_transfer_whenSolvent(ISilo.CollateralType.Protected);
    }

    function _sToken_transfer_whenSolvent(ISilo.CollateralType _collateralType) private {
        _depositForBorrow(100, depositor, _collateralType);
        _deposit(100, depositor, _collateralType);

        _depositForBorrow(10, makeAddr("any"));
        _borrow(1, depositor);

        assertTrue(silo1.isSolvent(depositor), "expect solvent user");

        vm.startPrank(depositor);

        _token0(_collateralType).transfer(receiver, 1);
        assertEq(_token0(_collateralType).balanceOf(receiver), 1, "transfer0 success");

        _token1(_collateralType).transfer(receiver, 1);
        assertEq(_token1(_collateralType).balanceOf(receiver), 1, "transfer1 success");

        vm.stopPrank();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_sToken_transfer_NotSolvent_
    */
    function test_sToken_transfer_NotSolvent_collateral() public {
        _sToken_transfer_NotSolvent(ISilo.CollateralType.Collateral);
    }

    function test_sToken_transfer_NotSolvent_protected() public {
        _sToken_transfer_NotSolvent(ISilo.CollateralType.Protected);
    }

    function _sToken_transfer_NotSolvent(ISilo.CollateralType _collateralType) private {
        _depositForBorrow(1e18, depositor, _collateralType);
        _deposit(1e18, depositor, _collateralType);

        _depositForBorrow(0.75e18, makeAddr("any"));
        _borrow(0.75e18, depositor);

        vm.warp(block.timestamp + 20000 days);

        assertFalse(silo1.isSolvent(depositor), "expect NOT solvent user");

        IShareToken token0 = _token0(_collateralType);
        IShareToken token1 = _token1(_collateralType);

        vm.startPrank(depositor);

        vm.expectRevert(IShareToken.SenderNotSolventAfterTransfer.selector);
        token0.transfer(receiver, 1);
        assertEq(token0.balanceOf(receiver), 0, "transfer0 success");

        token1.transfer(receiver, 1);
        assertEq(token1.balanceOf(receiver), 1, "transfer1 success");

        vm.stopPrank();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_sToken_transferFrom_whenSolvent_
    */
    function test_sToken_transferFrom_whenSolvent_collateral() public {
        _sToken_transferFrom_whenSolvent(ISilo.CollateralType.Collateral);
    }

    function test_sToken_transferFrom_whenSolvent_protected() public {
        _sToken_transferFrom_whenSolvent(ISilo.CollateralType.Protected);
    }

    function _sToken_transferFrom_whenSolvent(ISilo.CollateralType _collateralType) private {
        address spender = makeAddr("Spender");
        uint256 amount = 100e18;

        _depositForBorrow(amount, depositor, _collateralType);
        _deposit(amount, depositor, _collateralType);

        _depositForBorrow(10, makeAddr("any"));
        _borrow(1, depositor);

        assertTrue(silo1.isSolvent(depositor), "expect solvent user");

        IShareToken shareToken = _token0(_collateralType);

        vm.prank(depositor);
        shareToken.approve(spender, amount);

        vm.prank(spender);
        shareToken.transferFrom(depositor, receiver, 1);
        assertEq(shareToken.balanceOf(receiver), 1, "transfer0 success");

        shareToken = _token1(_collateralType);

        vm.prank(depositor);
        shareToken.approve(spender, amount);

        vm.prank(spender);
        shareToken.transferFrom(depositor, receiver, 1);
        assertEq(shareToken.balanceOf(receiver), 1, "transfer1 success");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vvv --mt test_sToken_transferFrom_whenNotSolvent_
    */
    function test_sToken_transferFrom_whenNotSolvent_collateral() public {
        _sToken_transferFrom_NotSolvent(ISilo.CollateralType.Collateral);
    }

    function test_sToken_transferFrom_whenNotSolvent_protected() public {
        _sToken_transferFrom_NotSolvent(ISilo.CollateralType.Protected);
    }

    function _sToken_transferFrom_NotSolvent(ISilo.CollateralType _collateralType) private {
        address spender = makeAddr("Spender");

        _depositForBorrow(1e18, depositor, _collateralType);
        _deposit(1e18, depositor, _collateralType);

        _depositForBorrow(0.75e18, makeAddr("any"));
        _borrow(0.75e18, depositor);

        vm.warp(block.timestamp + 20000 days);

        assertFalse(silo1.isSolvent(depositor), "expect NOT solvent user");

        IShareToken token0 = _token0(_collateralType);
        IShareToken token1 = _token1(_collateralType);

        vm.prank(depositor);
        token0.approve(spender, 1);

        vm.prank(spender);
        vm.expectRevert(IShareToken.SenderNotSolventAfterTransfer.selector);
        token0.transferFrom(depositor, receiver, 1);
        assertEq(token0.balanceOf(receiver), 0, "transferFrom0 success");

        vm.prank(depositor);
        token1.approve(spender, 1);

        vm.prank(spender);
        token1.transferFrom(depositor, receiver, 1);
        assertEq(token1.balanceOf(receiver), 1, "transferFrom1 success");
    }

    function _token0(ISilo.CollateralType _collateralType) private view returns (ShareCollateralToken) {
        return _collateralType == ISilo.CollateralType.Collateral ? shareCollateralToken0 : shareProtectedToken0;
    }

    function _token1(ISilo.CollateralType _collateralType) private view returns (ShareCollateralToken) {
        return _collateralType == ISilo.CollateralType.Collateral ? shareCollateralToken1 : shareProtectedToken1;
    }
}
