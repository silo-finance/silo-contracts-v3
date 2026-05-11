// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin5/access/Ownable.sol";
import {IAccessControl} from "openzeppelin5/access/IAccessControl.sol";

import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";
import {SiloConfigOverride} from "../../_common/fixtures/SiloFixture.sol";
import {SiloFixture} from "../../_common/fixtures/SiloFixture.sol";
import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";
import {MintableToken} from "../../_common/MintableToken.sol";
import {SiloLens} from "silo-core/contracts/SiloLens.sol";
import {ManualLiquidationHelper} from "silo-core/contracts/utils/liquidationHelper/ManualLiquidationHelper.sol";
import {LiquidationHelper} from "silo-core/contracts/utils/liquidationHelper/LiquidationHelper.sol";
import {ILiquidationHelper} from "silo-core/contracts/interfaces/ILiquidationHelper.sol";
import {
    PermissionedLiquidationControllerFactory
} from "silo-core/contracts/incentives/functional/PermissionedLiquidationControllerFactory.sol";
import {
    IPermissionedLiquidationController
} from "silo-core/contracts/interfaces/IPermissionedLiquidationController.sol";
import {
    BaseIncentivesControllerCompatible
} from "silo-core/contracts/incentives/base/BaseIncentivesControllerCompatible.sol";
import {
    PermissionedLiquidationController
} from "silo-core/contracts/incentives/functional/PermissionedLiquidationController.sol";
import {IPartialLiquidationByDefaulting} from "silo-core/contracts/interfaces/IPartialLiquidationByDefaulting.sol";

import {ProxyAdmin} from "openzeppelin5/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "openzeppelin5/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TransparentProxy} from "silo-core/contracts/utils/TransparentProxy.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";

contract NewImplementation is PermissionedLiquidationController {
    function owner() public view override returns (address) {
        return msg.sender;
    }

    function abc() public pure returns (string memory) {
        return "abc";
    }
}

