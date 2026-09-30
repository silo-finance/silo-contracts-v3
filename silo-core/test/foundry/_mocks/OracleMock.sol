// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";

contract OracleMock is Test {
    address public immutable ADDRESS;

    constructor(address _address) {
        ADDRESS = _address == address(0) ? makeAddr("OracleMock") : _address;
    }

    // quote signature 0x13b0be33
    function quoteMock(uint256 _baseAmount, address _baseToken, uint256 _quoteAmount) external {
        bytes memory data = abi.encodeWithSelector(ISiloOracle.quote.selector, _baseAmount, _baseToken);
        vm.mockCall(ADDRESS, data, abi.encode(_quoteAmount));
        vm.expectCall(ADDRESS, data);
    }

    function quoteTokenMock(address _quoteToken) external {
        bytes memory data = abi.encodeWithSelector(ISiloOracle.quoteToken.selector);
        vm.mockCall(ADDRESS, data, abi.encode(_quoteToken));
        vm.expectCall(ADDRESS, data);
    }

    function expectQuote(uint256 _baseAmount, address _baseToken) external {
        bytes memory data = abi.encodeWithSelector(ISiloOracle.quote.selector, _baseAmount, _baseToken);
        vm.expectCall(ADDRESS, data);
    }

    // ISiloOracle.beforeQuote.selector: 0xf9fa619a
    function beforeQuoteMock(address _baseToken) external {
        bytes memory data = abi.encodeWithSelector(ISiloOracle.beforeQuote.selector, _baseToken);
        vm.mockCall(ADDRESS, data, abi.encode());
        vm.expectCall(ADDRESS, data);
    }

    function expectBeforeQuote(address _baseToken) external {
        bytes memory data = abi.encodeWithSelector(ISiloOracle.beforeQuote.selector, _baseToken);
        vm.expectCall(ADDRESS, data);
    }
}
