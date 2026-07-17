// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {ILiquidationHelper} from "silo-core/contracts/interfaces/ILiquidationHelper.sol";
import {LiquidationHelper} from "silo-core/contracts/utils/liquidationHelper/LiquidationHelper.sol";
import {
    PermissionedLiquidationControllerFactory
} from "silo-core/contracts/incentives/functional/PermissionedLiquidationControllerFactory.sol";
import {
    IPermissionedLiquidationController
} from "silo-core/contracts/interfaces/IPermissionedLiquidationController.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";
import {SiloConfigOverride} from "../../_common/fixtures/SiloFixture.sol";
import {SiloFixture} from "../../_common/fixtures/SiloFixture.sol";
import {MintableToken} from "../../_common/MintableToken.sol";

/*
FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc LiquidationHelperWhitelistAttackTest
*/
contract LiquidationHelperWhitelistAttackTest is SiloLittleHelper, Test {
    using SafeERC20 for IERC20;

    bytes32 public constant ALLOWED_ROLE = keccak256("ALLOWED_ROLE");

    address internal depositor = address(0xdddddd);
    address internal borrower = address(0xBBBBBB);

    MintableToken internal weth;
    MintableToken internal usdc;

    ISilo internal siloUsdc;
    IPermissionedLiquidationController internal controllerC;
    IPermissionedLiquidationController internal controllerP;

    LiquidationHelper internal helper;

    function setUp() public {
        PermissionedLiquidationControllerFactory factory = new PermissionedLiquidationControllerFactory();
        weth = new MintableToken(18);
        token0 = weth;
        usdc = new MintableToken(6);
        token1 = usdc;

        SiloConfigOverride memory overrides;
        overrides.token0 = address(weth);
        overrides.token1 = address(usdc);
        overrides.configName = SiloConfigsNames.SILO_LOCAL_NO_ORACLE_DEFAULTING0;

        SiloFixture siloFixture = new SiloFixture();
        address hook;
        (, silo0, silo1,,, hook) = siloFixture.deploy_local(overrides);
        partialLiquidation = IPartialLiquidation(hook);

        siloUsdc = silo0.asset() == address(usdc) ? silo0 : silo1;

        weth.setOnDemand(true);
        usdc.setOnDemand(true);

        (controllerC, controllerP) = _setupPermissionedControllers(factory);
        _fetchControllers();
        _enablePermissions();

        helper = new LiquidationHelper({
            _nativeToken: makeAddr("WETH"),
            _exchangeProxy: makeAddr("ExchangeProxy"),
            _tokensReceiver: payable(address(this))
        });

        helper.grantRole({role: helper.ALLOWED_ROLE(), account: address(this)});
        _grantControllerAllowedRole(address(helper));
        // needed to clear the transient flag after helper liquidation and for the control example
        _grantControllerAllowedRole(address(this));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_partialExecuteLiquidation_secondCallRequiresPermission
    */
    function test_partialExecuteLiquidation_secondCallRequiresPermission() public {
        _createInsolventPosition();

        (, uint256 debtToRepay,) = partialLiquidation.maxLiquidation(borrower);
        assertGt(debtToRepay, 20, "need room for partial + 10 wei second cover");

        uint256 partialDebt = debtToRepay / 2;
        uint256 secondDebt = 10;
        uint256 maxDebtToCover = silo1.maxRepay(borrower);

        // same liquidity pattern as PartialLiquidationPermissionedTest (flashloan + repay buffer)
        usdc.mint(address(silo1), maxDebtToCover * 2);
        usdc.mint(address(helper), maxDebtToCover * 2);
        usdc.mint(address(this), secondDebt);

        _executePartialLiquidation(partialDebt);

        assertFalse(silo0.isSolvent(borrower), "borrower must stay insolvent after partial liquidation");

        // Helper raised the controller flag for this tx; clear it so the next call is permission-gated.
        controllerC.disallowLiquidation();
        controllerP.disallowLiquidation();

        IERC20(address(usdc)).forceApprove({spender: address(partialLiquidation), value: secondDebt});

        // Control: without permission the second liquidation reverts.
        vm.expectRevert(IPermissionedLiquidationController.LiquidationNotAllowed.selector);
        _liquidationCall(secondDebt);

        // Control: with permission the same liquidation call succeeds.
        controllerC.allowMeToLiquidate();
        controllerP.allowMeToLiquidate();
        _liquidationCall(secondDebt);
    }

    function _executePartialLiquidation(uint256 _partialDebt) internal {
        ILiquidationHelper.DexSwapInput[] memory swaps;

        helper.executeLiquidation({
            _flashLoanFrom: siloUsdc,
            _debtAsset: address(usdc),
            _maxDebtToCover: _partialDebt,
            _liquidation: ILiquidationHelper.LiquidationData({
                hook: partialLiquidation,
                collateralAsset: address(weth),
                user: borrower
            }),
            _swapsInputs0x: swaps
        });
    }

    function _liquidationCall(uint256 _debtToCover) internal {
        partialLiquidation.liquidationCall({
            _collateralAsset: address(weth),
            _debtAsset: address(usdc),
            _user: borrower,
            _maxDebtToCover: _debtToCover,
            _receiveSToken: false
        });
    }

    function _createInsolventPosition() internal {
        _depositForBorrow(10e6, depositor);
        _deposit(100e18, borrower, ISilo.CollateralType.Protected);
        _borrow(silo1.maxBorrow(borrower), borrower);
        _withdraw(silo0.maxWithdraw(borrower, ISilo.CollateralType.Protected), borrower, ISilo.CollateralType.Protected);

        vm.warp(block.timestamp + 3 days);
        assertFalse(silo0.isSolvent(borrower), "borrower must be insolvent");
    }

    function _grantControllerAllowedRole(address _account) internal {
        vm.startPrank(IPermissionedLiquidationController(address(controllerC)).owner());
        controllerC.grantRole({role: ALLOWED_ROLE, account: _account});
        controllerP.grantRole({role: ALLOWED_ROLE, account: _account});
        vm.stopPrank();
    }

    function _enablePermissions() internal {
        if (controllerC.permisionedData().enabled) return;

        vm.startPrank(IPermissionedLiquidationController(address(controllerC)).owner());
        controllerC.setEnabled(true);
        controllerP.setEnabled(true);
        vm.stopPrank();
    }

    function _fetchControllers() internal {
        address collateralShareToken = silo0.config().getConfig(address(silo0)).collateralShareToken;
        address protectedShareToken = silo0.config().getConfig(address(silo0)).protectedShareToken;
        IGaugeHookReceiver hook = IGaugeHookReceiver(IShareToken(address(silo0)).hookReceiver());

        controllerC = IPermissionedLiquidationController(address(hook.configuredGauges(IShareToken(collateralShareToken))));
        controllerP = IPermissionedLiquidationController(address(hook.configuredGauges(IShareToken(protectedShareToken))));
    }
}
