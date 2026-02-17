// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IHookReceiver} from "silo-core/contracts/interfaces/IHookReceiver.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {Hook} from "silo-core/contracts/lib/Hook.sol";
import {SiloFixture} from "../../_common/fixtures/SiloFixture.sol";
import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";
import {MintableToken} from "../../_common/MintableToken.sol";
import {SiloConfigOverride} from "../../_common/fixtures/SiloFixture.sol";

contract HookReceiver is IHookReceiver, Test {
    bool imIn;

    uint24 hooksBefore;
    uint24 hooksAfter;
    ISiloConfig siloConfig;

    function initialize(ISiloConfig _siloConfig, bytes calldata) external {
        siloConfig = _siloConfig;
    }

    /// @notice state of Silo before action, can be also without interest, if you need them, call silo.accrueInterest()
    function beforeAction(address, /* _silo */ uint256 _action, bytes calldata _input) external {
        // return to not create infinite loop
        if (imIn) return;

        (address silo0,) = siloConfig.getSilos();

        imIn = true;
        address receiver;

        if (Hook.matchAction(Hook.BORROW, _action)) {
            Hook.BeforeBorrowInput memory input = Hook.beforeBorrowDecode(_input);
            receiver = input.receiver;

            // create debt in two silos
            vm.prank(receiver);
            ISilo(silo0).borrow(1, receiver, receiver);
        } else {
            revert("should not happen");
        }

        imIn = false;
    }

    function afterAction(address, uint256, bytes calldata) external pure {
        revert("not in use");
    }

    /// @notice return hooksBefore and hooksAfter configuration
    function hookReceiverConfig(address) external view returns (uint24, uint24) {
        return (hooksBefore, hooksAfter);
    }

    function setBefore(uint24 _before) external {
        hooksBefore = _before;
    }
}

/*
FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mc SiloBeforeHooksTest
*/
contract SiloBeforeHooksTest is SiloLittleHelper, Test {
    address immutable BORROWER;
    address immutable DEPOSITOR;

    ISiloConfig internal _siloConfig;
    HookReceiver internal _hookReceiver;
    address internal _hookReceiverAddr;

    constructor() {
        BORROWER = makeAddr("BORROWER");
        DEPOSITOR = makeAddr("DEPOSITOR");
    }

    function setUp() public {
        _hookReceiver = new HookReceiver();
        _hookReceiverAddr = address(_hookReceiver);

        SiloFixture siloFixture = new SiloFixture();
        SiloConfigOverride memory configOverride;

        token0 = new MintableToken(18);
        token1 = new MintableToken(18);
        token0.setOnDemand(true);
        token1.setOnDemand(true);

        configOverride.token0 = address(token0);
        configOverride.token1 = address(token1);

        configOverride.hookReceiver = _hookReceiverAddr;

        (_siloConfig, silo0, silo1,,,) = siloFixture.deploy_local(configOverride);

        _deposit(1e18, BORROWER);
        _depositForBorrow(1e18, BORROWER);
        _depositForBorrow(10, DEPOSITOR);

        _hookReceiver.initialize(_siloConfig, "");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_borrow_beforeHook_createDebt
    */
    function test_borrow_beforeHook_createDebt() public {
        _hookReceiver.setBefore(uint24(Hook.BORROW));
        silo1.updateHooks();

        vm.expectRevert(ISilo.BorrowNotPossible.selector);
        vm.prank(BORROWER);
        silo1.borrow(8, BORROWER, BORROWER);

        _hookReceiver.setBefore(uint24(0));
        silo1.updateHooks();

        vm.prank(BORROWER);
        silo1.borrow(8, BORROWER, BORROWER);
    }
}
