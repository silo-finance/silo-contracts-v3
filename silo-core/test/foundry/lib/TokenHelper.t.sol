// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

import {TokenHelper} from "silo-core/contracts/lib/TokenHelper.sol";

contract MockTokenNoMetadata {}

contract MockTokenWithMetadata {
    string public symbol;
    uint8 public decimals;

    constructor(string memory _symbol, uint8 _decimals) {
        symbol = _symbol;
        decimals = _decimals;
    }
}

// forge test -vv --mc TokenHelperTest
contract TokenHelperTest is Test {
    string public constant SYMBOL = "SILO_TOKEN";
    bytes32 public constant SYMBOL_BYTES_LEFT = 0x53494c4f5f544f4b454e00000000000000000000000000000000000000000000;
    bytes32 public constant SYMBOL_BYTES_RIGHT = 0x0000000000000000000000000000000000000000000053494c4f5f544f4b454e;

    function setUp() public {}

    function test_NoContract() public {
        address empty = address(1);

        vm.expectRevert(TokenHelper.TokenIsNotAContract.selector);
        TokenHelper.assertAndGetDecimals(empty);

        vm.expectRevert(TokenHelper.TokenIsNotAContract.selector);
        TokenHelper.symbol(empty);
    }

    function test_NoMetadata() public {
        address token = address(new MockTokenNoMetadata());

        uint256 decimals = TokenHelper.assertAndGetDecimals(token);
        assertEq(decimals, 0);

        string memory symbol = TokenHelper.symbol(token);
        assertEq(symbol, "?");
    }

    function test_Metadata() public {
        string memory symbol = "ABC";
        uint8 decimals = 123;
        address token = address(new MockTokenWithMetadata(symbol, decimals));

        assertEq(TokenHelper.symbol(token), symbol);
        assertEq(TokenHelper.assertAndGetDecimals(token), decimals);
    }

    function test_removeZeros() public pure {
        assertEq(TokenHelper.removeZeros(""), "");
        assertEq(TokenHelper.removeZeros("0"), "0");
        assertEq(TokenHelper.removeZeros(abi.encode(0x20)), " ");
        assertEq(TokenHelper.removeZeros(abi.encode(0x20414243000000)), " ABC");
    }

    /**
     * forge test -vv --mt test_TokenHelper_symbolBytes32
     */
    function test_TokenHelper_symbolBytes32() public {
        address token = makeAddr("Token");

        vm.mockCall(token, abi.encodeWithSelector(IERC20Metadata.symbol.selector), abi.encode(SYMBOL_BYTES_LEFT));

        assertEq(TokenHelper.symbol(token), SYMBOL);

        vm.mockCall(token, abi.encodeWithSelector(IERC20Metadata.symbol.selector), abi.encode(SYMBOL_BYTES_RIGHT));

        assertEq(TokenHelper.symbol(token), SYMBOL);
    }
}
