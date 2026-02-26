// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IDynamicKinkModelFactory} from "silo-core/contracts/interfaces/IDynamicKinkModelFactory.sol";
import {IInterestRateModelV2Factory} from "silo-core/contracts/interfaces/IInterestRateModelV2Factory.sol";
import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";
import {ISiloIncentivesControllerFactory} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesControllerFactory.sol";
import {SiloDeployer} from "silo-core/contracts/SiloDeployer.sol";

contract SiloDeployerMock is SiloDeployer {
    constructor() SiloDeployer(
        IInterestRateModelV2Factory(address(0)),
        IDynamicKinkModelFactory(address(0)),
        ISiloFactory(address(0)),
        ISiloIncentivesControllerFactory(address(0)),
        address(0),
        address(0), address(0)) {}

    function isDefaultingHook(address _hook) external view returns (bool isDefaulting) {
        return _isDefaultingHook(_hook);
    }
}

/*
FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc SiloDeployerTest
*/
contract SiloDeployerTest is Test {
    SiloDeployerMock siloDeployer = new SiloDeployerMock();

    function test_siloDeployer_isDefaultingHook_zero() public view {
        assertFalse(siloDeployer.isDefaultingHook(address(0)), "false for zero address");
    }
    
    function test_siloDeployer_isDefaultingHook_notContract() public view {
        assertFalse(siloDeployer.isDefaultingHook(address(1)), "false for not contract address");
    }
    
    function test_siloDeployer_isDefaultingHook_notDefaulting() public view {
        assertFalse(siloDeployer.isDefaultingHook(address(this)), "false for non-defaulting hook");
    }
    
    function test_siloDeployer_isDefaultingHook_neverRevert(address _hook) public view {
        siloDeployer.isDefaultingHook(_hook);
    }
}
