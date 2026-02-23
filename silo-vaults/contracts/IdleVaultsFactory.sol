// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IERC4626, IERC20Metadata} from "openzeppelin5/interfaces/IERC4626.sol";

import {Create2Factory} from "common/utils/Create2Factory.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import {IdleVault} from "./IdleVault.sol";

contract IdleVaultsFactory is Create2Factory {
    mapping(address => bool) public isIdleVault;

    function createIdleVault(IERC4626 _vault, bytes32 _externalSalt) external virtual returns (IdleVault idleVault) {
        idleVault = new IdleVault{salt: _salt(_externalSalt)}(
            address(_vault),
            _vault.asset(),
            string.concat("IdleVault for ", IERC20Metadata(address(_vault)).name()),
            string.concat("IV-", IERC20Metadata(address(_vault)).symbol())
        );

        isIdleVault[address(idleVault)] = true;

        emit EventsLib.CreateIdleVault(address(idleVault), address(_vault));
    }
}
