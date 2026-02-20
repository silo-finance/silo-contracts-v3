// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {IERC4626, IERC20Metadata} from "openzeppelin5/interfaces/IERC4626.sol";

import {IdleVaultsFactoryDeploy} from "silo-vaults/deploy/IdleVaultsFactoryDeploy.s.sol";

import {IdleVault} from "../../contracts/IdleVault.sol";
import {IdleVaultsFactory} from "../../contracts/IdleVaultsFactory.sol";

import {IntegrationTest} from "./helpers/IntegrationTest.sol";

/*
 FOUNDRY_PROFILE=vaults_tests forge test --ffi --mc IdleVaultTest -vvv
*/
contract IdleVaultTest is IntegrationTest {
    address attacker = makeAddr("attacker");
    uint256 donationAmount;

    /*
        FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_idleVault_minDepositWithOffset -vvv
    */
    function test_idleVault_minDepositWithOffset() public {
        address v = address(vault);

        vm.startPrank(v);
        idleMarket.deposit(1, v);

        idleMarket.deposit(1, v);

        assertEq(idleMarket.redeem(idleMarket.balanceOf(v), v, v), 2, "expect no loss on tiny deposit");
        vm.stopPrank();
    }

    /*
        FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_idleVault_offset -vv
    */
    function test_idleVault_offset() public {
        vm.prank(address(vault));
        uint256 shares = idleMarket.deposit(1, address(vault));
        assertEq(shares, 1e6, "expect correct offset");
    }

    /*
        FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_idleVaultDeploy_sameOrder -vvv
    */
    function test_idleVaultDeploy_sameOrder() public {
        IdleVaultsFactoryDeploy deploy = new IdleVaultsFactoryDeploy();
        deploy.disableDeploymentsSync();
        IdleVaultsFactory factory = deploy.run();

        address idleMarket = makeAddr("idle market");

        vm.mockCall(address(idleMarket), abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(idleMarket));

        vm.mockCall(
            address(idleMarket), abi.encodeWithSelector(IERC20Metadata.name.selector), abi.encode("Idle Market")
        );

        vm.mockCall(
            address(idleMarket), abi.encodeWithSelector(IERC20Metadata.symbol.selector), abi.encode("IM")
        );

        address devWallet = makeAddr("dev wallet");
        address otherWallet = makeAddr("other wallet");

        uint256 snapshot = vm.snapshotState();

        vm.prank(devWallet);
        IdleVault idleVault1 = factory.createIdleVault(IERC4626(idleMarket), bytes32(0));

        vm.revertToState(snapshot);

        vm.prank(otherWallet);
        IdleVault idleVault2 = factory.createIdleVault(IERC4626(idleMarket), bytes32(0));

        assertNotEq(address(idleVault1), address(idleVault2), "idleVault1 == idleVault2");
    }
}
