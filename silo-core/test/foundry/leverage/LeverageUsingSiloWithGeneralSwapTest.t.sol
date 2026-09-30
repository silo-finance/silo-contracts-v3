// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "openzeppelin5/token/ERC20/extensions/IERC20Permit.sol";
import {MessageHashUtils} from "openzeppelin5/utils/cryptography/MessageHashUtils.sol";
import {Pausable} from "openzeppelin5/utils/Pausable.sol";
import {ILeverageRouter} from "silo-core/contracts/interfaces/ILeverageRouter.sol";
import {IERC20Errors} from "openzeppelin5/interfaces/draft-IERC6093.sol";
import {IAccessControl} from "openzeppelin5/access/IAccessControl.sol";

import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {AddrKey} from "common/addresses/AddrKey.sol";

import {LeverageRouterUsingSiloFlashloanWithGeneralSwapDeploy} from
    "silo-core/deploy/LeverageRouterUsingSiloFlashloanWithGeneralSwapDeploy.s.sol";

import {IERC20R} from "silo-core/contracts/interfaces/IERC20R.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IGeneralSwapModule} from "silo-core/contracts/interfaces/IGeneralSwapModule.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ILeverageUsingSiloFlashloan} from "silo-core/contracts/interfaces/ILeverageUsingSiloFlashloan.sol";
import {LeverageUsingSiloFlashloanWithGeneralSwap} from
    "silo-core/contracts/leverage/LeverageUsingSiloFlashloanWithGeneralSwap.sol";
import {LeverageRouter} from "silo-core/contracts/leverage/LeverageRouter.sol";
import {RescueModule} from "silo-core/contracts/leverage/modules/RescueModule.sol";

import {SiloLittleHelper} from "../_common/SiloLittleHelper.sol";
import {SwapRouterMock} from "./mocks/SwapRouterMock.sol";
import {WETH} from "./mocks/WETH.sol";

import {MintableToken} from "../_common/MintableToken.sol";
import {SiloFixture, SiloConfigOverride} from "../_common/fixtures/SiloFixture.sol";
import {RevertingReceiver} from "../_mocks/RevertingReceiver.sol";
import {LeverageUsingSiloFlashloanHarness} from "../_mocks/LeverageUsingSiloFlashloanHarness.sol";

