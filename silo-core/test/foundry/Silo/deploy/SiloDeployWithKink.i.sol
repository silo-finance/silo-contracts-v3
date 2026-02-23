// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IDynamicKinkModelFactory} from "silo-core/contracts/interfaces/IDynamicKinkModelFactory.sol";
import {SiloCoreDeployments, SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";

import {SiloDeployTest} from "./SiloDeploy.i.sol";

/*
AGGREGATOR=1INCH FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc SiloDeployWithKinkTest
*/
contract SiloDeployWithKinkTest is SiloDeployTest {
    /*
    AGGREGATOR=1INCH FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_siloDeployment_checkKinkIRM
    */
    function test_siloDeployment_checkKinkIRM() public {
        (address silo0, address silo1) = _siloConfig.getSilos();
        ISiloConfig.ConfigData memory config0 = _siloConfig.getConfig(silo0);
        ISiloConfig.ConfigData memory config1 = _siloConfig.getConfig(silo1);

        string memory chainAlias = ChainsLib.chainAlias();

        IDynamicKinkModelFactory factory = IDynamicKinkModelFactory(
            SiloCoreDeployments.get(SiloCoreContracts.DYNAMIC_KINK_MODEL_FACTORY, chainAlias)
        );

        assertTrue(factory.createdByFactory(config0.interestRateModel), "expect value KinkIRM model in silo0");
        assertTrue(factory.createdByFactory(config1.interestRateModel), "expect value KinkIRM model in silo1");
    }

    function test_oracles_deploy() public view override {
        // we not using oracle for Kink test
    }

    function _useConfig() internal pure override returns (string memory) {
        return SiloConfigsNames.SILO_CONFIG_KINK_TEST;
    }
}
