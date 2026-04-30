// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin5/access/Ownable.sol";
import {IAccessControl} from "openzeppelin5/access/IAccessControl.sol";

import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
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
import {
    PermissionedLiquidationControllerFactory
} from "silo-core/contracts/incentives/functional/PermissionedLiquidationControllerFactory.sol";
import {
    IPermissionedLiquidationController
} from "silo-core/contracts/interfaces/IPermissionedLiquidationController.sol";
import {
    BaseIncentivesControllerCompatible
} from "silo-core/contracts/incentives/base/BaseIncentivesControllerCompatible.sol";

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

        vm.expectRevert(abi.encodeWithSelector(IPermissionedLiquidationController.OnlyOwner.selector));
        controllerC.setEnabled(false);

        vm.startPrank(IPermissionedLiquidationController(address(controllerC)).owner());

        vm.expectRevert(abi.encodeWithSelector(IPermissionedLiquidationController.EnabledAlreadySet.selector));
        controllerC.setEnabled(true);

        controllerC.setEnabled(false);

        vm.stopPrank();

        assertFalse(controllerC.enabled());
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

        vm.prank(IPermissionedLiquidationController(address(controllerC)).owner());
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
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_permisioned_liquidation_protected
    */
    function test_permisioned_liquidation_protected() public {
        _createPositionToLiquidate(ISilo.CollateralType.Protected);

        _printBorrowerLTV();

        _setPermissionedLiquidation();

        vm.expectRevert(IPermissionedLiquidationController.LiquidationNotAllowed.selector);
        manualLiquidation.executeLiquidation(siloUsdc, borrower);

        _grantAllowedRole();
        manualLiquidation.executeLiquidation(siloUsdc, borrower);

        _printBorrowerLTV();
    }

    function test_permisioned_liquidation_collteral() public {
        _createPositionToLiquidate(ISilo.CollateralType.Collateral);

        _printBorrowerLTV();

        _setPermissionedLiquidation();

        vm.expectRevert(IPermissionedLiquidationController.LiquidationNotAllowed.selector);
        manualLiquidation.executeLiquidation(siloUsdc, borrower);

        _grantAllowedRole();
        manualLiquidation.executeLiquidation(siloUsdc, borrower);

        _printBorrowerLTV();
    }

    function _grantAllowedRole() internal {
        vm.startPrank(IPermissionedLiquidationController(address(controllerC)).owner());
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

        controllerC = IPermissionedLiquidationController(factory.create(IShareToken(collateralShareToken)));
        controllerP = IPermissionedLiquidationController(factory.create(IShareToken(protectedShareToken)));

        vm.prank(Ownable(address(hook)).owner());
        hook.setGauge(controllerC, IShareToken(collateralShareToken));

        vm.prank(Ownable(address(hook)).owner());
        hook.setGauge(controllerP, IShareToken(protectedShareToken));
    }

    function _printBorrowerLTV() internal {
        emit log_named_decimal_uint("borrower LTV", siloLens.getUserLTV(silo0, borrower), 16);
    }
}
