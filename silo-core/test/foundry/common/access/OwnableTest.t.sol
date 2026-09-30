// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "openzeppelin5/access/Ownable2Step.sol";
import {Test} from "forge-std/Test.sol";
import {OwnableMock as SiloOwnableWith1Step} from "silo-core/test/foundry/_mocks/OwnableMock.sol";

/*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mc OwnableTest
*/
contract OwnableTest is Test {
    SiloOwnableWith1Step public ownableContract;

    address public owner = makeAddr("Owner");
    address public newOwner = makeAddr("NewOwner");
    address public randomUser = makeAddr("RandomUser");

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setUp() public {
        vm.prank(owner);
        ownableContract = new SiloOwnableWith1Step(owner);
    }

    function testTransferOwnership1Step() public {
        // Verify initial owner
        assertEq(ownableContract.owner(), owner);

        // Expect the OwnershipTransferred event
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(owner, newOwner);

        // Transfer ownership in one step
        vm.prank(owner);
        ownableContract.transferOwnership1Step(newOwner);

        // Verify ownership was transferred immediately
        assertEq(ownableContract.owner(), newOwner);
    }

    function testTransferOwnership1StepToZeroAddress() public {
        // Transfer to zero address should revert with OwnableInvalidOwner error
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));

        vm.prank(owner);
        ownableContract.transferOwnership1Step(address(0));

        // Verify ownership remains unchanged
        assertEq(ownableContract.owner(), owner);
    }

    function testTransferOwnership1StepUnauthorized() public {
        // Non-owner should not be able to transfer ownership
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, randomUser));

        vm.prank(randomUser);
        ownableContract.transferOwnership1Step(newOwner);

        // Verify ownership remains unchanged
        assertEq(ownableContract.owner(), owner);
    }

    function testTransferOwnership1StepToSameOwner() public {
        // Transfer to same owner should succeed
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(owner, owner);

        vm.prank(owner);
        ownableContract.transferOwnership1Step(owner);

        // Verify ownership remains the same
        assertEq(ownableContract.owner(), owner);
    }

    function testTransferOwnership1StepMultipleTimes() public {
        // First transfer
        vm.prank(owner);
        ownableContract.transferOwnership1Step(newOwner);
        assertEq(ownableContract.owner(), newOwner);

        // Second transfer by new owner
        address thirdOwner = address(0x4);

        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(newOwner, thirdOwner);

        vm.prank(newOwner);
        ownableContract.transferOwnership1Step(thirdOwner);

        // Verify final ownership
        assertEq(ownableContract.owner(), thirdOwner);
    }

    function testFuzzTransferOwnership1Step(address initialOwner, address targetOwner) public {
        // Skip if initial owner is zero (constructor would fail)
        vm.assume(initialOwner != address(0));
        // Skip if target owner is zero (transferOwnership1Step would revert)
        vm.assume(targetOwner != address(0));

        // Deploy with fuzzed initial owner
        vm.prank(initialOwner);
        SiloOwnableWith1Step fuzzedOwnable = new SiloOwnableWith1Step(initialOwner);

        // Transfer to fuzzed target owner
        vm.expectEmit(true, true, false, true);
        emit OwnershipTransferred(initialOwner, targetOwner);

        vm.prank(initialOwner);
        fuzzedOwnable.transferOwnership1Step(targetOwner);

        // Verify ownership
        assertEq(fuzzedOwnable.owner(), targetOwner);
    }
}
