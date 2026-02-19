// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {IIncentivesClaimingLogic} from "silo-vaults/contracts/interfaces/IIncentivesClaimingLogic.sol";
import {IIncentivesClaimingLogicFactory} from "silo-vaults/contracts/interfaces/IIncentivesClaimingLogicFactory.sol";
import {IMethodsRegistry} from "silo-core/test/foundry/Silo/reentrancy/interfaces/IMethodsRegistry.sol";
import {IMethodReentrancyTest} from "silo-core/test/foundry/Silo/reentrancy/interfaces/IMethodReentrancyTest.sol";
import {SiloFixture} from "silo-core/test/foundry/_common/fixtures/SiloFixture.sol";
import {SiloConfigOverride} from "silo-core/test/foundry/_common/fixtures/SiloFixture.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";

import {SiloVaultsFactoryDeploy} from "silo-vaults/deploy/SiloVaultsFactoryDeploy.s.sol";
import {SiloVaultsFactory} from "silo-vaults/contracts/SiloVaultsFactory.sol";
import {ISiloVault} from "silo-vaults/contracts/interfaces/ISiloVault.sol";

import {Registries} from "./registries/Registries.sol";
import {MaliciousToken} from "./MaliciousToken.sol";
import {TestStateLib} from "./TestState.sol";

// FOUNDRY_PROFILE=vaults_tests forge test -vv --ffi --mc VaultReentrancyTest
contract VaultReentrancyTest is Test {

    // FOUNDRY_PROFILE=vaults_tests forge test -vv --ffi --mt test_coverage_for_vault_reentrancy
    function test_coverage_for_vault_reentrancy() public {
        Registries registries = new Registries();
        IMethodsRegistry[] memory methodRegistries = registries.list();

        bool allCovered = true;
        string memory root = vm.projectRoot();

        for (uint j = 0; j < methodRegistries.length; j++) {
            string memory abiPath = string.concat(root, methodRegistries[j].abiFile());
            // forge-lint: disable-next-line(unsafe-cheatcode)
            string memory json = vm.readFile(abiPath);

            string[] memory keys = vm.parseJsonKeys(json, ".methodIdentifiers");

            for (uint256 i = 0; i < keys.length; i++) {
                bytes4 sig = bytes4(keccak256(bytes(keys[i])));
                address method = address(methodRegistries[j].methods(sig));

                if (method == address(0)) {
                    allCovered = false;

                    emit log_string(string.concat("\nABI: ", methodRegistries[j].abiFile()));
                    emit log_string(string.concat("Method not found: ", keys[i]));
                }
            }
        }

        assertTrue(allCovered, "All methods should be covered");
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test -vvv --ffi --mt test_vault_calls_and_reentrancy
    */
    function test_vault_calls_and_reentrancy() public {
        ISiloVault vault = _deploySiloAndVaultWithOverrides();
        Registries registries = new Registries();
        IMethodsRegistry[] memory methodRegistries = registries.list();

        emit log_string("\n\nRunning reentrancy test");

        uint256 stateBeforeTest = vm.snapshotState();

        for (uint j = 0; j < methodRegistries.length; j++) {
            uint256 totalMethods = methodRegistries[j].supportedMethodsLength();

            emit log_string(string.concat("\nVerifying ",methodRegistries[j].abiFile()));

            for (uint256 i = 0; i < totalMethods; i++) {
                bytes4 methodSig = methodRegistries[j].supportedMethods(i);
                IMethodReentrancyTest method = methodRegistries[j].methods(methodSig);

                emit log_string(string.concat("\nExecute ", method.methodDescription()));

                bool entered = vault.reentrancyGuardEntered();
                assertTrue(!entered, "Reentrancy should be disabled before calling the method");

                method.callMethod();

                entered = vault.reentrancyGuardEntered();
                assertTrue(!entered, "Reentrancy should be disabled after calling the method");

                vm.revertToState(stateBeforeTest);
            }
        }
    }

    function _deploySiloAndVaultWithOverrides() internal returns (ISiloVault vault) {
        // Vault market deployments (Silo)
        SiloFixture siloFixture = new SiloFixture();

        SiloConfigOverride memory configOverride;

        configOverride.token0 = address(new MaliciousToken());
        configOverride.token1 = address(new MaliciousToken());
        configOverride.configName = SiloConfigsNames.SILO_LOCAL_GAUGE_HOOK_RECEIVER;
        ISilo market;

        (, market,,,,) = siloFixture.deploy_local(configOverride);

        SiloVaultsFactoryDeploy factoryDeploy = new SiloVaultsFactoryDeploy();
        factoryDeploy.disableDeploymentsSync();

        SiloVaultsFactory factory = factoryDeploy.run();

        address vaultInitialOwner = makeAddr("VaultOwner");

        // Vault deployment and configuration
        vault = factory.createSiloVault(
            vaultInitialOwner,
            1 days,
            address(configOverride.token0),
            "Test Vault1",
            "TV1",
            bytes32(0),
            address(vault),
            new IIncentivesClaimingLogic[](0),
            new IERC4626[](0),
            new IIncentivesClaimingLogicFactory[](0)
        );

        uint256 cap = 100e18;

        vm.prank(vaultInitialOwner);
        vault.submitCap(market, cap);

        vm.warp(block.timestamp + vault.timelock());

        vault.acceptCap(market);

        assertEq(vault.config(market).cap, cap, "_setCap");

        bool isEnabled = vault.config(market).enabled;
        assertTrue(isEnabled, "isEnabled");

        IERC4626[] memory newSupplyQueue = new IERC4626[](vault.supplyQueueLength() + 1);
        newSupplyQueue[0] = market;

        vm.prank(vaultInitialOwner);
        vault.setSupplyQueue(newSupplyQueue);

        assertEq(vault.supplyQueueLength(), 1, "supplyQueueLength");
        assertEq(vault.withdrawQueueLength(), 1, "withdrawQueueLength");

        TestStateLib.init(
            address(vault),
            vaultInitialOwner,
            address(market),
            configOverride.token0
        );
    }
}
