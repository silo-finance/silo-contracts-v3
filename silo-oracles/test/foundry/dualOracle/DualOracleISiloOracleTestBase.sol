// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IERC20Metadata} from "silo-oracles/test/foundry/interfaces/IERC20Metadata.sol";
import {SiloOracleMock1} from "silo-oracles/test/foundry/_mocks/silo-oracles/SiloOracleMock1.sol";
import {DualOracleFactory} from "silo-oracles/contracts/dualOracle/DualOracleFactory.sol";

abstract contract DualOracleISiloOracleTestBase is Test {
    address internal owner = makeAddr("Owner");
    uint32 internal constant TIMELOCK = 1 days;
    address internal baseToken;

    DualOracleFactory internal factory;
    SiloOracleMock1 internal oracleMock;
    ISiloOracle internal dualOracle;

    function setUp() public virtual {
        oracleMock = new SiloOracleMock1();
        factory = new DualOracleFactory();
        baseToken = oracleMock.baseToken();

        vm.mockCall(baseToken, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));

        dualOracle = _createDualOracle();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ISiloOracle_quoteToken
    */
    function test_ISiloOracle_quoteToken() public view {
        assertEq(dualOracle.quoteToken(), oracleMock.quoteToken(), "quoteToken mismatch");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ISiloOracle_quote_normalMode
    */
    function test_ISiloOracle_quote_normalMode() public view {
        uint256 baseAmount = 1e18;
        assertEq(
            dualOracle.quote(baseAmount, baseToken),
            oracleMock.quote(baseAmount, baseToken),
            "quote should delegate to primary oracle in normal mode"
        );
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ISiloOracle_beforeQuote_forwardsToPrimary
    */
    function test_ISiloOracle_beforeQuote_forwardsToPrimary() public {
        vm.expectEmit(true, false, false, false, address(oracleMock));
        emit SiloOracleMock1.BeforeQuoteSiloOracleMock1();
        dualOracle.beforeQuote(baseToken);
    }

    function _createDualOracle() internal virtual returns (ISiloOracle);
}
