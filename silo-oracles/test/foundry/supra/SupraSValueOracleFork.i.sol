// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {MintableToken} from "silo-core/test/foundry/_common/MintableToken.sol";

import {ISupraOraclePull_V2} from "silo-oracles/contracts/interfaces/ISupraOraclePull_V2.sol";
import {ISupraSValueOracle} from "silo-oracles/contracts/interfaces/ISupraSValueOracle.sol";
import {SupraSValueOracleFactory} from "silo-oracles/contracts/supra/SupraSValueOracleFactory.sol";

/*
    FOUNDRY_PROFILE=oracles forge test --match-contract SupraSValueOracleForkIntegrationTest --ffi -vv
*/
contract SupraSValueOracleForkIntegrationTest is Test {
    uint256 internal constant DEFAULT_XDC_USDT_PAIR_ID = 150;

    ISupraOraclePull_V2 internal constant SUPRA_XDC_ORACLE_PULL =
        ISupraOraclePull_V2(0x2FA6DbFe4291136Cf272E1A3294362b6651e8517);

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_XDC"), 100943727);
    }

    function test_fork_xdc_deploy_and_read_price() public {
        SupraSValueOracleFactory factory = new SupraSValueOracleFactory(SUPRA_XDC_ORACLE_PULL);

        MintableToken baseToken = new MintableToken(6);
        MintableToken quoteToken = new MintableToken(6);

        ISupraSValueOracle.DeploymentConfig memory cfg = ISupraSValueOracle.DeploymentConfig({
            baseToken: IERC20Metadata(address(baseToken)),
            quoteToken: IERC20Metadata(address(quoteToken)),
            pairId: DEFAULT_XDC_USDT_PAIR_ID
        });

        ISupraSValueOracle oracle = factory.create({_config: cfg, _externalSalt: bytes32(0)});

        uint256 expectedPrice = 0.030647e18;
        uint256 rawPrice = oracle.readPrice();
        assertEq(rawPrice, expectedPrice, "Supra raw price");

        uint256 quote = ISiloOracle(address(oracle)).quote({_baseAmount: 1e6, _baseToken: address(baseToken)});
        assertEq(quote, expectedPrice, "Oracle quote");

        quote = ISiloOracle(address(oracle)).quote({_baseAmount: 1e6 * 2, _baseToken: address(baseToken)});
        assertEq(quote, expectedPrice * 2, "Oracle quote *2");
    }
}
