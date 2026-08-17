// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {KinkCommonTest} from "./KinkCommon.t.sol";
import {IDynamicKinkModel} from "../../../../contracts/interfaces/IDynamicKinkModel.sol";
import {DynamicKinkModelConfig} from "../../../../contracts/interestRateModel/kink/DynamicKinkModelConfig.sol";

contract DynamicKinkModelConfigTest is KinkCommonTest {
    DynamicKinkModelConfig config; 

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_config_getConfig -vv
    */
    function test_kink_config_getConfig(
        IDynamicKinkModel.Config memory _config,
        IDynamicKinkModel.ImmutableConfig memory _immutableConfig
    ) public {
        config = new DynamicKinkModelConfig(_config, _immutableConfig);

        bytes32 hashIn = _hashConfig(_config);
        (IDynamicKinkModel.Config memory cfg, IDynamicKinkModel.ImmutableConfig memory imm) = config.getConfig();
        bytes32 hashCfgOut = _hashConfig(cfg);
        bytes32 hashImmOut = _hashImmutableConfig(imm);

        assertEq(hashIn, hashCfgOut, "hashIn != hashCfgOut");
        assertEq(hashIn, hashImmOut, "hashIn != hashImmOut");
    }
}