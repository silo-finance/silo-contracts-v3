// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {KinkCommon} from "./KinkCommon.sol";
import {IDynamicKinkModel} from "../../../../contracts/interfaces/IDynamicKinkModel.sol";
import {DynamicKinkModelConfig} from "../../../../contracts/interestRateModel/kink/DynamicKinkModelConfig.sol";

contract DynamicKinkModelConfigTest is KinkCommon {
    DynamicKinkModelConfig config; 

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_config_getConfig -vv
    */
    function test_kink_config_getConfig(IDynamicKinkModel.Config memory _config) public {
        config = new DynamicKinkModelConfig(_config);

        bytes32 hashIn = _hashConfig(_config);
        bytes32 hashOut = _hashConfig(config.getConfig());

        // TODO why assert not working for hash?? assertEq(hashIn, hashOut, "hashIn != hashOut");
    }
}