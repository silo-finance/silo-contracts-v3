// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.28;

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {IIncentivesClaimingLogic} from "silo-vaults/contracts/interfaces/IIncentivesClaimingLogic.sol";
import {IIncentivesClaimingLogicFactory} from "silo-vaults/contracts/interfaces/IIncentivesClaimingLogicFactory.sol";
import {Create2Factory} from "common/utils/Create2Factory.sol";
import {ISiloVault} from "./interfaces/ISiloVault.sol";
import {ISiloVaultsFactory} from "./interfaces/ISiloVaultsFactory.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";

import {EventsLib} from "./libraries/EventsLib.sol";
import {SiloVaultFactoryActionsLib} from "./libraries/SiloVaultFactoryActionsLib.sol";

import {VaultIncentivesModule} from "./incentives/VaultIncentivesModule.sol";

/// @title SiloVaultsFactory
/// @dev Forked with gratitude from Morpho Labs.
/// @author Silo Labs
/// @custom:contact security@silo.finance
/// @notice This contract allows to create SiloVault vaults, and to index them easily.
contract SiloVaultsFactory is Create2Factory, ISiloVaultsFactory, IVersioned {
    /* STORAGE */
    address public immutable VAULT_INCENTIVES_MODULE_IMPLEMENTATION;

    /// @inheritdoc ISiloVaultsFactory
    mapping(address => bool) public isSiloVault;

    /* CONSTRUCTOR */

    constructor() {
        VAULT_INCENTIVES_MODULE_IMPLEMENTATION = address(new VaultIncentivesModule());
    }

    /* EXTERNAL */

    /// @inheritdoc ISiloVaultsFactory
    function createSiloVault(
        address _initialOwner,
        uint256 _initialTimelock,
        address _asset,
        string memory _name,
        string memory _symbol,
        bytes32 _externalSalt,
        address _notificationReceiver,
        IIncentivesClaimingLogic[] memory _claimingLogics,
        IERC4626[] memory _marketsWithIncentives,
        IIncentivesClaimingLogicFactory[] memory _trustedFactories
    ) external virtual returns (ISiloVault siloVault) {
        siloVault = SiloVaultFactoryActionsLib.createSiloVault({
            _initialOwner: _initialOwner,
            _initialTimelock: _initialTimelock,
            _asset: _asset,
            _name: _name,
            _symbol: _symbol,
            _salt: _salt(_externalSalt),
            _notificationReceiver: _notificationReceiver,
            _incentivesModuleImplementation: VAULT_INCENTIVES_MODULE_IMPLEMENTATION,
            _claimingLogics: _claimingLogics,
            _marketsWithIncentives: _marketsWithIncentives,
            _trustedFactories: _trustedFactories
        });

        isSiloVault[address(siloVault)] = true;

        emit EventsLib.CreateSiloVault(
            address(siloVault), msg.sender, _initialOwner, _initialTimelock, _asset, _name, _symbol
        );

        emit EventsLib.VaultIncentiveModule(address(siloVault), address(siloVault.INCENTIVES_MODULE()));
    }

    /// @inheritdoc ISiloVaultsFactory
    function predictSiloVaultAddress(bytes memory _constructorArgs, bytes32 _salt, address _deployer)
        external
        pure
        returns (address vaultAddress)
    {
        bytes32 initCodeHash = SiloVaultFactoryActionsLib.initCodeHash(_constructorArgs);

        vaultAddress = address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            _deployer,
            _salt,
            initCodeHash
        )))));
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure virtual returns (string memory) { // solhint-disable-line func-name-mixedcase
        return "SiloVaultsFactory 4.0.0";
    }
}
