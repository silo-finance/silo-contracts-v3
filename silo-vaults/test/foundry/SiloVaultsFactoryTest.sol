// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {Clones} from "openzeppelin5/proxy/Clones.sol";
import {Nonces} from "openzeppelin5/utils/Nonces.sol";
import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {Create2Factory} from "common/utils/Create2Factory.sol";

import {IIncentivesClaimingLogic} from "silo-vaults/contracts/interfaces/IIncentivesClaimingLogic.sol";
import {IIncentivesClaimingLogicFactory} from "silo-vaults/contracts/interfaces/IIncentivesClaimingLogicFactory.sol";
import {SiloVault} from "../../contracts/SiloVault.sol";
import {SiloVaultsFactory} from "../../contracts/SiloVaultsFactory.sol";
import {VaultIncentivesModule} from "../../contracts/incentives/VaultIncentivesModule.sol";
import {ISiloVault} from "../../contracts/interfaces/ISiloVault.sol";
import {EventsLib} from "../../contracts/libraries/EventsLib.sol";
import {ConstantsLib} from "../../contracts/libraries/ConstantsLib.sol";

import {IntegrationTest} from "./helpers/IntegrationTest.sol";

/*
 FOUNDRY_PROFILE=vaults_tests forge test --ffi --mc SiloVaultsFactoryTest -vvv
*/
contract SiloVaultsFactoryTest is IntegrationTest, Create2Factory {
    SiloVaultsFactory factory;

    function setUp() public override {
        super.setUp();

        factory = new SiloVaultsFactory();
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testCreateSiloVaultOnce -vv
    */
    function testCreateSiloVaultOnce(
        address initialOwner,
        uint256 initialTimelock,
        string memory name,
        string memory symbol
    ) public {
        vm.assume(address(initialOwner) != address(0));
        initialTimelock = bound(initialTimelock, ConstantsLib.MIN_TIMELOCK, ConstantsLib.MAX_TIMELOCK);

        address predictedIncentivesModuleAddress = Clones.predictDeterministicAddress({
            implementation: factory.VAULT_INCENTIVES_MODULE_IMPLEMENTATION(),
            salt: _createSalt(address(this), bytes32(0)),
            deployer: address(factory)
        });

        address predictedVault = factory.predictSiloVaultAddress({
            _constructorArgs: abi.encode(
                initialOwner,
                initialTimelock,
                address(predictedIncentivesModuleAddress),
                address(loanToken),
                name,
                symbol
            ),
            _salt: _createSalt(address(this), bytes32(0)),
            _deployer: address(factory)
        });

        vm.expectEmit(true, true, true, true);
        emit EventsLib.VaultIncentiveModule(predictedVault, predictedIncentivesModuleAddress);

        ISiloVault siloVault = factory.createSiloVault(
            initialOwner,
            initialTimelock,
            address(loanToken),
            name,
            symbol,
            bytes32(0),
            address(0),
            new IIncentivesClaimingLogic[](0),
            new IERC4626[](0),
            new IIncentivesClaimingLogicFactory[](0)
        );

        assertTrue(factory.isSiloVault(address(siloVault)), "isSiloVault");

        assertEq(siloVault.owner(), initialOwner, "owner");
        assertEq(siloVault.timelock(), initialTimelock, "timelock");
        assertEq(siloVault.asset(), address(loanToken), "asset");
        assertEq(siloVault.name(), name, "name");
        assertEq(siloVault.symbol(), symbol, "symbol");
        assertTrue(address(siloVault.INCENTIVES_MODULE()) != address(0), "INCENTIVES_MODULE");
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testCreateSiloVaultTwice -vvv
    */
    function testCreateSiloVaultTwice(
        address initialOwner,
        uint256 initialTimelock,
        string memory name,
        string memory symbol
    ) public {
        vm.assume(address(initialOwner) != address(0));
        initialTimelock = bound(initialTimelock, ConstantsLib.MIN_TIMELOCK, ConstantsLib.MAX_TIMELOCK);

        ISiloVault siloVault1 = factory.createSiloVault(
            initialOwner,
            initialTimelock,
            address(loanToken),
            name,
            symbol,
            bytes32(0),
            address(0),
            new IIncentivesClaimingLogic[](0),
            new IERC4626[](0),
            new IIncentivesClaimingLogicFactory[](0)
        );

        assertTrue(factory.isSiloVault(address(siloVault1)), "isSiloVault1");

        ISiloVault siloVault2 = factory.createSiloVault(
            initialOwner,
            initialTimelock,
            address(loanToken),
            name,
            symbol,
            bytes32(0),
            address(0),
            new IIncentivesClaimingLogic[](0),
            new IERC4626[](0),
            new IIncentivesClaimingLogicFactory[](0)
        );

        assertTrue(factory.isSiloVault(address(siloVault2)), "isSiloVault2");

        assertNotEq(
            address(siloVault1.INCENTIVES_MODULE()),
            address(siloVault2.INCENTIVES_MODULE()),
            "siloVault1 != siloVault2"
        );
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testCreateSiloVaultDifferentOwner -vvv
    */
    function testCreateSiloVaultDifferentOwner() public {
        address initialOwner = makeAddr("initial owner");
        uint256 initialTimelock = 1000;
        string memory name = "test";
        string memory symbol = "test";

        initialTimelock = bound(initialTimelock, ConstantsLib.MIN_TIMELOCK, ConstantsLib.MAX_TIMELOCK);

        address devWallet = makeAddr("dev wallet");
        address otherWallet = makeAddr("other wallet");

        address implementation = factory.VAULT_INCENTIVES_MODULE_IMPLEMENTATION();

        bytes32 salt = keccak256(abi.encodePacked(devWallet, Nonces(address(factory)).nonces(devWallet), bytes32(0)));

        address predictedIncentivesModuleAddress =
            Clones.predictDeterministicAddress(implementation, salt, address(factory));

        vm.prank(otherWallet);
        ISiloVault siloVault1 = factory.createSiloVault(
            initialOwner,
            initialTimelock,
            address(loanToken),
            name,
            symbol,
            bytes32(0),
            address(0),
            new IIncentivesClaimingLogic[](0),
            new IERC4626[](0),
            new IIncentivesClaimingLogicFactory[](0)
        );

        assertTrue(factory.isSiloVault(address(siloVault1)), "isSiloVault1");

        vm.prank(devWallet);
        ISiloVault siloVault2 = factory.createSiloVault(
            initialOwner,
            initialTimelock,
            address(loanToken),
            name,
            symbol,
            bytes32(0),
            address(0),
            new IIncentivesClaimingLogic[](0),
            new IERC4626[](0),
            new IIncentivesClaimingLogicFactory[](0)
        );

        assertTrue(factory.isSiloVault(address(siloVault2)), "isSiloVault2");

        assertNotEq(
            address(siloVault1.INCENTIVES_MODULE()),
            address(siloVault2.INCENTIVES_MODULE()),
            "siloVault1 != siloVault2"
        );

        assertEq(address(siloVault2.INCENTIVES_MODULE()), predictedIncentivesModuleAddress, "unexpected address");
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt testCreateSiloVaultSameOrder -vvv
    */
    function testCreateSiloVaultSameOrder() public {
        address initialOwner = makeAddr("initial owner");
        uint256 initialTimelock = ConstantsLib.MIN_TIMELOCK;
        string memory name = "test";
        string memory symbol = "test";

        address devWallet = makeAddr("dev wallet");
        address otherWallet = makeAddr("other wallet");

        uint256 snapshot = vm.snapshotState();

        vm.prank(devWallet);
        ISiloVault siloVault = factory.createSiloVault(
            initialOwner,
            initialTimelock,
            address(loanToken),
            name,
            symbol,
            bytes32(0),
            address(0),
            new IIncentivesClaimingLogic[](0),
            new IERC4626[](0),
            new IIncentivesClaimingLogicFactory[](0)
        );

        vm.revertToState(snapshot);

        vm.prank(otherWallet);
        ISiloVault siloVault2 = factory.createSiloVault(
            initialOwner,
            initialTimelock,
            address(loanToken),
            name,
            symbol,
            bytes32(0),
            address(0),
            new IIncentivesClaimingLogic[](0),
            new IERC4626[](0),
            new IIncentivesClaimingLogicFactory[](0)
        );

        assertNotEq(address(siloVault), address(siloVault2), "siloVault == siloVault2");
    }
}
