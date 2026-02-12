// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {AccessControlEnumerable} from "openzeppelin5/access/extensions/AccessControlEnumerable.sol";

abstract contract Whitelist is AccessControlEnumerable {
    bytes32 public constant ALLOWED_ROLE = keccak256("ALLOWED_ROLE");

    error OnlyAllowedRole();

    modifier onlyAllowedOrPublic() {
        // If no allowed role is set, allow anyone to liquidate
        require(getRoleMemberCount(ALLOWED_ROLE) == 0 || hasRole(ALLOWED_ROLE, msg.sender), OnlyAllowedRole());

        _;
    }

    modifier onlyAllowed() {
        require(hasRole(ALLOWED_ROLE, msg.sender), OnlyAllowedRole());

        _;
    }

    // solhint-disable-next-line func-name-mixedcase
    function __Whitelist_init(address _owner) internal virtual {
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    }
}
