// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SiloStdLib} from "silo-core/contracts/lib/SiloStdLib.sol";

import {TokenMock} from "../../_mocks/TokenMock.sol";

// forge test -vv --mc GetSharesAndTotalSupplyTest
contract GetSharesAndTotalSupplyTest is Test {
    TokenMock immutable SHARE_TOKEN;

    constructor() {
        SHARE_TOKEN = new TokenMock(address(0));
    }

    /*
    forge test -vv --mt test_getSharesAndTotalSupply_zeros
    */
    function test_getSharesAndTotalSupply_zeros() public {
        address shareToken = SHARE_TOKEN.ADDRESS();
        address owner;

        SHARE_TOKEN.balanceOfAndTotalSupplyMock(owner, 0, 0);
        (uint256 shares, uint256 totalSupply) = SiloStdLib.getSharesAndTotalSupply(shareToken, owner, 0);
        assertEq(shares, 0, "zero shares");
        assertEq(totalSupply, 0, "zero totalSupply");
    }

    /*
    forge test -vv --mt test_getSharesAndTotalSupply_pass
    */
    function test_getSharesAndTotalSupply_pass() public {
        address shareToken = SHARE_TOKEN.ADDRESS();
        address owner = address(2);

        SHARE_TOKEN.balanceOfAndTotalSupplyMock(owner, 111, 222);
        (uint256 shares, uint256 totalSupply) = SiloStdLib.getSharesAndTotalSupply(shareToken, owner, 0);
        assertEq(shares, 111, "shares");
        assertEq(totalSupply, 222, "totalSupply");
    }

    /*
    forge test -vv --mt test_getSharesAndTotalSupply_pass
    */
    function test_getSharesAndTotalSupply_balanceCached() public {
        address shareToken = SHARE_TOKEN.ADDRESS();
        address owner = address(2);
        uint256 balance = 987;

        SHARE_TOKEN.totalSupplyMock(222);
        (uint256 shares, uint256 totalSupply) = SiloStdLib.getSharesAndTotalSupply(shareToken, owner, balance);
        assertEq(shares, balance, "shares");
        assertEq(totalSupply, 222, "totalSupply");
    }
}
