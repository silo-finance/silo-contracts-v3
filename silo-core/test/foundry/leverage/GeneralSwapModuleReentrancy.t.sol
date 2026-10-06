// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IGeneralSwapModule} from "silo-core/contracts/interfaces/IGeneralSwapModule.sol";
import {GeneralSwapModule} from "silo-core/contracts/leverage/modules/GeneralSwapModule.sol";
import {TransientReentrancy} from "silo-core/contracts/hooks/_common/TransientReentrancy.sol";

import {MintableToken} from "../_common/MintableToken.sol";

/// @dev Exchange proxy that calls `fillQuote` again from inside the swap.
contract ReenteringExchange {
    GeneralSwapModule internal immutable MODULE;

    constructor(GeneralSwapModule _module) {
        MODULE = _module;
    }

    fallback() external {
        IGeneralSwapModule.SwapArgs memory args = IGeneralSwapModule.SwapArgs({
            exchangeProxy: address(0),
            sellToken: address(0),
            buyToken: address(0),
            allowanceTarget: address(0),
            swapCallData: ""
        });

        MODULE.fillQuote({_swapArgs: args, _maxApprovalAmount: 0});
    }
}

/*
    FOUNDRY_PROFILE=core_test forge test --ffi --mc GeneralSwapModuleReentrancy -vv
*/
contract GeneralSwapModuleReentrancy is Test {
    function test_fillQuote_reentrancy_reverts() public {
        GeneralSwapModule module = new GeneralSwapModule();
        MintableToken sellToken = new MintableToken(18);
        ReenteringExchange exchange = new ReenteringExchange(module);

        sellToken.mint({_owner: address(module), _amount: 1});

        IGeneralSwapModule.SwapArgs memory args = IGeneralSwapModule.SwapArgs({
            exchangeProxy: address(exchange),
            sellToken: address(sellToken),
            buyToken: address(sellToken),
            allowanceTarget: address(exchange),
            swapCallData: ""
        });

        vm.expectRevert(TransientReentrancy.ReentrancyGuardReentrantCall.selector);
        module.fillQuote({_swapArgs: args, _maxApprovalAmount: 1});
    }
}
