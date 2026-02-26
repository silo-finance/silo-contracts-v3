// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";

import {IERC3156FlashBorrower} from "silo-core/contracts/interfaces/IERC3156FlashBorrower.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {Hook} from "silo-core/contracts/lib/Hook.sol";
import {ShareTokenDecimalsPowLib} from "../../_common/ShareTokenDecimalsPowLib.sol";
import {SiloFixture} from "../../_common/fixtures/SiloFixture.sol";
import {SiloConfigOverride} from "../../_common/fixtures/SiloFixture.sol";
import {MintableToken} from "../../_common/MintableToken.sol";
import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";
import {HookReceiverAllActionsWithEvents as HookMock} from "../../_mocks/HookReceiverAllActionsWithEvents.sol";

/// FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mc SiloHooksActionsTest
contract SiloHooksActionsTest is SiloLittleHelper, Test, HookMock {
    using Hook for uint256;
    using ShareTokenDecimalsPowLib for uint256;

    uint256 public constant NO_ACTIONS = 0;
    uint256 public constant SHARES_0 = 0;
    uint256 public constant ASSETS_0 = 0;
    bool public constant EXPECT_BEFORE = true;
    bool public constant EXPECT_AFTER = false;
    bytes32 public constant FLASHLOAN_CALLBACK = keccak256("ERC3156FlashBorrower.onFlashLoan");

    ISilo.CollateralType public constant COLLATERAL = ISilo.CollateralType.Collateral;
    ISilo.CollateralType public constant PROTECTED = ISilo.CollateralType.Protected;

    SiloFixture internal _siloFixture;
    ISiloConfig internal _config;
    HookMock internal _siloHookReceiver;

    address internal _depositor = makeAddr("Depositor");
    address internal _borrower = makeAddr("Borrower");

    // `HookReceiverAllActionsWithEvents` has a lot events
    // to avoid copying them all `SiloHooksActionsTest` derives from it so we can use them in the test
    constructor() HookMock(0, 0, 0, 0) {}

    // For the flash loan tests
    function onFlashLoan(address, address _token, uint256 _amount, uint256 _fee, bytes calldata)
        external
        returns (bytes32)
    {
        IERC20(_token).approve(msg.sender, _amount + _fee);
        return FLASHLOAN_CALLBACK;
    }

    /// FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testDepositFnBeforeAfterHookActions
    function testDepositFnBeforeAfterHookActions() public {
        uint256 beforeActions = Hook.depositAction(COLLATERAL);
        uint256 afterActions = Hook.depositAction(PROTECTED);

        HookMock hookReceiverMock = new HookMock(beforeActions, NO_ACTIONS, NO_ACTIONS, afterActions);
        _deploySiloWithHook(address(hookReceiverMock));

        uint256 amount = 1e18;

        _siloDepositWithHook(silo0, token0, _depositor, _depositor, amount, COLLATERAL, EXPECT_BEFORE);
        _siloDepositWithHook(silo1, token1, _depositor, _depositor, amount, PROTECTED, EXPECT_AFTER);

        // Ensure there are no other hook calls.
        _siloHookReceiver.revertAnyAction();
        // Following deposits should not trigger any hook. If it will trigger the hook will revert
        _siloDepositWithoutHook(silo0, token0, _depositor, _depositor, amount, PROTECTED);
        _siloDepositWithoutHook(silo1, token1, _depositor, _depositor, amount, COLLATERAL);
    }

    /// FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testDepositFnBeforeAndAfterHookActions
    function testDepositFnBeforeAndAfterHookActions() public {
        uint256 beforeActions = Hook.depositAction(COLLATERAL).addAction(Hook.depositAction(PROTECTED));

        uint256 afterActions = beforeActions;

        HookMock hookReceiverMock = new HookMock(beforeActions, afterActions, NO_ACTIONS, NO_ACTIONS);
        _deploySiloWithHook(address(hookReceiverMock));

        uint256 amount = 1e18;

        _siloDepositBothHooks(silo0, token0, _depositor, _depositor, amount, COLLATERAL);
        _siloDepositBothHooks(silo0, token0, _depositor, _depositor, amount, PROTECTED);

        // Ensure there are no other hook calls.
        _siloHookReceiver.revertAnyAction();
        // Following deposits should not trigger any hook. If it will trigger the hook will revert
        _siloDepositWithoutHook(silo1, token1, _depositor, _depositor, amount, COLLATERAL);
        _siloDepositWithoutHook(silo1, token1, _depositor, _depositor, amount, PROTECTED);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testDepositFnAllHookActions
    */
    function testDepositFnAllHookActions() public {
        uint256 beforeActions = Hook.depositAction(COLLATERAL).addAction(Hook.depositAction(PROTECTED));

        uint256 afterActions = beforeActions.addAction(Hook.shareTokenTransfer(Hook.COLLATERAL_TOKEN)).addAction(
            Hook.shareTokenTransfer(Hook.PROTECTED_TOKEN)
        );

        HookMock hookReceiverMock = new HookMock(beforeActions, afterActions, NO_ACTIONS, NO_ACTIONS);
        _deploySiloWithHook(address(hookReceiverMock));

        uint256 amount = 1e18;

        _siloDepositAllHooks(silo0, token0, _depositor, _depositor, amount, COLLATERAL);
        _siloDepositAllHooks(silo0, token0, _depositor, _depositor, amount, PROTECTED);

        // Ensure there are no other hook calls.
        _siloHookReceiver.revertAnyAction();
        // Following deposits should not trigger any hook. If it will trigger the hook will revert
        _siloDepositWithoutHook(silo1, token1, _depositor, _depositor, amount, COLLATERAL);
        _siloDepositWithoutHook(silo1, token1, _depositor, _depositor, amount, PROTECTED);
    }

    /// FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testWithdrawFnBeforeAfterHookActions
    function testWithdrawFnBeforeAfterHookActions() public {
        uint256 beforeActions = Hook.withdrawAction(COLLATERAL);
        uint256 afterActions = Hook.withdrawAction(PROTECTED);

        HookMock hookReceiverMock = new HookMock(beforeActions, NO_ACTIONS, NO_ACTIONS, afterActions);
        _deploySiloWithHook(address(hookReceiverMock));

        uint256 amount = 1e18;

        _siloDepositWithoutHook(silo0, token0, _depositor, _depositor, amount, COLLATERAL);
        _siloDepositWithoutHook(silo1, token1, _depositor, _depositor, amount, PROTECTED);

        _siloWithdrawWithHook(silo0, _depositor, _depositor, _depositor, amount, COLLATERAL, EXPECT_BEFORE);
        _siloWithdrawWithHook(silo1, _depositor, _depositor, _depositor, amount, PROTECTED, EXPECT_AFTER);

        // Ensure there are no other hook calls.
        _siloHookReceiver.revertAnyAction();
        // Following deposits should not trigger any hook. If it will trigger the hook will revert
        _siloDepositWithoutHook(silo0, token0, _depositor, _depositor, amount, PROTECTED);
        _siloDepositWithoutHook(silo1, token1, _depositor, _depositor, amount, COLLATERAL);
        _siloWithdrawWithoutHook(silo0, _depositor, _depositor, _depositor, amount, PROTECTED);
        _siloWithdrawWithoutHook(silo1, _depositor, _depositor, _depositor, amount, COLLATERAL);
    }

    /// FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testWithdrawFnBeforeAndAfterHookActions
    function testWithdrawFnBeforeAndAfterHookActions() public {
        uint256 beforeActions = Hook.withdrawAction(COLLATERAL).addAction(Hook.withdrawAction(PROTECTED));

        uint256 afterActions = beforeActions;

        HookMock hookReceiverMock = new HookMock(beforeActions, afterActions, NO_ACTIONS, NO_ACTIONS);
        _deploySiloWithHook(address(hookReceiverMock));

        uint256 amount = 1e18;

        _siloDepositWithoutHook(silo0, token0, _depositor, _depositor, amount, COLLATERAL);
        _siloDepositWithoutHook(silo0, token0, _depositor, _depositor, amount, PROTECTED);

        _siloWithdrawBothHooks(silo0, _depositor, _depositor, _depositor, amount, COLLATERAL);
        _siloWithdrawBothHooks(silo0, _depositor, _depositor, _depositor, amount, PROTECTED);

        // Ensure there are no other hook calls.
        _siloHookReceiver.revertAnyAction();
        // Following deposits should not trigger any hook. If it will trigger the hook will revert
        _siloDepositWithoutHook(silo1, token1, _depositor, _depositor, amount, PROTECTED);
        _siloDepositWithoutHook(silo1, token1, _depositor, _depositor, amount, COLLATERAL);
        _siloWithdrawWithoutHook(silo1, _depositor, _depositor, _depositor, amount, PROTECTED);
        _siloWithdrawWithoutHook(silo1, _depositor, _depositor, _depositor, amount, COLLATERAL);
    }

    /// FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testWithdrawFnAllHookActions
    function testWithdrawFnAllHookActions() public {
        uint256 beforeActions = Hook.withdrawAction(COLLATERAL).addAction(Hook.withdrawAction(PROTECTED));

        uint256 afterActions = beforeActions.addAction(Hook.shareTokenTransfer(Hook.COLLATERAL_TOKEN)).addAction(
            Hook.shareTokenTransfer(Hook.PROTECTED_TOKEN)
        );

        HookMock hookReceiverMock = new HookMock(beforeActions, afterActions, NO_ACTIONS, NO_ACTIONS);
        _deploySiloWithHook(address(hookReceiverMock));

        uint256 amount = 1e18;

        _siloDepositWithoutHook(silo0, token0, _depositor, _depositor, amount, COLLATERAL);
        _siloDepositWithoutHook(silo0, token0, _depositor, _depositor, amount, PROTECTED);

        _siloWithdrawAllHooks(silo0, _depositor, _depositor, _depositor, amount, COLLATERAL);
        _siloWithdrawAllHooks(silo0, _depositor, _depositor, _depositor, amount, PROTECTED);

        // Ensure there are no other hook calls.
        _siloHookReceiver.revertAnyAction();
        // Following deposits should not trigger any hook. If it will trigger the hook will revert
        _siloDepositWithoutHook(silo1, token1, _depositor, _depositor, amount, PROTECTED);
        _siloDepositWithoutHook(silo1, token1, _depositor, _depositor, amount, COLLATERAL);
        _siloWithdrawWithoutHook(silo1, _depositor, _depositor, _depositor, amount, PROTECTED);
        _siloWithdrawWithoutHook(silo1, _depositor, _depositor, _depositor, amount, COLLATERAL);
    }

    /// FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testRepayBeforeHooks
    function testRepayBeforeHooks() public {
        uint256 beforeActions = Hook.REPAY;

        HookMock hookReceiverMock = new HookMock(beforeActions, NO_ACTIONS, NO_ACTIONS, NO_ACTIONS);
        _deploySiloWithHook(address(hookReceiverMock));

        uint256 depositAmount = 100e18;
        uint256 collateralAmount = 100e18;

        _siloDepositWithoutHook(silo0, token0, _depositor, _depositor, depositAmount, COLLATERAL);
        _siloDepositWithoutHook(silo1, token1, _borrower, _borrower, collateralAmount, PROTECTED);

        uint256 borrowAmount = 1e18;

        vm.prank(_borrower);
        silo0.borrow(borrowAmount, _borrower, _borrower);

        _siloRepayBeforeHook(silo0, token0, _borrower, _borrower, borrowAmount);

        // Ensure there are no other hook calls.
        _siloHookReceiver.revertAnyAction();
        // Following operations should not trigger any hook. If it will trigger the hook will revert
        _siloWithdrawWithoutHook(silo0, _depositor, _depositor, _depositor, depositAmount, COLLATERAL);
        _siloWithdrawWithoutHook(silo1, _depositor, _borrower, _borrower, collateralAmount, PROTECTED);

        _siloDepositWithoutHook(silo0, token0, _borrower, _borrower, depositAmount, PROTECTED);
        _siloDepositWithoutHook(silo1, token1, _depositor, _depositor, collateralAmount, COLLATERAL);

        vm.prank(_borrower);
        silo1.borrow(borrowAmount, _borrower, _borrower);

        _siloRepayNoHooks(silo1, token1, _borrower, _borrower, borrowAmount);
    }

    /// FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testRepayAllHooks
    function testRepayAllHooks() public {
        uint256 beforeActions = Hook.REPAY;
        uint256 afterAction = beforeActions.addAction(Hook.shareTokenTransfer(Hook.DEBT_TOKEN));

        HookMock hookReceiverMock = new HookMock(NO_ACTIONS, NO_ACTIONS, beforeActions, afterAction);
        _deploySiloWithHook(address(hookReceiverMock));

        uint256 depositAmount = 100e18;
        uint256 collateralAmount = 100e18;

        _siloDepositWithoutHook(silo0, token0, _borrower, _borrower, depositAmount, PROTECTED);
        _siloDepositWithoutHook(silo1, token1, _depositor, _depositor, collateralAmount, COLLATERAL);

        uint256 borrowAmount = 1e18;

        vm.prank(_borrower);
        silo1.borrow(borrowAmount, _borrower, _borrower);

        _siloRepayAllHooks(silo1, token1, _borrower, _borrower, borrowAmount);
    }

    /// FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testFlashLoanAllHooks
    function testFlashLoanAllHooks() public {
        uint256 beforeActions = Hook.FLASH_LOAN;
        uint256 afterAction = beforeActions;

        HookMock hookReceiverMock = new HookMock(NO_ACTIONS, NO_ACTIONS, beforeActions, afterAction);
        _deploySiloWithHook(address(hookReceiverMock));

        uint256 depositAmount = 100e18;

        _siloDepositWithoutHook(silo1, token1, _depositor, _depositor, depositAmount, COLLATERAL);

        uint256 flashLoanAmount = 1e18;

        // mint to pay a flash loan fee
        token1.mint(address(this), 1e18);

        bytes memory data;
        uint256 flashFee = silo1.flashFee(address(token1), flashLoanAmount);

        vm.expectEmit(true, true, true, true);
        emit FlashLoanBeforeHA(address(silo1), address(this), address(token1), flashLoanAmount);

        vm.expectEmit(true, true, true, true);
        emit FlashLoanAfterHA(address(silo1), address(this), address(token1), flashLoanAmount, flashFee);

        silo1.flashLoan(IERC3156FlashBorrower(address(this)), address(token1), flashLoanAmount, data);
    }

    /// FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testTransitionCollateralToProtectedAllHooks
    function testTransitionCollateralToProtectedAllHooks() public {
        uint256 beforeActions = Hook.transitionCollateralAction(COLLATERAL);

        uint256 afterAction = beforeActions.addAction(Hook.shareTokenTransfer(Hook.COLLATERAL_TOKEN)).addAction(
            Hook.shareTokenTransfer(Hook.PROTECTED_TOKEN)
        );

        HookMock hookReceiverMock = new HookMock(beforeActions, afterAction, NO_ACTIONS, NO_ACTIONS);
        _deploySiloWithHook(address(hookReceiverMock));

        uint256 depositAmount = 100e18;

        _siloDepositWithoutHook(silo0, token0, _depositor, _depositor, depositAmount, COLLATERAL);

        _transitionCollateralAllHooks(silo0, _depositor, depositAmount, COLLATERAL);
    }

    /// FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testTransitionProtectedToCollateralAllHooks
    function testTransitionProtectedToCollateralAllHooks() public {
        uint256 beforeActions = Hook.transitionCollateralAction(PROTECTED);

        uint256 afterAction = beforeActions.addAction(Hook.shareTokenTransfer(Hook.COLLATERAL_TOKEN)).addAction(
            Hook.shareTokenTransfer(Hook.PROTECTED_TOKEN)
        );

        HookMock hookReceiverMock = new HookMock(beforeActions, afterAction, NO_ACTIONS, NO_ACTIONS);
        _deploySiloWithHook(address(hookReceiverMock));

        uint256 depositAmount = 100e18;

        _siloDepositWithoutHook(silo0, token0, _depositor, _depositor, depositAmount, PROTECTED);

        _transitionCollateralAllHooks(silo0, _depositor, depositAmount, PROTECTED);
    }

    /// FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testLiquidationReceiveSTokenFalseAllHooks
    function testLiquidationReceiveSTokenFalseAllHooks() public {
        bool receiveSToken = false;
        _liquidationTest(receiveSToken);
    }

    /// FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt testLiquidationReceiveSTokenTrueAllHooks
    function testLiquidationReceiveSTokenTrueAllHooks() public {
        bool receiveSToken = true;
        _liquidationTest(receiveSToken);
    }

    function _siloDepositWithHook(
        ISilo _silo,
        MintableToken _token,
        address _receiver,
        address _depositorAddr,
        uint256 _amount,
        ISilo.CollateralType _collateralType,
        bool _expectBefore
    ) internal {
        _token.mint(_depositorAddr, _amount);

        vm.prank(_depositorAddr);
        _token.approve(address(_silo), _amount);

        vm.prank(_depositorAddr);
        vm.expectEmit(true, true, true, true);

        if (_expectBefore) {
            emit DepositBeforeHA(address(_silo), _amount, SHARES_0, _receiver, _collateralType);
        } else {
            emit DepositAfterHA(
                address(_silo), _amount, SHARES_0, _amount, _amount.decimalsOffsetPow(), _receiver, _collateralType
            );
        }

        _silo.deposit(_amount, _depositor, _collateralType);
    }

    function _siloDepositBothHooks(
        ISilo _silo,
        MintableToken _token,
        address _receiver,
        address _depositorAddr,
        uint256 _amount,
        ISilo.CollateralType _collateralType
    ) internal {
        _token.mint(_depositorAddr, _amount);

        vm.prank(_depositorAddr);
        _token.approve(address(_silo), _amount);

        vm.prank(_depositorAddr);

        vm.expectEmit(true, true, true, true);
        emit DepositBeforeHA(address(_silo), _amount, SHARES_0, _receiver, _collateralType);
        vm.expectEmit(true, true, true, true);
        emit DepositAfterHA(
            address(_silo), _amount, SHARES_0, _amount, _amount.decimalsOffsetPow(), _receiver, _collateralType
        );

        _silo.deposit(_amount, _depositorAddr, _collateralType);
    }

    function _siloDepositAllHooks(
        ISilo _silo,
        MintableToken _token,
        address _receiver,
        address _depositorAddr,
        uint256 _amount,
        ISilo.CollateralType _collateralType
    ) internal {
        _token.mint(_depositorAddr, _amount);

        vm.prank(_depositorAddr);
        _token.approve(address(_silo), _amount);

        vm.prank(_depositorAddr);

        vm.expectEmit(true, true, true, true);
        emit DepositBeforeHA(address(_silo), _amount, SHARES_0, _receiver, _collateralType);

        vm.expectEmit(true, true, true, true);

        emit ShareTokenAfterHA(
            address(_silo),
            address(0), // because we mint tokens on deposit
            _receiver,
            _amount.decimalsOffsetPow(),
            0, // no balance for the sender
            _amount.decimalsOffsetPow(), // balance
            _amount.decimalsOffsetPow(), // total supply
            _collateralType
        );

        vm.expectEmit(true, true, true, true);
        emit DepositAfterHA(
            address(_silo), _amount, SHARES_0, _amount, _amount.decimalsOffsetPow(), _receiver, _collateralType
        );

        _silo.deposit(_amount, _receiver, _collateralType);
    }

    function _siloDepositWithoutHook(
        ISilo _silo,
        MintableToken _token,
        address _receiver,
        address _depositorAddr,
        uint256 _amount,
        ISilo.CollateralType _collateralType
    ) internal {
        _token.mint(_depositorAddr, _amount);

        vm.prank(_depositorAddr);
        _token.approve(address(_silo), _amount);

        vm.prank(_depositorAddr);
        _silo.deposit(_amount, _receiver, _collateralType);
    }

    function _siloWithdrawWithHook(
        ISilo _silo,
        address _receiver,
        address _owner,
        address _spender,
        uint256 _amount,
        ISilo.CollateralType _collateralType,
        bool _expectBefore
    ) internal {
        vm.expectEmit(true, true, true, true);

        if (_expectBefore) {
            emit WithdrawBeforeHA(address(_silo), _amount, SHARES_0, _receiver, _owner, _spender, _collateralType);
        } else {
            emit WithdrawAfterHA(
                address(_silo),
                _amount,
                SHARES_0,
                _receiver,
                _owner,
                _spender,
                _amount,
                _amount.decimalsOffsetPow(),
                _collateralType
            );
        }

        vm.prank(_spender);
        _silo.withdraw(_amount, _receiver, _owner, _collateralType);
    }

    function _siloWithdrawBothHooks(
        ISilo _silo,
        address _receiver,
        address _owner,
        address _spender,
        uint256 _amount,
        ISilo.CollateralType _collateralType
    ) internal {
        vm.expectEmit(true, true, true, true);
        emit WithdrawBeforeHA(address(_silo), _amount, SHARES_0, _receiver, _owner, _spender, _collateralType);

        vm.expectEmit(true, true, true, true);

        emit WithdrawAfterHA(
            address(_silo),
            _amount,
            SHARES_0,
            _receiver,
            _owner,
            _spender,
            _amount,
            _amount.decimalsOffsetPow(),
            _collateralType
        );

        vm.prank(_spender);
        _silo.withdraw(_amount, _receiver, _owner, _collateralType);
    }

    function _siloWithdrawAllHooks(
        ISilo _silo,
        address _receiver,
        address _owner,
        address _spender,
        uint256 _amount,
        ISilo.CollateralType _collateralType
    ) internal {
        vm.expectEmit(true, true, true, true);
        emit WithdrawBeforeHA(address(_silo), _amount, SHARES_0, _receiver, _owner, _spender, _collateralType);

        vm.expectEmit(true, true, true, true);

        emit ShareTokenAfterHA(
            address(_silo),
            _receiver,
            address(0), // because we burn tokens on withdrawal
            _amount.decimalsOffsetPow(),
            0, // no balance for the sender
            0, // no balance
            0, // no total supply
            _collateralType
        );

        vm.expectEmit(true, true, true, true);

        emit WithdrawAfterHA(
            address(_silo),
            _amount,
            SHARES_0,
            _receiver,
            _owner,
            _spender,
            _amount,
            _amount.decimalsOffsetPow(),
            _collateralType
        );

        vm.prank(_spender);
        _silo.withdraw(_amount, _receiver, _owner, _collateralType);
    }

    function _siloWithdrawWithoutHook(
        ISilo _silo,
        address _receiver,
        address _owner,
        address _spender,
        uint256 _amount,
        ISilo.CollateralType _collateralType
    ) internal {
        vm.prank(_spender);
        _silo.withdraw(_amount, _receiver, _owner, _collateralType);
    }

    function _siloBorrowBothHooks(ISilo _silo, address _borrowerAddr, address _receiver, uint256 _amount)
        internal
    {
        vm.expectEmit(true, true, true, true);
        emit BorrowBeforeHA(address(_silo), _amount, SHARES_0, _borrowerAddr, _receiver, _borrowerAddr);

        vm.expectEmit(true, true, true, true);

        emit BorrowAfterHA(
            address(_silo), _amount, SHARES_0, _borrowerAddr, _receiver, _borrowerAddr, _amount, _amount
        );

        vm.prank(_borrowerAddr);
        _silo.borrow(_amount, _borrowerAddr, _receiver);
    }

    function _siloBorrowAllHooks(ISilo _silo, address _borrowerAddr, address _receiver, uint256 _amount) internal {
        vm.expectEmit(true, true, true, true);
        emit BorrowBeforeHA(address(_silo), _amount, SHARES_0, _borrowerAddr, _receiver, _borrowerAddr);

        vm.expectEmit(true, true, true, true);

        emit DebtShareTokenAfterHA(
            address(_silo),
            address(0), // because we mint debt share tokens
            _receiver,
            _amount,
            0, // no balance for the sender
            _amount, // balance
            _amount // total supply
        );

        vm.expectEmit(true, true, true, true);

        emit BorrowAfterHA(
            address(_silo), _amount, SHARES_0, _borrowerAddr, _receiver, _borrowerAddr, _amount, _amount
        );

        vm.prank(_borrowerAddr);
        _silo.borrow(_amount, _borrowerAddr, _receiver);
    }

    function _siloRepayBeforeHook(
        ISilo _silo,
        MintableToken _token,
        address _repayer,
        address _borrowerAddr,
        uint256 _amount
    ) internal {
        vm.prank(_repayer);
        _token.approve(address(_silo), _amount);

        vm.expectEmit(true, true, true, true);
        emit RepayBeforeHA(address(_silo), _amount, SHARES_0, _borrowerAddr, _repayer);

        vm.prank(_repayer);
        _silo.repay(_amount, _borrowerAddr);
    }

    function _siloRepayAllHooks(
        ISilo _silo,
        MintableToken _token,
        address _repayer,
        address _borrowerAddr,
        uint256 _amount
    ) internal {
        vm.prank(_repayer);
        _token.approve(address(_silo), _amount);

        vm.expectEmit(true, true, true, true);
        emit RepayBeforeHA(address(_silo), _amount, SHARES_0, _borrowerAddr, _repayer);

        vm.expectEmit(true, true, true, true);

        emit DebtShareTokenAfterHA(
            address(_silo),
            _borrowerAddr,
            address(0), // because we burn debt share tokens
            _amount,
            0, // no balance for the sender
            0, // no balance
            0 // no total supply
        );

        vm.prank(_repayer);
        _silo.repay(_amount, _borrowerAddr);
    }

    function _siloRepayNoHooks(
        ISilo _silo,
        MintableToken _token,
        address _repayer,
        address _borrowerAddr,
        uint256 _amount
    ) internal {
        vm.prank(_repayer);
        _token.approve(address(_silo), _amount);

        vm.prank(_repayer);
        _silo.repay(_amount, _borrowerAddr);
    }

    function _transitionCollateralAllHooks(
        ISilo _silo,
        address _depositorAddr,
        uint256 _depositAmount,
        ISilo.CollateralType _withdrawType
    ) internal {
        uint256 sharesAmount = _depositAmount.decimalsOffsetPow();

        uint256 beforeActions = Hook.transitionCollateralAction(_withdrawType);

        uint256 afterAction = beforeActions.addAction(Hook.shareTokenTransfer(Hook.COLLATERAL_TOKEN)).addAction(
            Hook.shareTokenTransfer(Hook.PROTECTED_TOKEN)
        );

        HookMock hookReceiverMock = new HookMock(beforeActions, afterAction, NO_ACTIONS, NO_ACTIONS);
        _deploySiloWithHook(address(hookReceiverMock));

        uint256 depositAmount = 100e18;

        _siloDepositWithoutHook(silo0, token0, _depositor, _depositor, depositAmount, _withdrawType);

        vm.expectEmit(true, true, true, true);

        emit TransitionCollateralHA(address(_silo), sharesAmount, _depositorAddr, 0, _IS_BEFORE);

        vm.expectEmit(true, true, true, true);

        emit ShareTokenAfterHA(
            address(_silo),
            _depositorAddr,
            address(0), // because we burn tokens
            sharesAmount,
            0, // no balance for the sender
            0, // no balance
            0, // no total supply
            _withdrawType == COLLATERAL ? COLLATERAL : PROTECTED
        );

        vm.expectEmit(true, true, true, true);

        emit ShareTokenAfterHA(
            address(_silo),
            address(0), // because we mint tokens
            _depositorAddr,
            sharesAmount,
            0, // no balance for the sender
            sharesAmount, // balance
            sharesAmount, // total supply
            _withdrawType == COLLATERAL ? PROTECTED : COLLATERAL
        );

        vm.expectEmit(true, true, true, true);

        emit TransitionCollateralHA(address(_silo), sharesAmount, _depositorAddr, _depositAmount, _IS_AFTER);

        vm.prank(_depositorAddr);
        _silo.transitionCollateral(sharesAmount, _depositorAddr, _withdrawType);
    }

    function _liquidationTest(bool _receiveSToken) internal {
        uint256 beforeActions;

        uint256 afterAction = beforeActions.addAction(Hook.shareTokenTransfer(Hook.PROTECTED_TOKEN)) // as we have protected deposit
            .addAction(Hook.shareTokenTransfer(Hook.DEBT_TOKEN));

        HookMock hookReceiverMock = new HookMock(beforeActions, afterAction, beforeActions, afterAction);
        _deploySiloWithHook(address(hookReceiverMock));

        _depositForBorrowNotSameAsset();

        uint256 borrowAmount = 70e18;

        vm.prank(_borrower);
        silo0.borrow(borrowAmount, _borrower, _borrower);

        // liquidation
        vm.warp(block.timestamp + 70 days);

        uint256 collateralToLiquidate;
        uint256 debtToRepay;
        bool sTokenRequired;

        (collateralToLiquidate, debtToRepay, sTokenRequired) = partialLiquidation.maxLiquidation(_borrower);

        assertTrue(sTokenRequired, "sTokenRequired not required");
        assertGt(collateralToLiquidate, 0, "expect collateralToLiquidate");

        token0.mint(address(this), debtToRepay);
        token0.approve(address(partialLiquidation), debtToRepay);

        _liquidationAllHooks(_borrower, debtToRepay, borrowAmount, _receiveSToken);
    }

    function _liquidationAllHooks(
        address _borrowerAddr,
        uint256 _debtToRepay,
        uint256 _borrowAmount,
        bool _receiveSToken
    ) internal {
        uint256 expectedWithdrawCollateral = 100000000000000000000;

        if (_receiveSToken) {
            vm.expectEmit(true, true, true, true);

            emit ShareTokenAfterHA(
                address(silo1),
                _borrowerAddr,
                address(this), // because we transfer collateral
                expectedWithdrawCollateral.decimalsOffsetPow(),
                0, // no balance for the sender
                expectedWithdrawCollateral.decimalsOffsetPow(), // recipient balance
                expectedWithdrawCollateral.decimalsOffsetPow(), // total supply
                PROTECTED
            );
        }

        vm.expectEmit(true, true, true, true);

        emit DebtShareTokenAfterHA(
            address(silo0),
            _borrowerAddr,
            address(0), // because we burn debt share tokens
            _borrowAmount,
            0, // no balance for the sender
            0, // balance
            0 // total supply
        );

        if (!_receiveSToken) {
            vm.expectEmit(true, true, true, true);

            emit ShareTokenAfterHA(
                address(silo1),
                address(partialLiquidation),
                address(0), // recipient: because at the end we burn
                expectedWithdrawCollateral.decimalsOffsetPow(),
                0, // senderBalance: no balance for the sender
                0, // recipientBalance: no balance
                0, // totalSupply: no total supply
                PROTECTED
            );
        }

        partialLiquidation.liquidationCall(
            address(token1), address(token0), _borrower, _debtToRepay, _receiveSToken
        );
    }

    function _depositForBorrowNotSameAsset() internal {
        uint256 depositAmount = 100e18;
        uint256 collateralAmount = 100e18;

        _siloDepositWithoutHook(silo0, token0, _depositor, _depositor, depositAmount, COLLATERAL);
        _siloDepositWithoutHook(silo1, token1, _borrower, _borrower, collateralAmount, PROTECTED);
    }

    function _depositForBorrowSameAsset() internal {
        uint256 depositAmount = 100e18;
        uint256 collateralAmount = 100e18;

        _siloDepositWithoutHook(silo0, token0, _depositor, _depositor, depositAmount, COLLATERAL);
        _siloDepositWithoutHook(silo0, token0, _borrower, _borrower, collateralAmount, PROTECTED);
    }

    function _deploySiloWithHook(address _hookReceiver) internal {
        _siloFixture = new SiloFixture();
        SiloConfigOverride memory configOverride;

        configOverride.token0 = address(new MintableToken(18));
        configOverride.token1 = address(new MintableToken(18));
        configOverride.hookReceiverImplementation = _hookReceiver;
        configOverride.configName = SiloConfigsNames.SILO_LOCAL_DEPLOYER;

        address hook;
        (_config, silo0, silo1,,, hook) = _siloFixture.deploy_local(configOverride);
        partialLiquidation = IPartialLiquidation(hook);

        __init(MintableToken(configOverride.token0), MintableToken(configOverride.token1), silo0, silo1);

        ISiloConfig.ConfigData memory configData = _config.getConfig(address(silo0));

        _siloHookReceiver = HookMock(configData.hookReceiver);

        vm.label(address(silo0), "silo0");
        vm.label(address(silo1), "silo1");
        vm.label(address(configOverride.token0), "token0");
        vm.label(address(configOverride.token1), "token1");
    }
}
