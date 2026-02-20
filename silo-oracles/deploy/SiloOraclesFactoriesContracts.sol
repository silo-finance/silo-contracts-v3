// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.7.6 <0.9.0;

import {Deployments} from "silo-foundry-utils/lib/Deployments.sol";

library SiloOraclesFactoriesContracts {
    string public constant UNISWAP_V3_ORACLE_FACTORY = "UniswapV3OracleFactory.sol";
    string public constant CHAINLINK_V3_ORACLE_FACTORY = "ChainlinkV3OracleFactory.sol";
    string public constant DIA_ORACLE_FACTORY = "DIAOracleFactory.sol";
    string public constant ORACLE_FORWARDER_FACTORY = "OracleForwarderFactory.sol";
    string public constant ERC4626_ORACLE_FACTORY = "ERC4626OracleFactory.sol";
    string public constant ERC4626_ORACLE_HARDCODE_QUOTE_FACTORY = "ERC4626OracleHardcodeQuoteFactory.sol";
    string public constant ERC4626_ORACLE_UNDERLYING_FACTORY = "ERC4626OracleWithUnderlyingFactory.sol";
    string public constant PYTH_AGGREGATOR_FACTORY = "PythAggregatorFactory.sol";
    string public constant ORACLE_SCALER_FACTORY = "OracleScalerFactory.sol";
    string public constant PENDLE_PT_ORACLE_FACTORY = "PendlePTOracleFactory.sol";
    string public constant PENDLE_PT_TO_ASSET_ORACLE_FACTORY = "PendlePTToAssetOracleFactory.sol";
    string public constant PENDLE_LPT_TO_SY_ORACLE_FACTORY = "PendleLPTToSyOracleFactory.sol";
    string public constant PENDLE_LPT_TO_ASSET_ORACLE_FACTORY = "PendleLPTToAssetOracleFactory.sol";
    string public constant PENDLE_WRAPPER_LPT_TO_ASSET_ORACLE_FACTORY = "PendleWrapperLPTToAssetOracleFactory.sol";
    string public constant PENDLE_WRAPPER_LPT_TO_SY_ORACLE_FACTORY = "PendleWrapperLPTToSyOracleFactory.sol";
    string public constant PT_LINEAR_ORACLE_FACTORY = "PTLinearOracleFactory.sol";
    string public constant MANAGEABLE_ORACLE_FACTORY = "ManageableOracleFactory.sol";
}

library SiloOraclesFactoriesDeployments {
    string public constant DEPLOYMENTS_DIR = "silo-oracles";

    function get(string memory _contract, string memory _network) internal returns (address) {
        return Deployments.getAddress(DEPLOYMENTS_DIR, _network, _contract);
    }
}
