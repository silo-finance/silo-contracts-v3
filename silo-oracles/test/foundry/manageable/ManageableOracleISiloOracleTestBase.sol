// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {ManageableOracleFactory} from "silo-oracles/contracts/manageable/ManageableOracleFactory.sol";
import {IManageableOracleFactory} from "silo-oracles/contracts/interfaces/IManageableOracleFactory.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IERC20Metadata} from "silo-oracles/test/foundry/interfaces/IERC20Metadata.sol";

import {SiloOracleMock1} from "silo-oracles/test/foundry/_mocks/silo-oracles/SiloOracleMock1.sol";
import {MintableToken} from "silo-core/test/foundry/_common/MintableToken.sol";
import {ManageableOracleFactoryDeploy} from "silo-oracles/deploy/manageable/ManageableOracleFactoryDeploy.s.sol";

abstract contract ManageableOracleISiloOracleTestBase is Test {
    address internal owner = makeAddr("Owner");
    uint32 internal constant timelock = 1 days;
    address internal baseToken;

    IManageableOracleFactory internal factory;
    SiloOracleMock1 internal oracleMock;
    ISiloOracle internal manageableOracle;

    function setUp() public virtual {
        oracleMock = new SiloOracleMock1();

        ManageableOracleFactoryDeploy factoryDeployer = new ManageableOracleFactoryDeploy();
        factoryDeployer.disableDeploymentsSync();
        factory = IManageableOracleFactory(factoryDeployer.run());
        baseToken = oracleMock.baseToken();

        vm.mockCall(address(baseToken), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));

        vm.mockCall(
            address(baseToken), abi.encodeWithSelector(IERC20Metadata.symbol.selector), abi.encode("BASE_TOKEN")
        );

        manageableOracle = _createManageableOracle();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ISiloOracle_quoteToken
    */
    function test_ISiloOracle_quoteToken() public view {
        assertEq(manageableOracle.quoteToken(), oracleMock.quoteToken(), "invalid quoteToken");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ISiloOracle_quote
    */
    function test_ISiloOracle_quote() public view {
        uint256 baseAmount = 1e18;

        assertEq(
            manageableOracle.quote(baseAmount, baseToken), oracleMock.quote(baseAmount, baseToken), "invalid quote"
        );
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ISiloOracle_beforeQuote
    */
    function test_ISiloOracle_beforeQuote() public {
        vm.expectEmit(true, true, true, true, address(oracleMock));
        emit SiloOracleMock1.BeforeQuoteSiloOracleMock1();
        manageableOracle.beforeQuote(baseToken);
    }

    /// @return manageableOracle Created oracle (via create with oracle or create with factory)
    function _createManageableOracle() internal virtual returns (ISiloOracle manageableOracle);
}
