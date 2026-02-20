// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

import {Forking} from "../_common/Forking.sol";
import {IForking} from "../interfaces/IForking.sol";
import {sAVAXOracle} from "../../../contracts/custom/sAVAX/sAVAXOracle.sol";

/*
    FOUNDRY_PROFILE=oracles forge test -vv --match-contract sAVAXOracleTest
*/
contract sAVAXOracleTest is Forking {
    uint256 constant TEST_BLOCK = 76868990;

    sAVAXOracle public oracle;

    constructor() Forking(IForking.BlockChain.AVALANCHE) {}

    function setUp() public {
        initFork(TEST_BLOCK);
        oracle = new sAVAXOracle();
    }

    function test_sAVAXOracle_quote() public view {
        address baseTokenAddr = oracle.baseToken();
        uint256 amount = 10 ** IERC20Metadata(baseTokenAddr).decimals();
        uint256 quoteAmount = oracle.quote(amount, baseTokenAddr);

        assertEq(baseTokenAddr, oracle.IAU_SAVAX(), "baseToken");
        assertEq(quoteAmount, 1.248338953052103790e18, "quote");
    }

    function test_sAVAXOracle_VERSION() public view {
        assertEq(oracle.VERSION(), "sAVAXOracle 4.0.0", "VERSION");
    }
}