/*
    FOUNDRY_PROFILE=core_test  forge test -vv --ffi --mc LeverageUsingSiloFlashloanWithGeneralSwapTest
*/
contract LeverageUsingSiloFlashloanWithGeneralSwapTest is SiloLittleHelper, Test {
    using SafeERC20 for IERC20;

    bytes32 internal constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    uint256 constant _PRECISION = 1e18;

    WETH weth;

    ISiloConfig cfg;
    LeverageUsingSiloFlashloanWithGeneralSwap siloLeverage;
    LeverageUsingSiloFlashloanWithGeneralSwap siloLeverageImpl;
    LeverageRouter leverageRouter;
    address collateralShareToken;
    address protectedShareToken;
    address debtShareToken;
    SwapRouterMock swap;

    Vm.Wallet wallet = vm.createWallet("Signer");
    address public pauser;

    function setUp() public {
        // wallet = vm.createWallet("Signer");

        cfg = _setUpLocalFixture();

        _deposit(1e18, address(1));
        _depositForBorrow(1e18, address(2));

        (protectedShareToken, collateralShareToken,) = cfg.getShareTokens(address(silo0));
        (,, debtShareToken) = cfg.getShareTokens(address(silo1));

        leverageRouter = _deployLeverage();

        siloLeverageImpl = LeverageUsingSiloFlashloanWithGeneralSwap(leverageRouter.LEVERAGE_IMPLEMENTATION());

        // Get the user's leverage contract
        siloLeverage =
            LeverageUsingSiloFlashloanWithGeneralSwap(leverageRouter.predictUserLeverageContract(wallet.addr));

        address nativeTokenForLocalTesting = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        leverageRouter.setRevenueReceiver(makeAddr("RevenueReceiver"));
        leverageRouter.setLeverageFee(0.0001e18);

        swap = new SwapRouterMock();

        token0.setOnDemand(false);
        token1.setOnDemand(false);

        weth = new WETH(token0);
        vm.etch(nativeTokenForLocalTesting, address(weth).code);

        // for some weird reason, etch start to work only when I added below line
        WETH(nativeTokenForLocalTesting).deposit{value: 1}();

        leverageRouter.grantRole(leverageRouter.PAUSER_ROLE(), pauser);
    }

    function _deployLeverage() internal returns (LeverageRouter) {
        AddrLib.init();
        AddrLib.setAddress(AddrKey.DAO, address(this));
        emit log("DAO is set to this test contract");
        emit log_named_uint("chain ID", block.chainid);

        LeverageRouterUsingSiloFlashloanWithGeneralSwapDeploy deployer =
            new LeverageRouterUsingSiloFlashloanWithGeneralSwapDeploy();

        deployer.disableDeploymentsSync();
        return deployer.run();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_leverage_alwaysRevert_InvalidFlashloanLender
    */
    function test_leverage_alwaysRevert_InvalidFlashloanLender(address _caller) public {
        vm.assume(_caller != address(0));

        vm.prank(_caller);
        vm.expectRevert(ILeverageUsingSiloFlashloan.InvalidFlashloanLender.selector);

        siloLeverageImpl.onFlashLoan(address(0), address(0), 0, 0, "");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_leverage_alwaysRevert_UnknownAction
    */
    function test_leverage_alwaysRevert_UnknownAction() public {
        address nativeTokenForLocalTesting = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

        LeverageUsingSiloFlashloanHarness harness =
            new LeverageUsingSiloFlashloanHarness(address(leverageRouter), nativeTokenForLocalTesting);

        harness.setTxData(address(0), cfg, ILeverageUsingSiloFlashloan.LeverageAction.Undefined, address(this), 0);

        vm.expectRevert(abi.encodeWithSelector(ILeverageUsingSiloFlashloan.UnknownAction.selector));

        harness.onFlashLoan(address(0), address(0), 0, 0, "Any data");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_leverage_example_noInterest
    */
    function test_leverage_example_noInterest() public {
        _openLeverageExample();
        _closeLeverageExample();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_leverage_example_protected_noInterest
    */
    function test_leverage_example_protected_noInterest() public {
        _openLeverageExample(ISilo.CollateralType.Protected);
        _closeLeverageExample(ISilo.CollateralType.Protected);
    }

    /*
    accrue interest then close

    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_leverage_example_withInterest_solvent
    */
    function test_leverage_example_withInterest_solvent() public {
        address user = wallet.addr;

        _openLeverageExample();

        uint256 totalAssetsBefore = silo1.totalAssets();

        vm.warp(block.timestamp + 2000 days);

        uint256 totalAssetsAfter = silo1.totalAssets();
        assertGt(totalAssetsAfter, totalAssetsBefore * 1005 / 1000, "expect at least 0.5% generated interest");

        assertTrue(silo1.isSolvent(user), "we want example with solvent user");

        _closeLeverageExample();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_leverage_example_withInterest_inSolvent
    */
    function test_leverage_example_withInterest_inSolvent() public {
        address user = wallet.addr;

        _openLeverageExample();

        vm.startPrank(user);
        silo0.withdraw(silo0.maxWithdraw(user), user, user);

        vm.warp(block.timestamp + 1000 days);

        assertLt(SILO_LENS.getUserLTV(silo1, user), 0.9e18, "we want case when there is no bad debt");
        assertFalse(silo1.isSolvent(user), "we want example with inSolvent user");

        _closeLeverageExample();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_leverage_anySiloForFlashloan -vv
    */
    function test_leverage_anySiloForFlashloan() public {
        // SEPARATE SILO FOR FLASHLOAN

        SiloFixture siloFixture = new SiloFixture();

        MintableToken tokenA = new MintableToken(18);

        SiloConfigOverride memory overrides;
        overrides.token0 = address(tokenA);
        overrides.token1 = address(token1);
        overrides.configName = "Silo_Local_noOracle";

        (,, ISilo siloFlashloan,,,) = siloFixture.deploy_local(overrides);

        vm.label(address(siloFlashloan), "siloFlashloan");

        token1.mint(address(this), 5e18);
        token1.approve(address(siloFlashloan), 5e18);
        siloFlashloan.deposit(5e18, address(this));

        // OPEN

        address user = makeAddr("user");
        uint256 depositAmount = 0.1e18;
        uint256 multiplier = 1.08e18;

        (
            ILeverageUsingSiloFlashloan.FlashArgs memory flashArgs,
            ILeverageUsingSiloFlashloan.DepositArgs memory depositArgs,
            IGeneralSwapModule.SwapArgs memory swapArgs
        ) = _defaultOpenArgs(depositAmount, multiplier, address(siloFlashloan));

        _openLeverage(user, flashArgs, depositArgs, swapArgs);

        assertGt(silo1.maxRepay(user), 0, "users has debt");

        uint256 fee = _flashFee(siloFlashloan, flashArgs.amount);
        assertGt(fee, 0, "we want setup with some fee");
        assertEq(token1.balanceOf(address(siloFlashloan)), 5e18 + fee, "siloFlashloan got flashloan fees");

        // CLOSE

        ILeverageUsingSiloFlashloan.CloseLeverageArgs memory closeArgs;

        (closeArgs, swapArgs) = _defaultCloseArgs(address(siloFlashloan));

        _closeLeverage(user, closeArgs, swapArgs);

        _assertUserHasNoPosition(user);
        _assertNoApprovalsFromLeverage({_checkSwap: false});
        _assertSiloLeverageHasNoTokens();
        _assertThereIsNoDebtApprovals(user);

        assertGt(token1.balanceOf(address(siloFlashloan)), 5e18 + fee, "siloFlashloan got another flashloan fee");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_leverage_pausable_openLeveragePosition -vv
    */
    function test_leverage_pausable_openLeveragePosition() public {
        // The deployer (address(this)) has PAUSER_ROLE and can pause
        leverageRouter.pause();

        ILeverageUsingSiloFlashloan.FlashArgs memory flashArgs;
        ILeverageUsingSiloFlashloan.DepositArgs memory depositArgs;
        IGeneralSwapModule.SwapArgs memory swapArgs;

        vm.expectRevert(Pausable.EnforcedPause.selector);
        leverageRouter.openLeveragePosition(flashArgs, abi.encode(swapArgs), depositArgs);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_leverage_pausable_openLeveragePositionPermit -vv
    */
    function test_leverage_pausable_openLeveragePositionPermit() public {
        // The deployer (address(this)) has PAUSER_ROLE and can pause
        leverageRouter.pause();

        ILeverageUsingSiloFlashloan.FlashArgs memory flashArgs;
        ILeverageUsingSiloFlashloan.DepositArgs memory depositArgs;
        ILeverageUsingSiloFlashloan.Permit memory depositAllowance;
        IGeneralSwapModule.SwapArgs memory swapArgs;

        vm.expectRevert(Pausable.EnforcedPause.selector);
        leverageRouter.openLeveragePositionPermit(flashArgs, abi.encode(swapArgs), depositArgs, depositAllowance);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_leverage_pausable_closeLeveragePosition -vv
    */
    function test_leverage_pausable_closeLeveragePosition() public {
        // The deployer (address(this)) has PAUSER_ROLE and can pause
        leverageRouter.pause();

        ILeverageUsingSiloFlashloan.CloseLeverageArgs memory closeArgs;
        IGeneralSwapModule.SwapArgs memory swapArgs;

        vm.expectRevert(Pausable.EnforcedPause.selector);
        leverageRouter.closeLeveragePosition(abi.encode(swapArgs), closeArgs);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_leverage_pausable_closeLeveragePositionPermit -vv
    */
    function test_leverage_pausable_closeLeveragePositionPermit() public {
        vm.prank(pauser);
        leverageRouter.pause();

        ILeverageUsingSiloFlashloan.CloseLeverageArgs memory closeArgs;
        ILeverageUsingSiloFlashloan.Permit memory withdrawAllowance;
        IGeneralSwapModule.SwapArgs memory swapArgs;

        vm.expectRevert(Pausable.EnforcedPause.selector);
        leverageRouter.closeLeveragePositionPermit(abi.encode(swapArgs), closeArgs, withdrawAllowance);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_leverage_pausable_onlyPauserRoleCanPause -vv
    */
    function test_leverage_pausable_onlyPauserRoleCanPause() public {
        vm.prank(pauser);
        leverageRouter.pause();
        assertTrue(leverageRouter.paused(), "should be paused");

        vm.prank(pauser);
        leverageRouter.unpause();
        assertFalse(leverageRouter.paused(), "should be unpaused");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_leverage_pausable_nonPauserCannotPause -vv
    */
    function test_leverage_pausable_nonPauserCannotPause() public {
        address notPauser = makeAddr("notPauser");

        bytes32 pauserRole = leverageRouter.PAUSER_ROLE();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, notPauser, pauserRole)
        );

        vm.prank(notPauser);
        leverageRouter.pause();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_leverage_pausable_nonPauserCannotUnpause -vv
    */
    function test_leverage_pausable_nonPauserCannotUnpause() public {
        vm.prank(pauser);
        leverageRouter.pause();
        assertTrue(leverageRouter.paused(), "should be paused");

        address notPauser = makeAddr("notPauser");

        bytes32 pauserRole = leverageRouter.PAUSER_ROLE();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, notPauser, pauserRole)
        );

        vm.prank(notPauser);
        leverageRouter.unpause();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_leverage_pausable_adminCanGrantPauserRole -vv
    */
    function test_leverage_pausable_adminCanGrantPauserRole() public {
        address newPauser = makeAddr("newPauser");
        assertFalse(
            leverageRouter.hasRole(leverageRouter.PAUSER_ROLE(), newPauser), "should not have pauser role initially"
        );

        // address(this) has DEFAULT_ADMIN_ROLE from deployment
        leverageRouter.grantRole(leverageRouter.PAUSER_ROLE(), newPauser);

        assertTrue(
            leverageRouter.hasRole(leverageRouter.PAUSER_ROLE(), newPauser),
            "should have pauser role after granting"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_leverage_pausable_adminCanRevokePauserRole -vv
    */
    function test_leverage_pausable_adminCanRevokePauserRole() public {
        leverageRouter.grantRole(leverageRouter.PAUSER_ROLE(), pauser);
        assertTrue(
            leverageRouter.hasRole(leverageRouter.PAUSER_ROLE(), pauser), "should have pauser role initially"
        );

        // address(this) has DEFAULT_ADMIN_ROLE from deployment
        leverageRouter.revokeRole(leverageRouter.PAUSER_ROLE(), pauser);

        assertFalse(
            leverageRouter.hasRole(leverageRouter.PAUSER_ROLE(), pauser),
            "should not have pauser role after revoking"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_leverage_pausable_nonAdminCannotGrantPauserRole -vv
    */
    function test_leverage_pausable_nonAdminCannotGrantPauserRole() public {
        address anyAccount = makeAddr("anyAccount");
        address newPauser = makeAddr("newPauser");

        bytes32 pauserRole = leverageRouter.PAUSER_ROLE();
        bytes32 adminRole = leverageRouter.PAUSER_ADMIN_ROLE();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, anyAccount, adminRole)
        );

        vm.prank(anyAccount);
        leverageRouter.grantRole(pauserRole, newPauser);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_leverage_pausable_nonAdminCannotRevokePauserRole -vv
    */
    function test_leverage_pausable_nonAdminCannotRevokePauserRole() public {
        address anyAccount = makeAddr("anyAccount");
        bytes32 pauserRole = leverageRouter.PAUSER_ROLE();
        bytes32 adminRole = leverageRouter.PAUSER_ADMIN_ROLE();

        leverageRouter.grantRole(pauserRole, pauser);
        assertTrue(leverageRouter.hasRole(pauserRole, pauser));

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, anyAccount, adminRole)
        );

        vm.prank(anyAccount);
        leverageRouter.revokeRole(pauserRole, pauser);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_leverage_almostMax
    */
    function test_leverage_almostMax() public {
        address user = wallet.addr;
        uint256 depositAmount = 0.1e18;
        uint256 multiplier = 2.8e18;

        _depositForBorrow(1000e18, address(3));

        (
            ILeverageUsingSiloFlashloan.FlashArgs memory flashArgs,
            ILeverageUsingSiloFlashloan.DepositArgs memory depositArgs,
            IGeneralSwapModule.SwapArgs memory swapArgs
        ) = _defaultOpenArgs(depositAmount, multiplier, address(silo1));

        _prepareForOpeningLeverage({
            _user: user,
            _flashArgs: flashArgs,
            _depositArgs: depositArgs,
            _swapArgs: swapArgs,
            _approveAssets: true
        });

        // counterexample
        vm.prank(user);
        leverageRouter.openLeveragePosition(flashArgs, abi.encode(swapArgs), depositArgs);

        // emit log_named_decimal_uint("totalUserCollateral", totalUserCollateral, 18);
        // emit log_named_decimal_uint("leverage", totalUserCollateral * 100 / depositAmount, 2);
        emit log_named_decimal_uint("LTV", SILO_LENS.getUserLTV(silo0, user), 16);

        _assertThereIsNoDebtApprovals(user);
        _assertNoApprovalsFromLeverage({_checkSwap: true});
        _assertSiloLeverageHasNoTokens();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_leverage_withETH_pass
    */
    function test_leverage_withETH_pass() public {
        address user = wallet.addr;
        vm.deal(user, 0.2e18);

        uint256 depositAmount = 0.1e18;
        uint256 multiplier = 2.0e18;

        _depositForBorrow(1000e18, address(3));

        (
            ILeverageUsingSiloFlashloan.FlashArgs memory flashArgs,
            ILeverageUsingSiloFlashloan.DepositArgs memory depositArgs,
            IGeneralSwapModule.SwapArgs memory swapArgs
        ) = _defaultOpenArgs(depositAmount, multiplier, address(silo1));

        _prepareForOpeningLeverage({
            _user: user,
            _flashArgs: flashArgs,
            _depositArgs: depositArgs,
            _swapArgs: swapArgs,
            _approveAssets: false // we dont want approval, we will use ETH
        });

        assertEq(SILO_LENS.getUserLTV(silo0, user), 0, "user has no position");

        vm.startPrank(user);

        // to make sure we have no tokens to transferFrom
        token0.burn(token0.balanceOf(user));

        assertEq(
            IERC20(silo0.asset()).balanceOf(user),
            0,
            "make sure user do not have any tokens, so we can't transferFrom"
        );

        vm.expectRevert(ILeverageUsingSiloFlashloan.IncorrectNativeTokenAmount.selector);
        leverageRouter.openLeveragePosition{value: depositArgs.amount - 1}({
            _flashArgs: flashArgs,
            _swapArgs: abi.encode(swapArgs),
            _depositArgs: depositArgs
        });

        vm.expectRevert(ILeverageUsingSiloFlashloan.IncorrectNativeTokenAmount.selector);
        leverageRouter.openLeveragePosition{value: depositArgs.amount + 1}({
            _flashArgs: flashArgs,
            _swapArgs: abi.encode(swapArgs),
            _depositArgs: depositArgs
        });

        leverageRouter.openLeveragePosition{value: depositArgs.amount}({
            _flashArgs: flashArgs,
            _swapArgs: abi.encode(swapArgs),
            _depositArgs: depositArgs
        });

        vm.stopPrank();

        assertEq(SILO_LENS.getUserLTV(silo0, user), 0.67792014100738933e18, "user has leverage position");

        _assertThereIsNoDebtApprovals(user);
        _assertNoApprovalsFromLeverage({_checkSwap: true});
        _assertSiloLeverageHasNoTokens();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_full_leverage_flow_native_collateral_pass
    */
    function test_full_leverage_flow_native_collateral_pass() public {
        _open_leverage_native_pass(ISilo.CollateralType.Collateral);

        assertEq(
            SILO_LENS.getUserLTV(silo0, wallet.addr),
            0.67792014100738933e18,
            "sanity check: user has leverage position"
        );

        _closeLeverageExample(ISilo.CollateralType.Collateral);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_full_leverage_flow_native_protected_pass
    */
    function test_full_leverage_flow_native_protected_pass() public {
        _open_leverage_native_pass(ISilo.CollateralType.Protected);

        assertEq(
            SILO_LENS.getUserLTV(silo0, wallet.addr),
            0.67792014100738933e18,
            "sanity check: user has leverage position"
        );

        _closeLeverageExample(ISilo.CollateralType.Protected);
    }

    function _open_leverage_native_pass(ISilo.CollateralType _collateralType) internal {
        address user = wallet.addr;
        vm.deal(user, 0.2e18);

        uint256 depositAmount = 0.1e18;
        uint256 multiplier = 2.0e18;

        _depositForBorrow(1000e18, address(3));

        (
            ILeverageUsingSiloFlashloan.FlashArgs memory flashArgs,
            ILeverageUsingSiloFlashloan.DepositArgs memory depositArgs,
            IGeneralSwapModule.SwapArgs memory swapArgs
        ) = _defaultOpenArgs(depositAmount, multiplier, address(silo1));

        depositArgs.collateralType = _collateralType;

        _prepareForOpeningLeverage({
            _user: user,
            _flashArgs: flashArgs,
            _depositArgs: depositArgs,
            _swapArgs: swapArgs,
            _approveAssets: false // we dont want approval, we will use ETH
        });

        assertEq(SILO_LENS.getUserLTV(silo0, user), 0, "user has no position");

        vm.prank(user);
        leverageRouter.openLeveragePosition{value: depositArgs.amount}({
            _flashArgs: flashArgs,
            _swapArgs: abi.encode(swapArgs),
            _depositArgs: depositArgs
        });

        _assertThereIsNoDebtApprovals(user);
        _assertNoApprovalsFromLeverage({_checkSwap: true});
        _assertSiloLeverageHasNoTokens();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_openLeverage_withPermit_collateral
    */
    function test_openLeverage_withPermit_collateral() public {
        _openleverage_withDepositPermit(ISilo.CollateralType.Collateral);

        assertGt(IERC20(collateralShareToken).balanceOf(wallet.addr), 0, "user has collateral share token");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_openLeverage_withPermit_protected
    */
    function test_openLeverage_withPermit_protected() public {
        _openleverage_withDepositPermit(ISilo.CollateralType.Protected);

        assertGt(IERC20(protectedShareToken).balanceOf(wallet.addr), 0, "user has protected share token");
    }

    function _openleverage_withDepositPermit(ISilo.CollateralType _collateralType) internal {
        address user = wallet.addr;
        uint256 depositAmount = 0.1e18;
        uint256 multiplier = 2.0e18;

        _depositForBorrow(1000e18, address(3));

        (
            ILeverageUsingSiloFlashloan.FlashArgs memory flashArgs,
            ILeverageUsingSiloFlashloan.DepositArgs memory depositArgs,
            IGeneralSwapModule.SwapArgs memory swapArgs
        ) = _defaultOpenArgs(depositAmount, multiplier, address(silo1));

        depositArgs.collateralType = _collateralType;

        _prepareForOpeningLeverage({
            _user: user,
            _flashArgs: flashArgs,
            _depositArgs: depositArgs,
            _swapArgs: swapArgs,
            _approveAssets: false
        });

        assertEq(SILO_LENS.getUserLTV(silo0, user), 0, "user has no position");

        vm.startPrank(user);

        leverageRouter.openLeveragePositionPermit({
            _flashArgs: flashArgs,
            _swapArgs: abi.encode(swapArgs),
            _depositArgs: depositArgs,
            _depositAllowance: _generatePermit(silo0.asset())
        });

        vm.stopPrank();

        assertEq(SILO_LENS.getUserLTV(silo0, user), 0.67792014100738933e18, "user has leverage position");

        _assertThereIsNoDebtApprovals(user);
        _assertNoApprovalsFromLeverage({_checkSwap: true});
        _assertSiloLeverageHasNoTokens();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_leverage_closeWithPermit_collateral
    */
    function test_leverage_closeWithPermit_collateral() public {
        _leverage_closeWithPermit(ISilo.CollateralType.Collateral);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_leverage_closeWithPermit_protected
    */
    function test_leverage_closeWithPermit_protected() public {
        _leverage_closeWithPermit(ISilo.CollateralType.Protected);
    }

    function _leverage_closeWithPermit(ISilo.CollateralType _collateralType) internal {
        _openLeverageExample(_collateralType);

        address shareCollateral =
            _collateralType == ISilo.CollateralType.Protected ? protectedShareToken : collateralShareToken;
        assertGt(IERC20(shareCollateral).balanceOf(wallet.addr), 0, "user has collateral share token");

        address user = wallet.addr;

        (
            ILeverageUsingSiloFlashloan.CloseLeverageArgs memory closeArgs,
            IGeneralSwapModule.SwapArgs memory swapArgs
        ) = _defaultCloseArgs(address(silo1));

        closeArgs.collateralType = _collateralType;

        _closeLeverage(user, closeArgs, swapArgs, _generatePermit(shareCollateral));

        assertEq(silo0.balanceOf(user), 0, "user nas NO collateral");
        assertEq(silo1.maxRepay(user), 0, "user has NO debt");

        _assertNoApprovalsFromLeverage({_checkSwap: false});
        _assertSiloLeverageHasNoTokens();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_leverage_frontrun_closeWithPermit
    */
    function test_leverage_frontrun_closeWithPermit() public {
        _openLeverageExample();

        address user = wallet.addr;

        (
            ILeverageUsingSiloFlashloan.CloseLeverageArgs memory _closeArgs,
            IGeneralSwapModule.SwapArgs memory _swapArgs
        ) = _defaultCloseArgs(address(silo1));

        ILeverageUsingSiloFlashloan.Permit memory permit = _generatePermit(collateralShareToken);
        // frontrun
        IERC20Permit(collateralShareToken).permit({
            owner: user,
            spender: address(siloLeverage),
            value: permit.value,
            deadline: permit.deadline,
            v: permit.v,
            r: permit.r,
            s: permit.s
        });

        _closeLeverage(user, _closeArgs, _swapArgs, permit);

        assertEq(silo0.balanceOf(user), 0, "user nas NO collateral");
        assertEq(silo1.maxRepay(user), 0, "user has NO debt");

        _assertNoApprovalsFromLeverage({_checkSwap: false});
        _assertSiloLeverageHasNoTokens();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_leverage_AboveMaxLtv
    */
    function test_leverage_AboveMaxLtv() public {
        address user = wallet.addr;
        uint256 depositAmount = 0.1e18;
        uint256 multiplier = 2.81e18;

        _depositForBorrow(1000e18, address(3));

        (
            ILeverageUsingSiloFlashloan.FlashArgs memory flashArgs,
            ILeverageUsingSiloFlashloan.DepositArgs memory depositArgs,
            IGeneralSwapModule.SwapArgs memory swapArgs
        ) = _defaultOpenArgs(depositAmount, multiplier, address(silo1));

        _prepareForOpeningLeverage({
            _user: user,
            _flashArgs: flashArgs,
            _depositArgs: depositArgs,
            _swapArgs: swapArgs,
            _approveAssets: true
        });

        // counterexample
        vm.prank(user);
        vm.expectRevert(ISilo.AboveMaxLtv.selector);
        leverageRouter.openLeveragePosition(flashArgs, abi.encode(swapArgs), depositArgs);

        _assertThereIsNoDebtApprovals(user);
        _assertNoApprovalsFromLeverage({_checkSwap: true});
        _assertSiloLeverageHasNoTokens();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_leverage_debtApprovalAbuse
    */
    function test_leverage_debtApprovalAbuse() public {
        address user = wallet.addr;
        address attacker = makeAddr("attacker");

        _openLeverageExample();

        _giveMaxApprovalsToLeverage();

        uint256 userDebtBefore = IERC20(debtShareToken).balanceOf(user);

        _leverage_approvalAbuse(
            address(silo1),
            abi.encodeWithSignature("borrow(uint256,address,address)", 1, attacker, user),
            abi.encodePacked(IShareToken.AmountExceedsAllowance.selector)
        );

        assertEq(userDebtBefore, IERC20(debtShareToken).balanceOf(user), "user debt allowance was abused");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_leverage_transferFromAbuse
    */
    function test_leverage_transferFromAbuse() public {
        _openLeverageExample();

        _giveMaxApprovalsToLeverage();

        address user = wallet.addr;
        address attacker = makeAddr("attacker");

        uint256 userBalanceBefore = token0.balanceOf(user);
        emit log_named_address("leverage", address(siloLeverage));

        address swapModule = address(
            LeverageUsingSiloFlashloanWithGeneralSwap(leverageRouter.LEVERAGE_IMPLEMENTATION()).SWAP_MODULE()
        );

        _leverage_approvalAbuse(
            address(silo0.asset()),
            abi.encodeWithSignature("transferFrom(address,address,uint256)", user, attacker, 1),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, swapModule, 0, 1)
        );

        assertEq(userBalanceBefore, token0.balanceOf(user), "user allowance was abused");
    }

    function _giveMaxApprovalsToLeverage() internal {
        address user = wallet.addr;

        // user gave MAX approvals

        vm.startPrank(user);

        IERC20R(debtShareToken).setReceiveApproval(address(siloLeverage), type(uint256).max);
        IERC20(silo0.asset()).forceApprove(address(siloLeverage), type(uint256).max);
        IERC20(protectedShareToken).forceApprove(address(siloLeverage), type(uint256).max);
        IERC20(collateralShareToken).forceApprove(address(siloLeverage), type(uint256).max);

        vm.stopPrank();

        // make sure token balance is not an issue

        token0.mint(user, 100e18);
        token1.mint(user, 100e18);
    }

    function _leverage_approvalAbuse(
        address _exchangeProxy,
        bytes memory _swapCallData,
        bytes memory _expectedError
    ) internal {
        address attacker = makeAddr("attacker");
        uint256 depositAmount = 1e18;
        uint256 multiplier = 1.00001e18;

        _depositForBorrow(1000e18, address(3));

        // Get attacker's leverage contract address
        address attackerLeverageContract = leverageRouter.predictUserLeverageContract(attacker);

        // this will bypass ZeroAmountOutError
        token0.mint(attackerLeverageContract, 1e18);

        (
            ILeverageUsingSiloFlashloan.FlashArgs memory flashArgs,
            ILeverageUsingSiloFlashloan.DepositArgs memory depositArgs,
        ) = _defaultOpenArgs(depositAmount, multiplier, address(silo1));

        IGeneralSwapModule.SwapArgs memory swapArgs = IGeneralSwapModule.SwapArgs({
            buyToken: address(silo0.asset()),
            sellToken: address(silo1.asset()),
            allowanceTarget: address(swap),
            exchangeProxy: _exchangeProxy,
            swapCallData: _swapCallData
        });

        _prepareForOpeningLeverage({
            _user: attacker,
            _flashArgs: flashArgs,
            _depositArgs: depositArgs,
            _swapArgs: swapArgs,
            _approveAssets: true
        });

        vm.prank(attacker);
        vm.expectRevert(_expectedError);
        leverageRouter.openLeveragePosition(flashArgs, abi.encode(swapArgs), depositArgs);
    }

    function _openLeverageExample() internal {
        _openLeverageExample(ISilo.CollateralType.Collateral);
    }

    function _openLeverageExample(ISilo.CollateralType _collateralType) internal {
        address user = wallet.addr;
        uint256 depositAmount = 0.1e18;
        uint256 multiplier = 1.08e18;

        (
            ILeverageUsingSiloFlashloan.FlashArgs memory flashArgs,
            ILeverageUsingSiloFlashloan.DepositArgs memory depositArgs,
            IGeneralSwapModule.SwapArgs memory swapArgs
        ) = _defaultOpenArgs(depositAmount, multiplier, address(silo1));

        depositArgs.collateralType = _collateralType;

        (uint256 totalDeposited,) = _openLeverage(user, flashArgs, depositArgs, swapArgs);

        emit log_named_uint("totalDeposited", totalDeposited);
        uint256 finalMultiplier = totalDeposited * _PRECISION / depositArgs.amount;

        assertEq(finalMultiplier, 2.06899308e18, "finalMultiplier");

        address shareCollateral =
            _collateralType == ISilo.CollateralType.Collateral ? collateralShareToken : protectedShareToken;

        assertEq(
            silo0.previewRedeem(IERC20(shareCollateral).balanceOf(user), _collateralType),
            0.206899308e18,
            "users collateral"
        );

        uint256 flashFee = _flashFee(silo1, flashArgs.amount);

        assertEq(
            silo1.maxRepay(user), flashArgs.amount + flashFee, "user has debt equal to flashloan + flashloan fee"
        );

        assertEq(silo1.maxRepay(user), 0.10908e18, "users debt");

        _assertNoApprovalsFromLeverage({_checkSwap: true});
        _assertSiloLeverageHasNoTokens();
    }

    function _prepareForOpeningLeverage(
        address _user,
        ILeverageUsingSiloFlashloan.FlashArgs memory _flashArgs,
        ILeverageUsingSiloFlashloan.DepositArgs memory _depositArgs,
        IGeneralSwapModule.SwapArgs memory _swapArgs,
        bool _approveAssets
    ) internal {
        token0.mint(_user, _depositArgs.amount);

        // mock the swap: debt token -> collateral token, price is 1:1, lt's mock some fee
        swap.setSwap(_swapArgs.sellToken, _flashArgs.amount, _swapArgs.buyToken, _flashArgs.amount * 99 / 100);

        // APPROVALS

        address userLeverage = leverageRouter.predictUserLeverageContract(_user);

        vm.startPrank(_user);

        if (_approveAssets) {
            // siloLeverage needs approval to pull user tokens to do deposit in behalf of user
            IERC20(_depositArgs.silo.asset()).forceApprove(userLeverage, _depositArgs.amount);
        }

        uint256 debtReceiveApproval =
            leverageRouter.calculateDebtReceiveApproval(ISilo(_flashArgs.flashloanTarget), _flashArgs.amount);

        // user must set receive approval for debt share token
        IERC20R(debtShareToken).setReceiveApproval(userLeverage, debtReceiveApproval);
        vm.stopPrank();
    }

    function _openLeverage(
        address _user,
        ILeverageUsingSiloFlashloan.FlashArgs memory _flashArgs,
        ILeverageUsingSiloFlashloan.DepositArgs memory _depositArgs,
        IGeneralSwapModule.SwapArgs memory _swapArgs
    ) internal returns (uint256 totalDeposit, uint256 totalBorrow) {
        _prepareForOpeningLeverage({
            _user: _user,
            _flashArgs: _flashArgs,
            _depositArgs: _depositArgs,
            _swapArgs: _swapArgs,
            _approveAssets: true
        });

        {
            uint256 swapAmountOut = _flashArgs.amount * 99 / 100;
            uint256 totalUserDeposit;

            uint256 leverageFee = leverageRouter.calculateLeverageFee(_depositArgs.amount + swapAmountOut);
            totalUserDeposit = _depositArgs.amount + swapAmountOut - leverageFee;

            uint256 flashloanFee = _flashFee(ISilo(_flashArgs.flashloanTarget), _flashArgs.amount);

            vm.expectEmit(leverageRouter.predictUserLeverageContract(_user));

            emit ILeverageUsingSiloFlashloan.OpenLeverage({
                totalBorrow: _flashArgs.amount + flashloanFee,
                totalDeposit: totalUserDeposit,
                flashloanAmount: _flashArgs.amount,
                swapAmountOut: swapAmountOut,
                borrowerDeposit: _depositArgs.amount,
                borrower: _user,
                leverageFee: leverageFee,
                flashloanFee: flashloanFee
            });
        }

        vm.prank(_user);
        leverageRouter.openLeveragePosition(_flashArgs, abi.encode(_swapArgs), _depositArgs);

        _assertThereIsNoDebtApprovals(_user);

        address shareCollateral = _depositArgs.collateralType == ISilo.CollateralType.Collateral
            ? collateralShareToken
            : protectedShareToken;

        totalDeposit = silo0.previewRedeem(IERC20(shareCollateral).balanceOf(_user), _depositArgs.collateralType);
        totalBorrow = silo1.maxRepay(_user);
    }

    function _closeLeverageExample() internal {
        _closeLeverageExample(ISilo.CollateralType.Collateral);
    }

    function _closeLeverageExample(ISilo.CollateralType _collateralType) internal {
        address user = wallet.addr;

        (
            ILeverageUsingSiloFlashloan.CloseLeverageArgs memory _closeArgs,
            IGeneralSwapModule.SwapArgs memory _swapArgs
        ) = _defaultCloseArgs(address(silo1));

        _closeArgs.collateralType = _collateralType;

        _closeLeverage(user, _closeArgs, _swapArgs);

        assertEq(silo0.balanceOf(user), 0, "user nas NO collateral");
        assertEq(silo1.maxRepay(user), 0, "user has NO debt");

        _assertSiloLeverageHasNoTokens();
    }

    function _closeLeverage(
        address _user,
        ILeverageUsingSiloFlashloan.CloseLeverageArgs memory _closeArgs,
        IGeneralSwapModule.SwapArgs memory _swapArgs
    ) internal {
        ILeverageUsingSiloFlashloan.Permit memory _withdrawPermit;
        _closeLeverage(_user, _closeArgs, _swapArgs, _withdrawPermit);
    }

    function _closeLeverage(
        address _user,
        ILeverageUsingSiloFlashloan.CloseLeverageArgs memory _closeArgs,
        IGeneralSwapModule.SwapArgs memory _swapArgs,
        ILeverageUsingSiloFlashloan.Permit memory _withdrawPermit
    ) internal {
        vm.startPrank(_user);

        // mock the swap: part of collateral token -> debt token, so we can repay flashloan
        // for this test case price is 1:1
        // we need swap bit more, so we can count for fee or slippage, here we simulate +11%
        uint256 flashAmount = silo1.maxRepay(_user);

        {
            // to deep
            uint256 amountIn = flashAmount * 111 / 100;
            swap.setSwap(_swapArgs.sellToken, amountIn, _swapArgs.buyToken, amountIn * 99 / 100);
        }

        // APPROVALS

        // Get user's leverage contract
        address userLeverageContract = leverageRouter.predictUserLeverageContract(_user);

        address shareCollateral =
            _closeArgs.collateralType == ISilo.CollateralType.Protected ? protectedShareToken : collateralShareToken;

        if (_withdrawPermit.value == 0) {
            // uint256 collateralSharesApproval = IERC20(collateralShareToken).balanceOf(_user);
            IERC20(shareCollateral).forceApprove(userLeverageContract, type(uint256).max);
        }

        {
            // to deep
            vm.expectEmit(userLeverageContract);

            emit ILeverageUsingSiloFlashloan.CloseLeverage({
                depositWithdrawn: silo0.previewRedeem(
                    IERC20(shareCollateral).balanceOf(_user), _closeArgs.collateralType
                ),
                // forge-lint: disable-next-line(divide-before-multiply)
                swapAmountOut: (flashAmount * 111 / 100) * 99 / 100,
                flashloanAmount: flashAmount,
                flashloanFee: _flashFee(ISilo(_closeArgs.flashloanTarget), flashAmount),
                borrower: _user
            });
        }

        if (_withdrawPermit.value == 0) {
            leverageRouter.closeLeveragePosition(abi.encode(_swapArgs), _closeArgs);
        } else {
            leverageRouter.closeLeveragePositionPermit(abi.encode(_swapArgs), _closeArgs, _withdrawPermit);
        }

        vm.stopPrank();

        _assertThereIsNoDebtApprovals(_user);
    }

    function _defaultOpenArgs(uint256 _depositAmount, uint256 _multiplier, address _flashloanTarget)
        internal
        view
        returns (
            ILeverageUsingSiloFlashloan.FlashArgs memory flashArgs,
            ILeverageUsingSiloFlashloan.DepositArgs memory depositArgs,
            IGeneralSwapModule.SwapArgs memory swapArgs
        )
    {
        flashArgs = ILeverageUsingSiloFlashloan.FlashArgs({
            amount: _depositAmount * _multiplier / _PRECISION,
            flashloanTarget: _flashloanTarget
        });

        depositArgs = ILeverageUsingSiloFlashloan.DepositArgs({
            amount: _depositAmount,
            collateralType: ISilo.CollateralType.Collateral,
            silo: silo0
        });

        // this data should be provided by BE API
        // NOTICE: user needs to give allowance for swap router to use tokens
        swapArgs = IGeneralSwapModule.SwapArgs({
            buyToken: address(silo0.asset()),
            sellToken: address(silo1.asset()),
            allowanceTarget: address(swap),
            exchangeProxy: address(swap),
            swapCallData: "mocked swap data"
        });
    }

    function _defaultCloseArgs(address _flashloanTarget)
        internal
        view
        returns (
            ILeverageUsingSiloFlashloan.CloseLeverageArgs memory closeArgs,
            IGeneralSwapModule.SwapArgs memory swapArgs
        )
    {
        closeArgs = ILeverageUsingSiloFlashloan.CloseLeverageArgs({
            flashloanTarget: _flashloanTarget,
            siloWithCollateral: silo0,
            collateralType: ISilo.CollateralType.Collateral
        });

        swapArgs = IGeneralSwapModule.SwapArgs({
            sellToken: address(silo0.asset()),
            buyToken: address(silo1.asset()),
            allowanceTarget: address(swap),
            exchangeProxy: address(swap),
            swapCallData: "mocked swap data"
        });
    }

    function _assertUserHasNoPosition(address _user) internal view {
        assertEq(silo0.balanceOf(_user), 0, "[_assertUserHasNoPosition] user nas NO collateral");
        assertEq(silo1.balanceOf(_user), 0, "[_assertUserHasNoPosition] user has NO debt balance");
        assertEq(silo1.maxRepay(_user), 0, "[_assertUserHasNoPosition] user has NO debt");
    }

    function _assertThereIsNoDebtApprovals(address _user) internal view {
        assertEq(
            IERC20R(debtShareToken).receiveAllowance(_user, address(siloLeverage)),
            0,
            "[NoDebtApprovals] for siloLeverage"
        );
        assertEq(IERC20R(debtShareToken).receiveAllowance(_user, address(swap)), 0, "[NoDebtApprovals] for swap");
        assertEq(IERC20R(debtShareToken).receiveAllowance(_user, address(swap)), 0, "[NoDebtApprovals] for swap");
        assertEq(IERC20R(debtShareToken).receiveAllowance(_user, address(silo0)), 0, "[NoDebtApprovals] for silo0");
        assertEq(IERC20R(debtShareToken).receiveAllowance(_user, address(silo1)), 0, "[NoDebtApprovals] for silo1");
    }

    function _assertSiloLeverageHasNoTokens() internal view {
        _assertSiloLeverageHasNoTokens(address(0));
    }

    function _assertSiloLeverageHasNoTokens(address _customToken) internal view {
        assertEq(token0.balanceOf(address(siloLeverage)), 0, "siloLeverage has no  token0");
        assertEq(token1.balanceOf(address(siloLeverage)), 0, "siloLeverage has no  token1");

        if (_customToken != address(0)) {
            assertEq(IERC20(_customToken).balanceOf(address(siloLeverage)), 0, "siloLeverage has no custom tokens");
        }
    }

    // we not always checking swap, because eg on closing, we not using whole approval
    function _assertNoApprovalsFromLeverage(bool _checkSwap) internal view {
        assertEq(
            token0.allowance(address(siloLeverage), address(silo0)), 0, "[_assertNoApprovals] token0 for silo0"
        );
        assertEq(
            token0.allowance(address(siloLeverage), address(silo1)), 0, "[_assertNoApprovals] token0 for silo1"
        );

        assertEq(
            token1.allowance(address(siloLeverage), address(silo0)), 0, "[_assertNoApprovals] token1 for silo0"
        );
        assertEq(
            token1.allowance(address(siloLeverage), address(silo1)), 0, "[_assertNoApprovals] token1 for silo1"
        );

        if (_checkSwap) {
            address swapModule = address(
                LeverageUsingSiloFlashloanWithGeneralSwap(leverageRouter.LEVERAGE_IMPLEMENTATION()).SWAP_MODULE()
            );

            assertEq(token0.allowance(swapModule, address(swap)), 0, "[_assertNoApprovals] token0 for swap router");

            assertEq(token1.allowance(swapModule, address(swap)), 0, "[_assertNoApprovals] token1 for swap router");
        }
    }

    function _generatePermit(address _token)
        internal
        view
        returns (ILeverageUsingSiloFlashloan.Permit memory permit)
    {
        uint256 nonce = IERC20Permit(_token).nonces(wallet.addr);

        permit = ILeverageUsingSiloFlashloan.Permit({
            value: 1000e18,
            deadline: block.timestamp + 1000,
            v: 0,
            r: "",
            s: ""
        });

        (permit.v, permit.r, permit.s) = _createPermit({
            _signer: wallet.addr,
            _signerPrivateKey: wallet.privateKey,
            _spender: address(siloLeverage),
            _value: permit.value,
            _nonce: nonce,
            _deadline: permit.deadline,
            _token: _token
        });
    }

    function _createPermit(
        address _signer,
        uint256 _signerPrivateKey,
        address _spender,
        uint256 _value,
        uint256 _nonce,
        uint256 _deadline,
        address _token
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        // forge-lint: disable-next-line(asm-keccak256)
        bytes32 structHash = keccak256(abi.encode(_PERMIT_TYPEHASH, _signer, _spender, _value, _nonce, _deadline));

        bytes32 domainSeparator = IERC20Permit(_token).DOMAIN_SEPARATOR();
        bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);

        (v, r, s) = vm.sign(_signerPrivateKey, digest);
    }

    function _flashFee(ISilo _flashloanTarget, uint256 _amount) internal view returns (uint256 fee) {
        address token = _flashloanTarget.asset();
        fee = _flashloanTarget.flashFee(token, _amount);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_rescueTokens_singleToken_success_fuzz
    */
    function test_rescueTokens_singleToken_success_fuzz(address _rescuer) public {
        _openLeverageExample();

        // Get user's leverage contract
        address userLeverageContract = leverageRouter.predictUserLeverageContract(wallet.addr);

        // Send some tokens to the leverage contract
        uint256 rescueAmount = 1e18;
        token0.mint(userLeverageContract, rescueAmount);

        uint256 userBalanceBefore = token0.balanceOf(wallet.addr);

        bool expectSuccess = wallet.addr == _rescuer;

        // Rescue tokens

        if (expectSuccess) {
            vm.expectEmit(true, true, false, true, userLeverageContract);
            emit RescueModule.TokensRescued(address(token0), rescueAmount);
        } else {
            vm.expectRevert(RescueModule.OnlyLeverageUser.selector);
        }

        vm.prank(_rescuer);
        siloLeverage.rescueTokens(token0);

        if (expectSuccess) {
            // Verify tokens were transferred to user
            assertEq(
                token0.balanceOf(_rescuer), userBalanceBefore + rescueAmount, "User should receive rescued tokens"
            );
            assertEq(token0.balanceOf(userLeverageContract), 0, "Leverage contract should have no tokens");
        }
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_rescueTokens_singleToken_emptyBalance_fuzz
    */
    function test_rescueTokens_singleToken_emptyBalance_fuzz(address _rescuer) public {
        _openLeverageExample();

        if (_rescuer == wallet.addr) {
            vm.expectRevert(abi.encodeWithSelector(RescueModule.EmptyBalance.selector, address(token0)));
        } else {
            vm.expectRevert(RescueModule.OnlyLeverageUser.selector);
        }

        vm.prank(_rescuer);
        siloLeverage.rescueTokens(token0);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_rescueNativeTokens_success_fuzz
    */
    function test_rescueNativeTokens_success_fuzz(address _rescuer) public {
        _openLeverageExample();

        // Get user's leverage contract
        address userLeverageContract = leverageRouter.predictUserLeverageContract(wallet.addr);

        // Use vm.deal to directly set ETH balance on the leverage contract
        uint256 rescueAmount = 1e18;
        vm.deal(userLeverageContract, rescueAmount);

        uint256 userBalanceBefore = _rescuer.balance;
        uint256 contractBalanceBefore = userLeverageContract.balance;

        assertEq(contractBalanceBefore, rescueAmount, "Contract should have native tokens");

        bool expectSuccess = wallet.addr == _rescuer;

        if (expectSuccess) {
            vm.expectEmit(true, true, false, true, userLeverageContract);
            emit RescueModule.TokensRescued(address(0), rescueAmount);
        } else {
            vm.expectRevert(RescueModule.OnlyLeverageUser.selector);
        }

        vm.prank(_rescuer);
        siloLeverage.rescueNativeTokens();

        if (expectSuccess) {
            // Verify native tokens were transferred to user
            assertEq(
                _rescuer.balance, userBalanceBefore + rescueAmount, "User should receive rescued native tokens"
            );
            assertEq(userLeverageContract.balance, 0, "Leverage contract should have no native tokens");
        }
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_rescueNativeTokens_noBalance_fuzz
    */
    function test_rescueNativeTokens_noBalance_fuzz(address _rescuer) public {
        _openLeverageExample();

        // Verify leverage contract has no native tokens
        address userLeverageContract = leverageRouter.predictUserLeverageContract(wallet.addr);
        assertEq(userLeverageContract.balance, 0, "Contract should have no native tokens");

        // Try to rescue native tokens when there's no balance (should always revert)

        if (_rescuer == wallet.addr) {
            vm.expectRevert(abi.encodeWithSelector(RescueModule.EmptyBalance.selector, address(0)));
        } else {
            vm.expectRevert(RescueModule.OnlyLeverageUser.selector);
        }

        vm.prank(_rescuer);
        siloLeverage.rescueNativeTokens();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_rescueNativeTokens_nativeTokenTransferFailed
    */
    function test_rescueNativeTokens_nativeTokenTransferFailed() public {
        _openLeverageExample();

        address user = wallet.addr;

        // Get user's leverage contract
        address userLeverageContract = leverageRouter.predictUserLeverageContract(user);

        // Use vm.deal to set native token balance on the leverage contract
        uint256 rescueAmount = 1e18;
        vm.deal(userLeverageContract, rescueAmount);

        // Deploy reverting receiver and get its bytecode
        RevertingReceiver revertingReceiver = new RevertingReceiver();
        bytes memory revertingCode = address(revertingReceiver).code;

        // Replace user's code with reverting receiver code
        vm.etch(user, revertingCode);

        // Verify contract has native tokens to rescue
        assertEq(userLeverageContract.balance, rescueAmount, "Contract should have native tokens");

        // Try to rescue native tokens - should fail because user's receive() reverts
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(RescueModule.NativeTokenTransferFailed.selector));
        siloLeverage.rescueNativeTokens();

        // Verify native tokens are still in the contract
        assertEq(userLeverageContract.balance, rescueAmount, "Native tokens should still be in leverage contract");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_leverage_setLeverageFee_pass -vv
    */
    function test_leverage_setLeverageFee_pass_fuzz(uint256 _fee) public {
        vm.assume(_fee <= leverageRouter.MAX_LEVERAGE_FEE());
        vm.assume(_fee != leverageRouter.leverageFee());

        vm.expectEmit(true, false, false, false);
        emit ILeverageRouter.LeverageFeeChanged(_fee);
        leverageRouter.setLeverageFee(_fee);
        assertEq(leverageRouter.leverageFee(), _fee, "Fee should be updated");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_leverage_setLeverageFee_fail_InvalidFee_fuzz -vv
    */
    function test_leverage_setLeverageFee_fail_InvalidFee_fuzz(uint256 _fee) public {
        vm.assume(_fee > leverageRouter.MAX_LEVERAGE_FEE());

        vm.expectRevert(abi.encodeWithSelector(ILeverageRouter.InvalidFee.selector));
        leverageRouter.setLeverageFee(_fee);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_leverage_setLeverageFee_fail_FeeDidNotChanged -vv
    */
    function test_leverage_setLeverageFee_fail_FeeDidNotChanged() public {
        uint256 newFee = leverageRouter.leverageFee();
        vm.expectRevert(abi.encodeWithSelector(ILeverageRouter.FeeDidNotChanged.selector));
        leverageRouter.setLeverageFee(newFee);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_leverage_setLeverageFee_fail_ReceiverZero -vv
    */
    function test_leverage_setLeverageFee_fail_ReceiverZero() public {
        LeverageRouter newLeverageRouter = _deployLeverage();

        uint256 newFee = 0.01e18;
        vm.expectRevert(abi.encodeWithSelector(ILeverageRouter.ReceiverZero.selector));
        newLeverageRouter.setLeverageFee(newFee);
    }
}
