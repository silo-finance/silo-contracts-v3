// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20PermitUpgradeable} from "openzeppelin5-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

contract ERC20UpgradableMock is ERC20PermitUpgradeable {
    uint256 public constant USER_BALANCE = 1000e18;

    function mockUserBalance(address _user) external {
        _mint(_user, USER_BALANCE);
    }
}
