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

import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {
    IBackwardsCompatibleGaugeLike
} from "silo-core/contracts/incentives/interfaces/IBackwardsCompatibleGaugeLike.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";
import {SiloConfigOverride} from "../../_common/fixtures/SiloFixture.sol";
import {SiloFixture} from "../../_common/fixtures/SiloFixture.sol";
import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";
import {MintableToken} from "../../_common/MintableToken.sol";
import {SiloLens} from "silo-core/contracts/SiloLens.sol";
import {ManualLiquidationHelper} from "silo-core/contracts/utils/liquidationHelper/ManualLiquidationHelper.sol";
import {
    PermissionedLiquidationIncentiveControllerFactory
} from "silo-core/contracts/incentives/functional/PermissionedLiquidationIncentiveControllerFactory.sol";
import {
    IPermissionedLiquidationIncentiveController
} from "silo-core/contracts/interfaces/IPermissionedLiquidationIncentiveController.sol";
import {
    PermissionedLiquidationIncentiveController
} from "silo-core/contracts/incentives/functional/PermissionedLiquidationIncentiveController.sol";

import {ProxyAdmin} from "openzeppelin5/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "openzeppelin5/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TransparentProxy} from "silo-core/contracts/utils/TransparentProxy.sol";

contract NewImplementation is PermissionedLiquidationIncentiveController {
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

    error OnlyOwner();

    bytes32 public constant ALLOWED_ROLE = keccak256("ALLOWED_ROLE");

    PermissionedLiquidationIncentiveControllerFactory factory;

    uint256 constant DEPOSIT_AMOUNT = 1e6;
    uint256 constant MAX_AMOUNT = 1000e6;

    address depositor = address(0xdddddd);
    address borrower = address(0xBBBBBB);

    MintableToken weth;
    MintableToken usdc;
    SiloLens siloLens;

    ISilo siloWeth;
    ISilo siloUsdc;

    IPermissionedLiquidationIncentiveController controllerC;
    IPermissionedLiquidationIncentiveController controllerP;

    ManualLiquidationHelper manualLiquidation;

    function setUp() public {
        factory = new PermissionedLiquidationIncentiveControllerFactory();
        weth = new MintableToken(18);
        token0 = weth;
        usdc = new MintableToken(6);
        token1 = usdc;

        SiloConfigOverride memory overrides;
        overrides.token0 = address(weth);
        overrides.token1 = address(usdc);
        vm.label(address(weth), "WETH");
        vm.label(address(usdc), "USDC");

        SiloFixture siloFixture = new SiloFixture();

        address hook;
        (, silo0, silo1,,, hook) = siloFixture.deploy_local(overrides);
        partialLiquidation = IPartialLiquidation(hook);

        siloLens = new SiloLens();
        manualLiquidation = new ManualLiquidationHelper(makeAddr("WETH"), payable(address(this)));

        (siloWeth, siloUsdc) = silo0.asset() == address(weth) ? (silo0, silo1) : (silo1, silo0);

        weth.setOnDemand(true);
        usdc.setOnDemand(true);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_permisioned_liquidation_enabled
    */
    function test_permisioned_liquidation_enabled() public {
        _setPermissionedLiquidation();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        controllerC.setEnabled(false);

        vm.startPrank(Ownable(address(controllerC)).owner());

        vm.expectRevert(abi.encodeWithSelector(IPermissionedLiquidationIncentiveController.EnabledAlreadySet.selector));
        controllerC.setEnabled(true);

        controllerC.setEnabled(false);

        vm.stopPrank();

        assertFalse(controllerC.permisionedData().enabled);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_permisioned_liquidation_grantAllowedRole
    */
    function test_permisioned_liquidation_grantAllowedRole() public {
        _setPermissionedLiquidation();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), bytes32(0)
            )
        );
        controllerC.grantRole(ALLOWED_ROLE, address(manualLiquidation));

        vm.prank(Ownable(address(controllerC)).owner());
        controllerC.grantRole(ALLOWED_ROLE, address(manualLiquidation));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_permisioned_liquidation_vars
    */
    function test_permisioned_liquidation_vars_collteral() public {
        _setPermissionedLiquidation();

        address collateralShareToken = silo0.config().getConfig(address(silo0)).collateralShareToken;

        _permisioned_liquidation_vars(address(controllerC), IShareToken(collateralShareToken));
    }

    function test_permisioned_liquidation_vars_protected() public {
        _setPermissionedLiquidation();

        address protectedShareToken = silo0.config().getConfig(address(silo0)).protectedShareToken;

        _permisioned_liquidation_vars(address(controllerP), IShareToken(protectedShareToken));
    }

    function _permisioned_liquidation_vars(address _collateralController, IShareToken _shareToken) internal view {
        ISiloIncentivesController controller = ISiloIncentivesController(_collateralController);

        assertEq(
            Ownable(address(_collateralController)).owner(),
            Ownable(address(partialLiquidation)).owner(),
            "controller owner is a hook owner"
        );

        assertEq(
            IBackwardsCompatibleGaugeLike(_collateralController).share_token(),
            address(_shareToken),
            "controller share token should match"
        );
        assertEq(controller.SHARE_TOKEN(), address(_shareToken), "controller SHARE_TOKEN should match");
        assertEq(controller.NOTIFIER(), address(partialLiquidation), "controller notifier should be hook");

        assertEq(
            address(IGaugeHookReceiver(address(partialLiquidation)).configuredGauges(_shareToken)),
            address(controller),
            "controller should be configured for share token"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_permisioned_liquidation_protected
    */
    function test_permisioned_liquidation_protected() public {
        _createPositionToLiquidate(ISilo.CollateralType.Protected);

        _printBorrowerLTV();

        _setPermissionedLiquidation();

        vm.expectRevert(IPermissionedLiquidationIncentiveController.LiquidationNotAllowed.selector);
        manualLiquidation.executeLiquidation(siloUsdc, borrower);

        _grantAllowedRole();
        manualLiquidation.executeLiquidation(siloUsdc, borrower);

        _printBorrowerLTV();
    }

    function test_permisioned_liquidation_collteral() public {
        _createPositionToLiquidate(ISilo.CollateralType.Collateral);

        _printBorrowerLTV();

        _setPermissionedLiquidation();

        vm.expectRevert(IPermissionedLiquidationIncentiveController.LiquidationNotAllowed.selector);
        manualLiquidation.executeLiquidation(siloUsdc, borrower);

        _grantAllowedRole();
        manualLiquidation.executeLiquidation(siloUsdc, borrower);

        _printBorrowerLTV();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_permisioned_liquidation_disable
    */
    function test_permisioned_liquidation_disable() public {
        _createPositionToLiquidate(ISilo.CollateralType.Collateral);

        _printBorrowerLTV();

        _setPermissionedLiquidation();

        vm.expectRevert(IPermissionedLiquidationIncentiveController.LiquidationNotAllowed.selector);
        manualLiquidation.executeLiquidation(siloUsdc, borrower);

        vm.prank(Ownable(address(controllerC)).owner());
        controllerC.setEnabled(false);

        // when disabled, liquidation is allowed
        manualLiquidation.executeLiquidation(siloUsdc, borrower);

        _printBorrowerLTV();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_permisioned_liquidation_upgrade
    */
    function test_permisioned_liquidation_upgrade() public {
        _setPermissionedLiquidation();

        assertTrue(controllerC.permisionedData().enabled, "active controller is enabled");

        IPermissionedLiquidationIncentiveController newImplementation = new NewImplementation();
        assertFalse(newImplementation.permisionedData().enabled, "inactive controller is disabled");

        vm.startPrank(Ownable(address(controllerC)).owner());

        IGaugeHookReceiver hook = IGaugeHookReceiver(address(partialLiquidation));
        IShareToken shareToken = IShareToken(address(silo0));

        address beforeUpgrade = address(hook.configuredGauges(shareToken));

        _upgrade(address(controllerC), address(newImplementation));

        address afterUpgrade = address(hook.configuredGauges(shareToken));
        assertEq(beforeUpgrade, afterUpgrade, "configured gauge addressshould not change");
        assertTrue(
            IPermissionedLiquidationIncentiveController(afterUpgrade).permisionedData().enabled,
            "after upgrade enabled flag should stay enabled, because storage is contant"
        );

        assertEq(NewImplementation(afterUpgrade).abc(), "abc", "after upgrade we have new method abc");
    }

    function _grantAllowedRole() internal {
        vm.startPrank(Ownable(address(controllerC)).owner());
        controllerC.grantRole(ALLOWED_ROLE, address(manualLiquidation));
        controllerP.grantRole(ALLOWED_ROLE, address(manualLiquidation));
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

    function _setPermissionedLiquidation() internal {
        IGaugeHookReceiver hook = IGaugeHookReceiver(IShareToken(address(silo0)).hookReceiver());
        address collateralShareToken = silo0.config().getConfig(address(silo0)).collateralShareToken;
        address protectedShareToken = silo0.config().getConfig(address(silo0)).protectedShareToken;

        controllerC = IPermissionedLiquidationIncentiveController(factory.create(IShareToken(collateralShareToken)));
        controllerP = IPermissionedLiquidationIncentiveController(factory.create(IShareToken(protectedShareToken)));

        address hookOwner = Ownable(address(hook)).owner();

        vm.startPrank(hookOwner);
        hook.setGauge(controllerC, IShareToken(collateralShareToken));
        hook.setGauge(controllerP, IShareToken(protectedShareToken));
        controllerC.setEnabled(true);
        controllerP.setEnabled(true);
        vm.stopPrank();
    }

    function _printBorrowerLTV() internal {
        emit log_named_decimal_uint("borrower LTV", siloLens.getUserLTV(silo0, borrower), 16);
    }

    function _upgrade(address _controllerProxy, address _newImplementation) internal {
        address proxyAdmin = TransparentProxy(payable(_controllerProxy)).getAdmin();

        ProxyAdmin(proxyAdmin)
            .upgradeAndCall(ITransparentUpgradeableProxy(payable(_controllerProxy)), _newImplementation, bytes(""));
    }
}