/*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc PartialLiquidationPermissionedTest
*/
contract PartialLiquidationPermissionedTest is SiloLittleHelper, IntegrationTest {
    using SafeERC20 for IERC20;

    bytes32 public constant ALLOWED_ROLE = keccak256("ALLOWED_ROLE");

    PermissionedLiquidationControllerFactory factory;

    uint256 constant DEPOSIT_AMOUNT = 1e6;
    uint256 constant MAX_AMOUNT = 1000e6;

    address depositor = address(0xdddddd);
    address borrower = address(0xBBBBBB);

    MintableToken weth;
    MintableToken usdc;
    SiloLens siloLens;

    ISilo siloWeth;
    ISilo siloUsdc;

    IPermissionedLiquidationController controllerC;
    IPermissionedLiquidationController controllerP;

    ManualLiquidationHelper manualLiquidation;
    IPartialLiquidationByDefaulting hookV2;

    function setUp() public {
        factory = new PermissionedLiquidationControllerFactory();
        weth = new MintableToken(18);
        token0 = weth;
        usdc = new MintableToken(6);
        token1 = usdc;

        SiloConfigOverride memory overrides;
        overrides.token0 = address(weth);
        overrides.token1 = address(usdc);
        vm.label(address(weth), "WETH");
        vm.label(address(usdc), "USDC");
        overrides.configName = SiloConfigsNames.SILO_LOCAL_NO_ORACLE_DEFAULTING0;

        SiloFixture siloFixture = new SiloFixture();

        address hook;
        (, silo0, silo1,,, hook) = siloFixture.deploy_local(overrides);
        partialLiquidation = IPartialLiquidation(hook);
        hookV2 = IPartialLiquidationByDefaulting(hook);

        siloLens = new SiloLens();
        manualLiquidation = new ManualLiquidationHelper(makeAddr("WETH"), payable(address(this)));

        (siloWeth, siloUsdc) = silo0.asset() == address(weth) ? (silo0, silo1) : (silo1, silo0);

        weth.setOnDemand(true);
        usdc.setOnDemand(true);

        (controllerC, controllerP) = _setupPermissionedControllers(factory);

        _fetchControllers();
        _enablePermissionsIfDisabled();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_permisioned_liquidation_enabled
    */
    function test_permisioned_liquidation_enabled() public {
        vm.expectRevert(abi.encodeWithSelector(IPermissionedLiquidationController.OnlyOwner.selector));
        controllerC.setEnabled(false);

        vm.startPrank(IPermissionedLiquidationController(address(controllerC)).owner());

        vm.expectRevert(abi.encodeWithSelector(IPermissionedLiquidationController.EnabledAlreadySet.selector));
        controllerC.setEnabled(true);

        controllerC.setEnabled(false);

        vm.stopPrank();

        assertFalse(controllerC.permisionedData().enabled, "we set false above");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_permisioned_liquidation_grantAllowedRole
    */
    function test_permisioned_liquidation_grantAllowedRole() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), bytes32(0)
            )
        );
        controllerC.grantRole(ALLOWED_ROLE, address(manualLiquidation));

        vm.prank(IPermissionedLiquidationController(address(controllerC)).owner());
        controllerC.grantRole(ALLOWED_ROLE, address(manualLiquidation));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_permisioned_liquidation_vars
    */
    function test_permisioned_liquidation_vars_collteral() public view {
        address collateralShareToken = silo0.config().getConfig(address(silo0)).collateralShareToken;

        _permisioned_liquidation_vars(address(controllerC), IShareToken(collateralShareToken));
    }

    function test_permisioned_liquidation_vars_protected() public view {
        address protectedShareToken = silo0.config().getConfig(address(silo0)).protectedShareToken;

        _permisioned_liquidation_vars(address(controllerP), IShareToken(protectedShareToken));
    }

    function _permisioned_liquidation_vars(address _collateralController, IShareToken _shareToken) internal view {
        BaseIncentivesControllerCompatible controller = BaseIncentivesControllerCompatible(_collateralController);

        assertEq(
            IPermissionedLiquidationController(_collateralController).owner(),
            Ownable(address(partialLiquidation)).owner(),
            "controller owner is a hook owner"
        );

        assertEq(controller.share_token(), address(_shareToken), "controller share token should match");
        assertEq(controller.SHARE_TOKEN(), address(_shareToken), "controller SHARE_TOKEN should match");
        assertEq(controller.NOTIFIER(), address(partialLiquidation), "controller notifier should be hook");

        assertEq(
            address(IGaugeHookReceiver(address(partialLiquidation)).configuredGauges(_shareToken)),
            address(controller),
            "controller should be configured for share token"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_permisioned_liquidation_remove
    */
    function test_permisioned_liquidation_remove() public {
        address collateralShareToken = silo0.config().getConfig(address(silo0)).collateralShareToken;
        address protectedShareToken = silo0.config().getConfig(address(silo0)).protectedShareToken;
        address debtShareToken = silo1.config().getConfig(address(silo1)).debtShareToken;

        vm.startPrank(IPermissionedLiquidationController(address(controllerC)).owner());
        IPermissionedLiquidationController debtController = IPermissionedLiquidationController(factory.create(IShareToken(debtShareToken)));
        IGaugeHookReceiver(address(partialLiquidation)).setGauge(debtController, IShareToken(debtShareToken));
        vm.stopPrank();

        _createPositionToLiquidate(ISilo.CollateralType.Protected);

        vm.startPrank(IPermissionedLiquidationController(address(controllerC)).owner());
        IGaugeHookReceiver(address(partialLiquidation)).removeGauge(IShareToken(debtShareToken));
        IGaugeHookReceiver(address(partialLiquidation)).removeGauge(IShareToken(protectedShareToken));
        IGaugeHookReceiver(address(partialLiquidation)).removeGauge(IShareToken(collateralShareToken));
        vm.stopPrank();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_permisioned_liquidation_transitionCollateral
    */
    function test_permisioned_liquidation_transitionCollateral() public {
        _depositForBorrow(10e6, depositor);

        _deposit(100e18, borrower);
        _borrow(silo1.maxBorrow(borrower), borrower);

        _withdraw(silo0.maxWithdraw(borrower), borrower);

        _grantAllowedRole();

        uint256 balance = silo0.balanceOf(borrower);
        assertGt(balance, 0, "collateral");

        vm.prank(borrower);
        silo0.transitionCollateral(balance, borrower, ISilo.CollateralType.Collateral);

        assertEq(silo0.balanceOf(borrower), 0, "transition did not worked");

        // crosscheck, liquidation should work and transition should work
        vm.warp(block.timestamp + 3 days);
        assertFalse(silo0.isSolvent(borrower), "Borrower is still solvent");
        manualLiquidation.executeLiquidation(siloUsdc, borrower);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_permisioned_liquidation_LiquidationHelper
    */
    function test_permisioned_liquidation_LiquidationHelper() public {
        _createPositionToLiquidate(ISilo.CollateralType.Protected);

        _printBorrowerLTV();

        LiquidationHelper helper = new LiquidationHelper(makeAddr("WETH"), makeAddr("ExchangeProxy"), payable(address(this)));

        uint256 maxDebtToCover = silo1.maxRepay(borrower);
        usdc.mint(address(silo1), maxDebtToCover * 2);
        usdc.mint(address(helper), maxDebtToCover * 2); // for repay flashloan

        vm.expectRevert(IPermissionedLiquidationController.LiquidationNotAllowed.selector);
        helper.executeLiquidation({
            _flashLoanFrom: siloUsdc,
            _debtAsset: address(usdc),
            _maxDebtToCover: maxDebtToCover,
            _liquidation: ILiquidationHelper.LiquidationData({
                hook: partialLiquidation,
                collateralAsset: address(weth),
                user: borrower
            }),
            _swapsInputs0x: new ILiquidationHelper.DexSwapInput[](0)
        });

        _grantAllowedRole(address(helper));

        helper.executeLiquidation({
            _flashLoanFrom: siloUsdc,
            _debtAsset: address(usdc),
            _maxDebtToCover: maxDebtToCover,
            _liquidation: ILiquidationHelper.LiquidationData({
                hook: partialLiquidation,
                collateralAsset: address(weth),
                user: borrower
            }),
            _swapsInputs0x: new ILiquidationHelper.DexSwapInput[](0)
        });

        _printBorrowerLTV();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_permisioned_liquidation_protected_hookV1
    */
    function test_permisioned_liquidation_protected_hookV1() public {
        _createPositionToLiquidate(ISilo.CollateralType.Protected);

        _printBorrowerLTV();

        vm.expectRevert(IPermissionedLiquidationController.LiquidationNotAllowed.selector);
        manualLiquidation.executeLiquidation(siloUsdc, borrower);

        _grantAllowedRole();
        manualLiquidation.executeLiquidation(siloUsdc, borrower);

        _printBorrowerLTV();
    }
    
    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_permisioned_liquidation_protected_hookV2
    */
    function test_permisioned_liquidation_protected_hookV2() public {
        _createPositionToLiquidate(ISilo.CollateralType.Protected);

        _printBorrowerLTV();

        vm.expectRevert(IPermissionedLiquidationController.LiquidationNotAllowed.selector);
        hookV2.liquidationCallByDefaulting(borrower);

        _grantAllowedRole(address(this));
        controllerP.allowMeToLiquidate(); // it will work here only because foundy is one single tx
        hookV2.liquidationCallByDefaulting(borrower);

        _printBorrowerLTV();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_permisioned_liquidation_collteral_hookV1
    */
    function test_permisioned_liquidation_collteral_hookV1() public {
        _createPositionToLiquidate(ISilo.CollateralType.Collateral);

        _printBorrowerLTV();

        vm.expectRevert(IPermissionedLiquidationController.LiquidationNotAllowed.selector);
        manualLiquidation.executeLiquidation(siloUsdc, borrower);

        _grantAllowedRole();
        manualLiquidation.executeLiquidation(siloUsdc, borrower);

        _printBorrowerLTV();
    }
    
    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_permisioned_liquidation_collteral_hookV2
    */
    function test_permisioned_liquidation_collteral_hookV2() public {
        _createPositionToLiquidate(ISilo.CollateralType.Collateral);

        _printBorrowerLTV();

        vm.expectRevert(IPermissionedLiquidationController.LiquidationNotAllowed.selector);
        hookV2.liquidationCallByDefaulting(borrower);

        _grantAllowedRole(address(this));
        controllerP.allowMeToLiquidate(); // invalid controller

        vm.expectRevert(IPermissionedLiquidationController.LiquidationNotAllowed.selector);
        hookV2.liquidationCallByDefaulting(borrower);

        controllerC.allowMeToLiquidate(); // it will work here only because foundy is one single tx
        hookV2.liquidationCallByDefaulting(borrower);

        _printBorrowerLTV();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_permisioned_liquidation_disable
    */
    function test_permisioned_liquidation_disable_hookV1() public {
        _createPositionToLiquidate(ISilo.CollateralType.Collateral);

        _printBorrowerLTV();

        vm.expectRevert(IPermissionedLiquidationController.LiquidationNotAllowed.selector);
        manualLiquidation.executeLiquidation(siloUsdc, borrower);

        vm.prank(controllerC.owner());
        controllerC.setEnabled(false);

        // when disabled, liquidation is allowed
        manualLiquidation.executeLiquidation(siloUsdc, borrower);

        _printBorrowerLTV();
    }
    
    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_permisioned_liquidation_disable_hookV2
    */
    function test_permisioned_liquidation_disable_hookV2() public {
        _createPositionToLiquidate(ISilo.CollateralType.Collateral);

        _printBorrowerLTV();

        vm.expectRevert(IPermissionedLiquidationController.LiquidationNotAllowed.selector);
        hookV2.liquidationCallByDefaulting(borrower);

        vm.prank(controllerC.owner());
        controllerC.setEnabled(false);

        // when disabled, liquidation is allowed
        hookV2.liquidationCallByDefaulting(borrower);

        _printBorrowerLTV();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_permisioned_liquidation_proxy_owner
    */
    function test_permisioned_liquidation_proxy_owner() public view {
        address proxyAdmin = TransparentProxy(payable(address(controllerC))).getAdmin();
        assertEq(Ownable(address(proxyAdmin)).owner(), Ownable(address(partialLiquidation)).owner(), "proxy admin owner should be hook owner");
    }
    
    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_permisioned_liquidation_contoller_owner
    */
    function test_permisioned_liquidation_contoller_owner() public view {
        assertEq(controllerC.owner(), Ownable(address(partialLiquidation)).owner(), "controllerC owner should be hook owner");
        assertEq(controllerP.owner(), Ownable(address(partialLiquidation)).owner(), "controllerP owner should be hook owner");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_permisioned_liquidation_upgrade
    */
    function test_permisioned_liquidation_upgrade() public {
        assertTrue(controllerC.permisionedData().enabled, "active controller is enabled");

        IPermissionedLiquidationController newImplementation = new NewImplementation();
        assertFalse(newImplementation.permisionedData().enabled, "inactive controller is disabled");

        IGaugeHookReceiver hook = IGaugeHookReceiver(address(partialLiquidation));
        IShareToken shareToken = IShareToken(address(silo0));

        address beforeUpgrade = address(hook.configuredGauges(shareToken));

        _upgrade(address(controllerC), address(newImplementation));

        address afterUpgrade = address(hook.configuredGauges(shareToken));

        assertEq(beforeUpgrade, afterUpgrade, "configured gauge addressshould not change");
        
        assertTrue(
            IPermissionedLiquidationController(afterUpgrade).permisionedData().enabled,
            "after upgrade enabled flag should stay enabled, because storage is contant"
        );

        assertEq(NewImplementation(afterUpgrade).abc(), "abc", "after upgrade we have new method abc");
    }

    function _grantAllowedRole(address _address) internal {
        vm.startPrank(IPermissionedLiquidationController(address(controllerC)).owner());
        controllerC.grantRole(ALLOWED_ROLE, _address);
        controllerP.grantRole(ALLOWED_ROLE, _address);
        vm.stopPrank();
    }

    function _grantAllowedRole() internal {
        _grantAllowedRole(address(manualLiquidation));
    }

    function _enablePermissionsIfDisabled() internal {
        if (controllerC.permisionedData().enabled) return;

        vm.startPrank(IPermissionedLiquidationController(address(controllerC)).owner());
        controllerC.setEnabled(true);
        controllerP.setEnabled(true);
        vm.stopPrank();
    }

    function _createPositionToLiquidate(ISilo.CollateralType _type) internal {
        _depositForBorrow(10e6, depositor);

        _deposit(100e18, borrower, _type);
        _borrow(silo1.maxBorrow(borrower), borrower);

        _withdraw(silo0.maxWithdraw(borrower, _type), borrower, _type);

        vm.warp(block.timestamp + 3 days);

        assertFalse(silo0.isSolvent(borrower), "Borrower is still solvent");
    }

    function _fetchControllers() internal {
        IGaugeHookReceiver hook = IGaugeHookReceiver(IShareToken(address(silo0)).hookReceiver());
        address collateralShareToken = silo0.config().getConfig(address(silo0)).collateralShareToken;
        address protectedShareToken = silo0.config().getConfig(address(silo0)).protectedShareToken;

        controllerC = IPermissionedLiquidationController(address(hook.configuredGauges(IShareToken(collateralShareToken))));
        controllerP = IPermissionedLiquidationController(address(hook.configuredGauges(IShareToken(protectedShareToken))));
    }

    function _printBorrowerLTV() internal {
        emit log_named_decimal_uint("borrower LTV", siloLens.getUserLTV(silo0, borrower), 16);
    }

    function _upgrade(address _controllerProxy, address _newImplementation) internal {
        address proxyAdmin = TransparentProxy(payable(_controllerProxy)).getAdmin();

        vm.prank(Ownable(address(proxyAdmin)).owner());
        ProxyAdmin(proxyAdmin)
            .upgradeAndCall(ITransparentUpgradeableProxy(payable(_controllerProxy)), _newImplementation, bytes(""));
    }
}
