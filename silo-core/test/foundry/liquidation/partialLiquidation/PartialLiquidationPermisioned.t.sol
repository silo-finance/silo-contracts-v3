// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin5/access/Ownable.sol";

import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {Whitelist} from "silo-core/contracts/hooks/_common/Whitelist.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";
import {SiloConfigOverride} from "../../_common/fixtures/SiloFixture.sol";
import {SiloFixture} from "../../_common/fixtures/SiloFixture.sol";
import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";
import {MintableToken} from "../../_common/MintableToken.sol";
import {SiloLens} from "silo-core/contracts/SiloLens.sol";
import {ManualLiquidationHelper} from "silo-core/contracts/utils/liquidationHelper/ManualLiquidationHelper.sol";
import {
    PermissionedLiquidationController
} from "silo-core/contracts/incentives/functional/PermissionedLiquidationController.sol";
import {
    IPermissionedLiquidationController
} from "silo-core/contracts/interfaces/IPermissionedLiquidationController.sol";

contract PartialLiquidationPermissionedTest is SiloLittleHelper, IntegrationTest {
    using SafeERC20 for IERC20;

    bytes32 public constant ALLOWED_ROLE = keccak256("ALLOWED_ROLE");

    uint256 constant DEPOSIT_AMOUNT = 1e6;
    uint256 constant MAX_AMOUNT = 1000e6;

    address depositor = address(0xdddddd);
    address borrower = address(0xBBBBBB);

    MintableToken weth;
    MintableToken usdc;
    SiloLens siloLens;

    ISilo siloWeth;
    ISilo siloUsdc;

    ISiloIncentivesController controllerC;
    ISiloIncentivesController controllerP;

    ManualLiquidationHelper manualLiquidation;

    function setUp() public {
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

        (, silo0, silo1,,,) = siloFixture.deploy_local(overrides);

        siloLens = new SiloLens();
        manualLiquidation = new ManualLiquidationHelper(makeAddr("WETH"), payable(address(this)));

        (siloWeth, siloUsdc) = silo0.asset() == address(weth) ? (silo0, silo1) : (silo1, silo0);

        weth.setOnDemand(true);
        usdc.setOnDemand(true);
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
        Whitelist(address(controllerC)).grantRole(ALLOWED_ROLE, address(manualLiquidation));
        Whitelist(address(controllerP)).grantRole(ALLOWED_ROLE, address(manualLiquidation));
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

        controllerC = new PermissionedLiquidationController(address(this), address(hook), collateralShareToken);
        controllerP = new PermissionedLiquidationController(address(this), address(hook), protectedShareToken);

        vm.prank(Ownable(address(hook)).owner());
        hook.setGauge(controllerC, IShareToken(collateralShareToken));
        vm.prank(Ownable(address(hook)).owner());
        hook.setGauge(controllerP, IShareToken(protectedShareToken));
    }

    function _printBorrowerLTV() internal {
        emit log_named_decimal_uint("borrower LTV", siloLens.getUserLTV(silo0, borrower), 16);
    }
}
