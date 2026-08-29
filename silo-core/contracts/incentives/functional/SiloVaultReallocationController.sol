// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {SiloIncentivesControllerCompatible} from "../SiloIncentivesControllerCompatible.sol";
import {ISiloVault, MarketAllocation} from "silo-vaults/contracts/interfaces/ISiloVault.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";

/// @notice the goal of this contract is to reallocate funds (withdraw all from silo)
/// immediately after any repay happens in silo.
/// This contract requires the allocator role for the vault.
contract SiloVaultReallocationController is SiloIncentivesControllerCompatible {
    mapping(address vault => IERC4626 idleVault) public idleVaults;

    /// @dev list of suported vaults, for which we trigger reallocation after any repay happens in silo.
    address[] public vaults;

    bool public enabled = true;

    error VaultAlreadyAdded();

    constructor(address _owner, address _notifier, address _shareTokenAddress)
        SiloIncentivesControllerCompatible(_owner, _notifier, _shareTokenAddress)
    {}

    function setEnabled(bool _enabled) external onlyOwner {
        enabled = _enabled;
    }

    function addVault(address _vault) external onlyOwner {
        uint256 vaultsLength = vaults.length;

        for (uint256 i = 0; i < vaultsLength; i++) {
            if (vaults[i] == _vault) {
                revert VaultAlreadyAdded();
            }
        }

        vaults.push(_vault);
    }

    function removeVault(address _vault) external {
        uint256 vaultsLength = vaults.length;

        for (uint256 i = 0; i < vaultsLength; i++) {
            if (vaults[i] == _vault) {
                removeVault(i);
                break;
            }
        }
    }

    function removeVault(uint256 _index) public onlyOwner {
        vaults[_index] = vaults[vaults.length - 1];
        vaults.pop();
    }

    function afterTokenTransfer(
        address /*_sender*/,
        uint256 /*_senderBalance*/,
        address /*_recipient*/,
        uint256 /*_recipientBalance*/,
        uint256 /*_totalSupply*/,
        uint256 /*_amount*/
    ) public virtual override {
        if (!enabled) return;

        // do realocation
        IERC4626 silo = IERC4626(IShareToken(msg.sender).silo());
        uint256 vaultsLength = vaults.length;

        for (uint256 i = 0; i < vaultsLength; i++) {
            realocate(vaults[i], silo);
        }
    }

    /// @notice this is public, so anyone can execute it; 
    /// however, because our goal is to do it in one specific way, 
    /// there is no threat to that process.
    function reallocate(address _vault, IERC4626 _silo) public {
        // This is an optional condition because reallocate will check it internally
        if (_silo.maxWithdraw(_vault) == 0) return;

        IERC4626 idleVault = idleVaults[_vault];
        if (address(idleVault) == address(0)) return;

        MarketAllocation[] memory allocations = new MarketAllocation[](2);

        allocations[0].market = _silo;
        allocations[0].assets = 0;

        allocations[1].market = idleVault;
        allocations[1].assets = type(uint256).max;

        ISiloVault(_vault).reallocate(allocations);
    }

    function getVaults() public view returns (address[] memory) {
        return vaults;
    }
}
