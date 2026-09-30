// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {Actions} from "silo-core/contracts/lib/Actions.sol";

/*
 FOUNDRY_PROFILE=core_test forge test --ffi --mc SafeTransferInternalTest -vv
*/
contract SafeTransferInternalTest is Test {
    address constant TOKEN = address(0xabc);
    address constant TO = address(0x999);
    uint256 constant AMOUNT = 123;

    function setUp() public {
        vm.clearMockedCalls();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_safeTransferInternal_notAtoken  -vv
    */
    function test_safeTransferInternal_notAtoken() public {
        assertTrue(
            Actions._safeTransferInternal(IERC20(TOKEN), TO, AMOUNT),
            "the only case that is not what we expect, when no mock, low-level cal did not revert"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_safeTransferInternal_return_true  -vv
    */
    function test_safeTransferInternal_return_true() public {
        vm.mockCall(TOKEN, abi.encodeWithSelector(IERC20.transfer.selector, TO, AMOUNT), abi.encode(true));
        assertTrue(Actions._safeTransferInternal(IERC20(TOKEN), TO, AMOUNT), "expect success");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_safeTransferInternal_return_false  -vv
    */
    function test_safeTransferInternal_return_false() public {
        vm.mockCall(TOKEN, abi.encodeWithSelector(IERC20.transfer.selector, TO, AMOUNT), abi.encode(false));
        assertFalse(Actions._safeTransferInternal(IERC20(TOKEN), TO, AMOUNT), "expect to fail");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_safeTransferInternal_return_uint  -vv
    */
    function test_safeTransferInternal_return_uint() public {
        bytes4 selector = bytes4(keccak256("transfer(address,uint256)"));
        vm.mockCall(TOKEN, abi.encodeWithSelector(selector, TO, AMOUNT), abi.encode(uint256(1)));
        assertTrue(
            Actions._safeTransferInternal(IERC20(TOKEN), TO, AMOUNT), "1 == true, so result will be sucessful"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_safeTransferInternal_return_nothing  -vv
    */
    function test_safeTransferInternal_return_nothing() public {
        vm.mockCall(TOKEN, abi.encodeWithSelector(IERC20.transfer.selector, TO, AMOUNT), "");
        assertTrue(Actions._safeTransferInternal(IERC20(TOKEN), TO, AMOUNT), "expect success");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_safeTransferInternal_revert_noData  -vv
    */
    function test_safeTransferInternal_revert_noData() public {
        vm.mockCallRevert(TOKEN, abi.encodeWithSelector(IERC20.transfer.selector, TO, AMOUNT), "");
        assertFalse(Actions._safeTransferInternal(IERC20(TOKEN), TO, AMOUNT), "expect to fail");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_safeTransferInternal_revert_withData  -vv
    */
    function test_safeTransferInternal_revert_withData() public {
        vm.mockCallRevert(TOKEN, abi.encodeWithSelector(IERC20.transfer.selector, TO, AMOUNT), "revert");
        assertFalse(Actions._safeTransferInternal(IERC20(TOKEN), TO, AMOUNT), "expect to fail");
    }
}
