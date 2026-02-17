// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.7.6;

import {KeyValueStorage} from "silo-foundry-utils/key-value/KeyValueStorage.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

library SiloConfigsNames {
    string public constant SILO_LOCAL_NO_ORACLE_SILO = "Silo_Local_noOracle";
    string public constant SILO_LOCAL_NO_ORACLE_DEFAULTING0 = "Silo_Local_noOracleDefaulting0";
    string public constant SILO_LOCAL_NO_ORACLE_DEFAULTING1 = "Silo_Local_noOracleDefaulting1";
    string public constant SILO_LOCAL_NO_ORACLE_NO_LTV_SILO = "Silo_Local_noOracleNoLtv";
    string public constant SILO_LOCAL_NOT_BORROWABLE = "Silo_Local_notBorrowable";
    string public constant SILO_LOCAL_BEFORE_CALL = "Silo_Local_beforeCall";
    string public constant SILO_LOCAL_DEPLOYER = "Silo_Local_deployer";
    string public constant SILO_LOCAL_HOOKS_MISCONFIGURATION = "Silo_Local_HookMisconfiguration";
    string public constant SILO_LOCAL_GAUGE_HOOK_RECEIVER = "Silo_Local_gauge_hook_receiver";
    string public constant SILO_LOCAL_INVALID_CONTRACTS = "Silo_Local_invalidContracts";

    string public constant SILO_FULL_CONFIG_TEST = "Silo_FULL_CONFIG_TEST";
    string public constant SILO_CONFIG_KINK_TEST = "Silo_CONFIG_KINK_TEST";
    string public constant SILO_ETH_USDC_UNI_V3 = "Silo_ETH-USDC_UniswapV3";
    string public constant SILO_PENDLE_REWARDS_TEST = "Silo_PENDLE_REWARDS_TEST";
}

library SiloDeployments {
    string public constant DEPLOYMENTS_FILE = "silo-core/deploy/silo/_siloDeployments.json";

    function save(string memory _chain, string memory _name, address _deployed) internal {
        KeyValueStorage.setAddress(DEPLOYMENTS_FILE, _chain, _name, _deployed);
    }

    function get(string memory _chain, string memory _name) internal returns (address) {
        address shared = AddrLib.getAddress(_name);

        if (shared != address(0)) {
            return shared;
        }

        return KeyValueStorage.getAddress(DEPLOYMENTS_FILE, _chain, _name);
    }
}
