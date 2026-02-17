// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "openzeppelin5/token/ERC20/ERC20.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IERC3156FlashBorrower} from "silo-core/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC20R} from "silo-core/contracts/interfaces/IERC20R.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {PartialLiquidation} from "silo-core/contracts/hooks/liquidation/PartialLiquidation.sol";
import {BaseHookReceiver} from "silo-core/contracts/hooks/_common/BaseHookReceiver.sol";
import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";
import {Hook} from "silo-core/contracts/lib/Hook.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";
import {MintableToken} from "../../_common/MintableToken.sol";
import {SiloConfigOverride} from "../../_common/fixtures/SiloFixture.sol";
import {SiloFixture} from "../../_common/fixtures/SiloFixture.sol";

/*
FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc HookCallsOutsideActionTest
*/
contract HookCallsOutsideActionTest is PartialLiquidation, IERC3156FlashBorrower, SiloLittleHelper, Test {
    using Hook for uint256;
    using SiloLensLib for ISilo;

    bytes32 constant FLASHLOAN_CALLBACK = keccak256("ERC3156FlashBorrower.onFlashLoan");

    uint24 public configuredHooksBefore;
    uint24 public configuredHooksAfter;

    function setUp() public {
        token0 = new MintableToken(6);
        token1 = new MintableToken(18);

        token0.setOnDemand(true);
        token1.setOnDemand(true);

        SiloConfigOverride memory overrides;
        overrides.token0 = address(token0);
        overrides.token1 = address(token1);
        overrides.hookReceiver = address(this);

        SiloFixture siloFixture = new SiloFixture();
        (siloConfig, silo0, silo1,,,) = siloFixture.deploy_local(overrides);
        partialLiquidation = this;

        _setAllHooks();

        silo0.updateHooks();
        silo1.updateHooks();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_ifHooksAreNotCalledInsideAction
    */
    function test_ifHooksAreNotCalledInsideAction() public {
        (bool entered) = siloConfig.reentrancyGuardEntered();
        assertFalse(entered, "initial state for entered");

        address depositor = makeAddr("depositor");
        address borrower = makeAddr("borrower");

        // execute all possible actions

        emit log("-- _depositForBorrow --");
        _depositForBorrow(200e18, depositor);

        emit log("-- _deposit collateral --");
        _deposit(3, depositor);

        emit log("-- _depositCollateral --");
        _deposit(200e18, borrower);

        emit log("-- _borrow --");
        _borrow(50e18, borrower);

        emit log("-- _repay --");
        _repay(1e18, borrower);

        emit log("-- _withdraw --");
        _withdraw(10e18, borrower);

        vm.warp(block.timestamp + 10);

        emit log("-- accrueInterest0 --");
        silo0.accrueInterest();
        emit log("-- accrueInterest1 --");
        silo1.accrueInterest();

        emit log("-- transitionCollateral --");
        vm.prank(borrower);
        silo0.transitionCollateral(100e18, borrower, ISilo.CollateralType.Collateral);

        emit log("-- _depositForBorrow --");
        _depositForBorrow(100e18, borrower);

        vm.prank(borrower);
        silo1.deposit(10, borrower);

        vm.prank(borrower);
        silo1.deposit(10, borrower, ISilo.CollateralType.Protected);

        (address protectedShareToken, address collateralShareToken, address debtShareToken) =
            siloConfig.getShareTokens(address(silo1));

        emit log("-- protectedShareToken.transfer --");
        vm.prank(borrower);
        IERC20(protectedShareToken).transfer(depositor, 1);

        emit log("-- collateralShareToken.transfer --");
        vm.prank(borrower);
        IERC20(collateralShareToken).transfer(depositor, 1);

        emit log("-- setReceiveApproval --");
        vm.prank(depositor);
        IERC20R(debtShareToken).setReceiveApproval(borrower, 1);

        emit log("-- debtShareToken.transfer --");
        vm.prank(borrower);
        IERC20(debtShareToken).transfer(depositor, 1);

        emit log("-- withdraw --");
        vm.prank(borrower);
        silo1.withdraw(48e18, borrower, borrower);

        emit log("-- flashLoan --");
        silo0.flashLoan(this, address(token0), silo0.maxFlashLoan(address(token0)), "");

        // liquidation
        emit log("-- liquidationCall --");

        emit log_named_decimal_uint("borrower LTV", silo0.getLtv(borrower), 16);

        uint256 maxWithdraw = silo1.maxWithdraw(borrower);
        vm.prank(borrower);
        emit log_named_uint("max withdraw", maxWithdraw);
        silo1.withdraw(maxWithdraw, borrower, borrower);

        vm.warp(block.timestamp + 20000 days);

        emit log_named_decimal_uint("borrower LTV", silo0.getLtv(borrower), 16);

        partialLiquidation.liquidationCall(
            address(token0),
            address(token1),
            borrower,
            type(uint256).max,
            false // _receiveSToken
        );

        emit log_named_decimal_uint("borrower LTV", silo0.getLtv(borrower), 16);

        silo1.withdrawFees();
    }

    function initialize(ISiloConfig _config, bytes calldata) public view override {
        assertEq(address(siloConfig), address(_config), "SiloConfig addresses should match");
    }

    function beforeAction(address, uint256 _action, bytes calldata) external override {
        emit log_named_uint("[before] action", _action);
        _printAction(_action);

        (bool entered) = siloConfig.reentrancyGuardEntered();
        emit log_named_uint("[before] reentrancyGuardEntered", entered ? 1 : 0);

        emit log("[before] action --------------------- ");
    }

    function afterAction(address, uint256 _action, bytes calldata _inputAndOutput) external override {
        emit log_named_uint("[after] action", _action);
        _printAction(_action);

        (bool entered) = siloConfig.reentrancyGuardEntered();
        emit log_named_uint("[after] reentrancyGuardEntered", entered ? 1 : 0);

        if (entered) {
            if (_action.matchAction(Hook.SHARE_TOKEN_TRANSFER)) {
                Hook.AfterTokenTransfer memory input = Hook.afterTokenTransferDecode(_inputAndOutput);

                if (input.sender == address(0) || input.recipient == address(0)) {
                    assertTrue(entered, "only when minting/burning we can be inside action");
                    _tryReenter();
                } else {
                    assertTrue(entered, "on regular transfer we are also inside action, silo is locked");
                    _tryReenter();
                }
            } else {
                assertFalse(entered, "entered: hook `after` must be called after (outside) any action");
            }
        } else {
            // we not in enter state, ok
        }

        emit log("[after] action --------------------- ");
    }

    function onFlashLoan(address, address _token, uint256 _amount, uint256, bytes calldata)
        external
        returns (bytes32)
    {
        IERC20(_token).transfer(address(msg.sender), _amount);
        return FLASHLOAN_CALLBACK;
    }

    function hookReceiverConfig(address) external view override returns (uint24 hooksBefore, uint24 hooksAfter) {
        hooksBefore = configuredHooksBefore;
        hooksAfter = configuredHooksAfter;
    }

    function _setAllHooks() internal {
        // we want all possible combinations to be ON
        configuredHooksBefore = type(uint24).max;
        configuredHooksAfter = type(uint24).max;
    }

    function _setNoHooks() internal {
        configuredHooksBefore = 0;
        configuredHooksAfter = 0;
    }

    function _printAction(uint256 _action) internal {
        if (_action.matchAction(Hook.BORROW_SAME_ASSET)) emit log("BORROW_SAME_ASSET (deprecated!)");
        if (_action.matchAction(Hook.DEPOSIT)) emit log("DEPOSIT");
        if (_action.matchAction(Hook.BORROW)) emit log("BORROW");
        if (_action.matchAction(Hook.REPAY)) emit log("REPAY");
        if (_action.matchAction(Hook.WITHDRAW)) emit log("WITHDRAW");
        if (_action.matchAction(Hook.FLASH_LOAN)) emit log("FLASH_LOAN");
        if (_action.matchAction(Hook.TRANSITION_COLLATERAL)) emit log("TRANSITION_COLLATERAL");
        if (_action.matchAction(Hook.SWITCH_COLLATERAL)) emit log("SWITCH_COLLATERAL (deprecated!)");
        if (_action.matchAction(Hook.SHARE_TOKEN_TRANSFER)) emit log("SHARE_TOKEN_TRANSFER");
        if (_action.matchAction(Hook.COLLATERAL_TOKEN)) emit log("COLLATERAL_TOKEN");
        if (_action.matchAction(Hook.PROTECTED_TOKEN)) emit log("PROTECTED_TOKEN");
        if (_action.matchAction(Hook.DEBT_TOKEN)) emit log("DEBT_TOKEN");
    }

    function _tryReenter() internal virtual {}
}
