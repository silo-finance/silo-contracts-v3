// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.7.6 <0.9.0;

import {Deployments} from "silo-foundry-utils/lib/Deployments.sol";

library SiloOraclesContracts {
    string public constant WUSD_PLUS_USD_ADAPTER = "WusdPlusUsdAdapter.sol";
    string public constant SILO_VIRTUAL_ASSET_8_DECIMALS = "SiloVirtualAsset8Decimals.sol";
    string public constant SILO_VIRTUAL_ASSET_USD = "SiloVirtualAssetUSD.sol";
    string public constant SILO_VIRTUAL_ASSET_EUR = "SiloVirtualAssetEUR.sol";
    string public constant SILO_VIRTUAL_ASSET_BTC = "SiloVirtualAssetBTC.sol";
    string public constant EGGS_TO_SONIC_ADAPTER = "EggsToSonicAdapter.sol";
    string public constant X33_TO_USD_ADAPTER = "X33ToUsdAdapter.sol";
    string public constant WSTETH_TO_STETH_ADAPTER_MAINNET = "WstEthToStEthAdapterMainnet.sol";
    string public constant VIRTUAL_TOKEN_PRICE = "VirtualTokenPrice.sol";
    string public constant REVERTING_ORACLE = "RevertingOracle.sol";
}

library SiloOraclesDeployments {
    string public constant DEPLOYMENTS_DIR = "silo-oracles";

    function get(string memory _contract, string memory _network) internal returns (address) {
        return Deployments.getAddress(DEPLOYMENTS_DIR, _network, _contract);
    }
}
