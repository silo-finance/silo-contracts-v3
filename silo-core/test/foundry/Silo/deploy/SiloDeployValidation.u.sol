// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";
import {SiloDeployWithDeployerOwner} from "silo-core/deploy/silo/SiloDeployWithDeployerOwner.s.sol";
import {SiloConfigData} from "silo-core/deploy/input-readers/SiloConfigData.sol";

// FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc SiloDeployValidation
contract SiloDeployValidation is IntegrationTest {
    // the name of the hook receiver smart contract in the SiloConfigsNames.LOCAL_INVALID_HOOK
    string internal constant _INVALID_HOOK_RECEIVER = "InvalidHookReceiver";
    // names of the interest rate models smart contracts in the SiloConfigsNames.LOCAL_INVALID_IRM
    string internal constant _INVALID_IRM0 = "InterestRateModel0";
    string internal constant _INVALID_IRM1 = "InterestRateModel1";

    SiloDeployWithDeployerOwner internal _siloDeploy;

    function setUp() public {
        _siloDeploy = new SiloDeployWithDeployerOwner();
        _siloDeploy.useConfig(SiloConfigsNames.SILO_LOCAL_INVALID_CONTRACTS);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_invalidHookReceiver
    function test_invalidHookReceiver() public {
        vm.expectRevert(
            abi.encodeWithSelector(SiloConfigData.DeployedContractNotFound.selector, _INVALID_HOOK_RECEIVER)
        );

        _siloDeploy.run();
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_invalidIRM
    function test_invalidIRM() public {
        // mocking contracts that are before an interest rate model
        AddrLib.setAddress(_INVALID_HOOK_RECEIVER, makeAddr(_INVALID_HOOK_RECEIVER));

        vm.expectRevert(abi.encodeWithSelector(SiloConfigData.DeployedContractNotFound.selector, _INVALID_IRM0));

        _siloDeploy.run();

        // mock the irm0 address to verify the irm1 (as we try first to resolve the irm0)
        AddrLib.setAddress(_INVALID_IRM0, makeAddr(_INVALID_IRM0));

        vm.expectRevert(abi.encodeWithSelector(SiloConfigData.DeployedContractNotFound.selector, _INVALID_IRM1));

        _siloDeploy.run();
    }
}
