// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import "../../../constants/Arbitrum.sol";

import {TokensGenerator} from "../_common/TokensGenerator.sol";
import {IDIAOracle} from "../../../contracts/interfaces/IDIAOracle.sol";
import {DIAOracleConfig} from "../../../contracts/dia/DIAOracleConfig.sol";
import "../_common/DIAConfigDefault.sol";

/*
    FOUNDRY_PROFILE=oracles forge test -vv --match-contract DIAOracleConfigTest
*/
contract DIAOracleConfigTest is DIAConfigDefault {
    uint256 constant TEST_BLOCK = 124937740;

    DIAOracleConfig public immutable CFG;

    constructor() TokensGenerator(BlockChain.ARBITRUM) {
        initFork(TEST_BLOCK);

        CFG = new DIAOracleConfig(_defaultDIAConfig(10 ** (18 + 8 - 18), 0));
    }

    function test_DIAOracleConfig_getQuoteData() public view {
        IDIAOracle.DIAConfig memory config = CFG.getConfig();

        assertEq(address(config.diaOracle), address(DIA_ORACLE_V2), "diaOracle");
        assertEq(config.baseToken, address(tokens["RDPX"]), "baseToken");
        assertEq(config.quoteToken, address(tokens["USDT"]), "quoteToken");
        assertEq(uint256(config.heartbeat), uint256(1 days), "heartbeat");
        assertEq(uint256(config.normalizationDivider), 100000000, "normalizationDivider");
        assertEq(uint256(config.normalizationMultiplier), 0, "normalizationMultiplier");
        assertFalse(config.convertToQuote, "quoteIsEth");
    }
}
