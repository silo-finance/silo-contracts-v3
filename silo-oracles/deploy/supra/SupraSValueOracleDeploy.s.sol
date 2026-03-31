// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

// solhint-disable no-console
import {console2} from "forge-std/console2.sol";

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {PriceFormatter} from "silo-core/deploy/lib/PriceFormatter.sol";

import {CommonDeploy} from "../CommonDeploy.sol";
import {OraclesDeployments} from "../OraclesDeployments.sol";
import {SiloOraclesFactoriesContracts} from "../SiloOraclesFactoriesContracts.sol";
import {ISupraSValueOracle} from "silo-oracles/contracts/interfaces/ISupraSValueOracle.sol";
import {ISupraSValueOracleFactory} from "silo-oracles/contracts/interfaces/ISupraSValueOracleFactory.sol";

/*
Deploys one `SupraSValueOracle` via deployed `SupraSValueOracleFactory`.

Required env:
  PAIR_ID         - Supra pair id
  BASE_TOKEN      - priced token
  QUOTE_TOKEN     - quote token

Optional env:
  EXTERNAL_SALT                   - CREATE2 salt (bytes32)
*/
contract SupraSValueOracleDeploy is CommonDeploy {
    function run() public returns (ISupraSValueOracle oracle) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        ISupraSValueOracle.DeploymentConfig memory cfg = ISupraSValueOracle.DeploymentConfig({
            baseToken: IERC20Metadata(vm.envAddress("BASE_TOKEN")),
            quoteToken: IERC20Metadata(vm.envAddress("QUOTE_TOKEN")),
            pairId: vm.envUint("PAIR_ID")
        });

        bytes32 externalSalt = vm.envOr("EXTERNAL_SALT", bytes32(0));
        address factoryAddr = getDeployedAddress(SiloOraclesFactoriesContracts.SUPRA_SVALUE_ORACLE_FACTORY);
        ISupraSValueOracleFactory factory = ISupraSValueOracleFactory(factoryAddr);

        vm.startBroadcast(deployerPrivateKey);
        oracle = factory.create({_config: cfg, _externalSalt: externalSalt});
        vm.stopBroadcast();

        string memory oracleName = string.concat("SUPRA_SVALUE_ORACLE_", vm.toString(cfg.pairId));
        OraclesDeployments.save(getChainAlias(), oracleName, address(oracle));

        console2.log("SupraSValueOracle:", address(oracle));
        console2.log("Oracle name (deployments key):", oracleName);

        _qa({_oracle: oracle, _baseToken: address(cfg.baseToken)});
    }

    function _qa(ISupraSValueOracle _oracle, address _baseToken) internal view {
        uint256 oneBase = 10 ** IERC20Metadata(_baseToken).decimals();
        uint256 quote = _printQuote({
            _oracle: ISiloOracle(address(_oracle)),
            _baseToken: _baseToken,
            _baseAmount: oneBase
        });

        string memory baseSymbol = IERC20Metadata(_baseToken).symbol();
        string memory quoteSymbol = IERC20Metadata(ISiloOracle(address(_oracle)).quoteToken()).symbol();

        console2.log("\nQA ------------------------------:", address(_oracle));
        console2.log(string.concat("  Quote (1 ", baseSymbol, "):"));
        console2.log("   ", PriceFormatter.formatPriceInE18(quote), quoteSymbol);
    }
}
