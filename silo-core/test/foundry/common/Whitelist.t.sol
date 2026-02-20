// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "openzeppelin5/access/IAccessControl.sol";

import {Whitelist} from "silo-core/contracts/hooks/_common/Whitelist.sol";

/// @notice Concrete implementation of Whitelist for testing purposes
contract WhitelistImpl is Whitelist {
    function initialize(address _owner) external {
        __Whitelist_init(_owner);
    }

    function onlyAllowedFn() external onlyAllowed {
        // Test function protected by onlyAllowed modifier
    }

    function onlyAllowedOrPublicFn() external onlyAllowedOrPublic {
        // Test function protected by onlyAllowedOrPublic modifier
    }
}

/*
FOUNDRY_PROFILE=core_test forge test --ffi --mc WhitelistTest -vv
*/
contract WhitelistTest is Test {
    bytes32 public constant ALLOWED_ROLE = keccak256("ALLOWED_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);

    WhitelistImpl whitelist;
    address owner;
    address allowedUser;
    address unauthorizedUser;
    address zeroAddress;

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    function setUp() public {
        owner = makeAddr("owner");
        allowedUser = makeAddr("allowedUser");
        unauthorizedUser = makeAddr("unauthorizedUser");
        zeroAddress = address(0);

        whitelist = new WhitelistImpl();
        whitelist.initialize(owner);

        assertEq(whitelist.ALLOWED_ROLE(), ALLOWED_ROLE, "ALLOWED_ROLE should be correctly defined");
        assertEq(whitelist.DEFAULT_ADMIN_ROLE(), DEFAULT_ADMIN_ROLE, "DEFAULT_ADMIN_ROLE should be correctly defined");
    }

    // ============ Initialization Tests ============

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_Initialization_onlyOnce
    */
    function test_Initialization_onlyOnce() public {
        /*
        we can not use onlyInitializing, because `Linearization of inheritance graph impossible`
        so we have no protection inside whitelist
        */
        whitelist.initialize(makeAddr("fakeOwner"));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_Initialization_GrantsDefaultAdminRoleToOwner
    */
    function test_Initialization_GrantsDefaultAdminRoleToOwner() public view {
        assertTrue(whitelist.hasRole(DEFAULT_ADMIN_ROLE, owner), "owner should have DEFAULT_ADMIN_ROLE");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_Initialization_ZeroAddressHasNoRoles
    */
    function test_Initialization_ZeroAddressHasNoRoles() public view {
        assertFalse(whitelist.hasRole(DEFAULT_ADMIN_ROLE, zeroAddress));
        assertFalse(whitelist.hasRole(ALLOWED_ROLE, zeroAddress));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_Initialization_Bytes32Zero
    */
    function test_Initialization_Bytes32Zero() public view {
        bytes32 role = bytes32(0);
        assertFalse(whitelist.hasRole(role, address(0)));
        assertEq(whitelist.getRoleAdmin(role), whitelist.DEFAULT_ADMIN_ROLE(), "default admin is bytes32(0)");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_Initialization_OwnerCanGrantRoles
    */
    function test_Initialization_OwnerCanGrantRoles() public {
        vm.prank(owner);
        whitelist.grantRole(ALLOWED_ROLE, allowedUser);

        assertTrue(whitelist.hasRole(ALLOWED_ROLE, allowedUser));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_Initialization_NonOwnerCannotGrantRoles
    */
    function test_Initialization_NonOwnerCannotGrantRoles() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorizedUser,
                DEFAULT_ADMIN_ROLE
            )
        );
        whitelist.grantRole(ALLOWED_ROLE, allowedUser);
    }

    // ============ onlyAllowed Modifier Tests ============

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_OnlyAllowed_AllowsUserWithAllowedRole
    */
    function test_OnlyAllowed_AllowsUserWithAllowedRole() public {
        vm.prank(owner);
        whitelist.grantRole(ALLOWED_ROLE, allowedUser);

        vm.prank(allowedUser);
        whitelist.onlyAllowedFn();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_OnlyAllowed_RevertsForUserWithoutAllowedRole
    */
    function test_OnlyAllowed_RevertsForUserWithoutAllowedRole() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(Whitelist.OnlyAllowedRole.selector);
        whitelist.onlyAllowedFn();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_OnlyAllowed_RevertsForOwnerWithoutAllowedRole
    */
    function test_OnlyAllowed_RevertsForOwnerWithoutAllowedRole() public {
        // Owner has DEFAULT_ADMIN_ROLE but not ALLOWED_ROLE
        vm.prank(owner);
        vm.expectRevert(Whitelist.OnlyAllowedRole.selector);
        whitelist.onlyAllowedFn();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_OnlyAllowed_RevertsForZeroAddress
    */
    function test_OnlyAllowed_RevertsForZeroAddress() public {
        vm.prank(zeroAddress);
        vm.expectRevert(Whitelist.OnlyAllowedRole.selector);
        whitelist.onlyAllowedFn();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_OnlyAllowed_RevertsAfterRoleRevoked
    */
    function test_OnlyAllowed_RevertsAfterRoleRevoked() public {
        vm.prank(owner);
        whitelist.grantRole(ALLOWED_ROLE, allowedUser);

        vm.prank(allowedUser);
        whitelist.onlyAllowedFn();

        vm.prank(owner);
        whitelist.revokeRole(ALLOWED_ROLE, allowedUser);


        vm.prank(allowedUser);
        vm.expectRevert(Whitelist.OnlyAllowedRole.selector);
        whitelist.onlyAllowedFn();
    }

    // ============ onlyAllowedOrPublic Modifier Tests ============

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_OnlyAllowedOrPublic_AllowsAnyoneWhenNoRolesSet
    */
    function test_OnlyAllowedOrPublic_AllowsAnyoneWhenNoRolesSet() public {
        // No roles granted, should allow public access
        vm.prank(unauthorizedUser);
        whitelist.onlyAllowedOrPublicFn();

        vm.prank(allowedUser);
        whitelist.onlyAllowedOrPublicFn();

        vm.prank(owner);
        whitelist.onlyAllowedOrPublicFn();
        
        vm.prank(zeroAddress);
        whitelist.onlyAllowedOrPublicFn();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_OnlyAllowedOrPublic_AllowsUserWithAllowedRole
    */
    function test_OnlyAllowedOrPublic_AllowsUserWithAllowedRole() public {
        vm.prank(owner);
        whitelist.grantRole(ALLOWED_ROLE, allowedUser);

        vm.prank(allowedUser);
        whitelist.onlyAllowedOrPublicFn();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_OnlyAllowedOrPublic_RevertsForUserWithoutAllowedRoleWhenRolesExist
    */
    function test_OnlyAllowedOrPublic_RevertsForUserWithoutAllowedRoleWhenRolesExist() public {
        vm.prank(owner);
        whitelist.grantRole(ALLOWED_ROLE, allowedUser);

        vm.prank(unauthorizedUser);
        vm.expectRevert(Whitelist.OnlyAllowedRole.selector);
        whitelist.onlyAllowedOrPublicFn();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_OnlyAllowedOrPublic_AllowsPublicAfterAllRolesRevoked
    */
    function test_OnlyAllowedOrPublic_AllowsPublicAfterAllRolesRevoked() public {
        vm.prank(owner);
        whitelist.grantRole(ALLOWED_ROLE, allowedUser);

        vm.expectRevert(Whitelist.OnlyAllowedRole.selector);
        vm.prank(unauthorizedUser);
        whitelist.onlyAllowedOrPublicFn();

        vm.prank(owner);
        whitelist.revokeRole(ALLOWED_ROLE, allowedUser);

        // After all roles revoked, should allow public access
        vm.prank(unauthorizedUser);
        whitelist.onlyAllowedOrPublicFn();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_OnlyAllowedOrPublic_AllowsMultipleUsersWithRole
    */
    function test_OnlyAllowedOrPublic_AllowsMultipleUsersWithRole() public {
        address user2 = address(0x4);
        address user3 = address(0x5);

        vm.startPrank(owner);
        whitelist.grantRole(ALLOWED_ROLE, allowedUser);
        whitelist.grantRole(ALLOWED_ROLE, user2);
        whitelist.grantRole(ALLOWED_ROLE, user3);
        vm.stopPrank();

        vm.prank(allowedUser);
        whitelist.onlyAllowedOrPublicFn();

        vm.prank(user2);
        whitelist.onlyAllowedOrPublicFn();

        vm.prank(user3);
        whitelist.onlyAllowedOrPublicFn();
    }


    function test_OnlyAllowedOrPublic_TransitionFromPublicToRestricted() public {
        // Initially public (no roles)
        vm.prank(unauthorizedUser);
        whitelist.onlyAllowedOrPublicFn();

        // Grant role to someone
        vm.prank(owner);
        whitelist.grantRole(ALLOWED_ROLE, allowedUser);

        // Now unauthorized user should be blocked
        vm.prank(unauthorizedUser);
        vm.expectRevert(Whitelist.OnlyAllowedRole.selector);
        whitelist.onlyAllowedOrPublicFn();

        // But allowed user should still work
        vm.prank(allowedUser);
        whitelist.onlyAllowedOrPublicFn();

        vm.prank(owner);
        whitelist.revokeRole(ALLOWED_ROLE, allowedUser);

        vm.prank(unauthorizedUser);
        whitelist.onlyAllowedOrPublicFn();
    }

    // ============ Integration Tests ============

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_Integration_CompleteWorkflow
    */
    function test_Integration_CompleteWorkflow() public {
        address user1 = address(0x10);
        address user2 = address(0x11);
        address user3 = address(0x12);

        // 1. Initially public access
        vm.prank(user1);
        whitelist.onlyAllowedOrPublicFn();

        // 2. Grant roles to multiple users
        vm.startPrank(owner);
        whitelist.grantRole(ALLOWED_ROLE, user1);
        whitelist.grantRole(ALLOWED_ROLE, user2);
        vm.stopPrank();

        // 3. Users with roles can access
        vm.prank(user1);
        whitelist.onlyAllowedFn();
        vm.prank(user1);
        whitelist.onlyAllowedOrPublicFn();

        vm.prank(user2);
        whitelist.onlyAllowedFn();
        vm.prank(user2);
        whitelist.onlyAllowedOrPublicFn();

        // 4. User without role cannot access
        vm.prank(user3);
        vm.expectRevert(Whitelist.OnlyAllowedRole.selector);
        whitelist.onlyAllowedFn();

        vm.prank(user3);
        vm.expectRevert(Whitelist.OnlyAllowedRole.selector);
        whitelist.onlyAllowedOrPublicFn();

        // 5. Revoke one role
        vm.prank(owner);
        whitelist.revokeRole(ALLOWED_ROLE, user1);

        // 6. User1 can no longer access
        vm.prank(user1);
        vm.expectRevert(Whitelist.OnlyAllowedRole.selector);
        whitelist.onlyAllowedFn();

        // 7. User2 still can access
        vm.prank(user2);
        whitelist.onlyAllowedFn();

        // 8. Revoke all roles
        vm.prank(owner);
        whitelist.revokeRole(ALLOWED_ROLE, user2);

        // 9. Public access restored
        vm.prank(user3);
        whitelist.onlyAllowedOrPublicFn();
    }
}
