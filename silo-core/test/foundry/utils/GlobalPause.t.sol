// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {AddrKey} from "common/addresses/AddrKey.sol";
import {IGlobalPause} from "common/utils/interfaces/IGlobalPause.sol";
import {GlobalPause} from "silo-core/contracts/utils/GlobalPause.sol";
import {GlobalPauseDeploy} from "silo-core/deploy/GlobalPauseDeploy.s.sol";
import {PausableMock} from "../_mocks/PausableMock.sol";
import {GnosisSafeMock} from "../_mocks/GnosisSafeMock.sol";
import {Ownable} from "openzeppelin5/access/Ownable.sol";
import {Ownable2Step} from "openzeppelin5/access/Ownable2Step.sol";

/*
FOUNDRY_PROFILE=core_test forge test --ffi -vv --mc GlobalPauseTest
*/
contract GlobalPauseTest is Test {
    IGlobalPause public globalPause;
    PausableMock public pausableMock1;
    PausableMock public pausableMock2;
    GnosisSafeMock public gnosisSafeMock;
    address public signer1 = makeAddr("signer1");
    address public signer2 = makeAddr("signer2");
    address public authorizedAccount = makeAddr("authorizedAccount");
    address public unauthorizedAccount = makeAddr("unauthorizedAccount");
    address public newOwner = makeAddr("newOwner");

    event Paused(address _contract);
    event Unpaused(address _contract);
    event OwnershipAccepted(address _contract);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event ContractAdded(address _contract);
    event ContractRemoved(address _contract);
    event Authorized(address _account);
    event Unauthorized(address _account);
    event FailedToPause(address _contract);
    event FailedToUnpause(address _contract);

    function setUp() public {
        address[] memory signers = new address[](2);
        signers[0] = signer1;
        signers[1] = signer2;
        gnosisSafeMock = new GnosisSafeMock(signers);

        AddrLib.init();
        AddrLib.setAddress(AddrKey.DAO, address(gnosisSafeMock));

        GlobalPauseDeploy deploy = new GlobalPauseDeploy();
        deploy.disableDeploymentsSync();
        globalPause = deploy.run();

        pausableMock1 = new PausableMock();
        pausableMock2 = new PausableMock();
    }

    /*//////////////////////////////////////////////////////////////
                            PERMISSIONS TESTS
    //////////////////////////////////////////////////////////////*/

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_constructor_setsOwnerToMultisig
    */
    function test_constructor_setsOwnerToMultisig() public view {
        assertEq(Ownable(address(globalPause)).owner(), address(gnosisSafeMock));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_onlySigner_allowsMultisigSigners
    */
    function test_onlySigner_allowsMultisigSigners() public view {
        assertTrue(globalPause.isSigner(signer1));
        assertTrue(globalPause.isSigner(signer2));
        assertFalse(globalPause.isSigner(unauthorizedAccount));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_onlyAuthorized_allowsOwner
    */
    function test_onlyAuthorized_allowsOwner() public {
        vm.prank(pausableMock1.owner());
        pausableMock1.transferOwnership(address(globalPause));

        vm.prank(address(gnosisSafeMock));
        globalPause.acceptOwnership(address(pausableMock1));

        vm.expectEmit(true, false, false, false);
        emit ContractAdded(address(pausableMock1));

        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock1));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_onlyAuthorized_allowsSigners
    */
    function test_onlyAuthorized_allowsSigners() public {
        vm.prank(pausableMock1.owner());
        pausableMock1.transferOwnership(address(globalPause));

        vm.prank(signer1);
        globalPause.acceptOwnership(address(pausableMock1));

        vm.expectEmit(true, false, false, false);
        emit ContractAdded(address(pausableMock1));

        vm.prank(signer1);
        globalPause.addContract(address(pausableMock1));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_onlyAuthorized_allowsAuthorizedAccounts
    */
    function test_onlyAuthorized_allowsAuthorizedAccounts() public {
        vm.prank(address(gnosisSafeMock));
        globalPause.grantAuthorization(authorizedAccount);

        vm.prank(pausableMock1.owner());
        pausableMock1.transferOwnership(address(globalPause));

        vm.prank(authorizedAccount);
        globalPause.acceptOwnership(address(pausableMock1));

        vm.expectEmit(true, false, false, false);
        emit ContractAdded(address(pausableMock1));

        vm.prank(authorizedAccount);
        globalPause.addContract(address(pausableMock1));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_onlyAuthorized_revertsForUnauthorized
    */
    function test_onlyAuthorized_revertsForUnauthorized() public {
        vm.expectRevert(IGlobalPause.Forbidden.selector);
        vm.prank(unauthorizedAccount);
        globalPause.pause(address(pausableMock1));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_onlyOwner_revertsForNonOwner
    */
    function test_onlyOwner_revertsForNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorizedAccount));
        vm.prank(unauthorizedAccount);
        globalPause.grantAuthorization(authorizedAccount);
    }

    /*//////////////////////////////////////////////////////////////
                      OWNERSHIP TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_transferOwnership_startsOwnershipTransfer
    */
    function test_transferOwnership_startsOwnershipTransfer() public {
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferStarted(address(gnosisSafeMock), newOwner);

        vm.prank(address(gnosisSafeMock));
        Ownable2Step(address(globalPause)).transferOwnership(newOwner);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_acceptOwnership_completesOwnershipTransfer
    */
    function test_acceptOwnership_completesOwnershipTransfer() public {
        vm.prank(address(gnosisSafeMock));
        Ownable2Step(address(globalPause)).transferOwnership(newOwner);

        assertEq(Ownable(address(globalPause)).owner(), address(gnosisSafeMock));

        vm.prank(newOwner);
        Ownable2Step(address(globalPause)).acceptOwnership();

        assertEq(Ownable(address(globalPause)).owner(), newOwner);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_acceptOwnership_acceptsContractOwnership
    */
    function test_acceptOwnership_acceptsContractOwnership() public {
        vm.prank(pausableMock1.owner());
        pausableMock1.transferOwnership(address(globalPause));

        vm.expectEmit(true, false, false, false);
        emit OwnershipAccepted(address(pausableMock1));

        vm.prank(signer1);
        globalPause.acceptOwnership(address(pausableMock1));

        assertEq(pausableMock1.owner(), address(globalPause));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_acceptOwnership_revertsForUnauthorized
    */
    function test_acceptOwnership_revertsForUnauthorized() public {
        vm.prank(pausableMock1.owner());
        pausableMock1.transferOwnership(address(globalPause));

        vm.expectRevert(IGlobalPause.Forbidden.selector);
        vm.prank(unauthorizedAccount);
        globalPause.acceptOwnership(address(pausableMock1));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_transferOwnershipFrom_transfersContractOwnership
    */
    function test_transferOwnershipFrom_transfersContractOwnership() public {
        vm.prank(pausableMock1.owner());
        pausableMock1.transferOwnership(address(globalPause));

        vm.prank(signer1);
        globalPause.acceptOwnership(address(pausableMock1));

        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock1));

        // The Ownable2Step contract will emit its own OwnershipTransferStarted event
        // and GlobalPause will emit OwnershipTransferStarted with different parameters
        vm.prank(address(gnosisSafeMock));
        globalPause.transferOwnershipFrom(address(pausableMock1), newOwner);

        // New owner accepts ownership directly on the contract
        vm.prank(newOwner);
        pausableMock1.acceptOwnership();

        assertEq(pausableMock1.owner(), newOwner);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_transferOwnershipFrom_onlyOwner
    */
    function test_transferOwnershipFrom_onlyOwner() public {
        vm.prank(pausableMock1.owner());
        pausableMock1.transferOwnership(address(globalPause));

        vm.prank(signer1);
        globalPause.acceptOwnership(address(pausableMock1));

        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock1));

        // Test that unauthorized account cannot call transferOwnershipFrom
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorizedAccount));
        vm.prank(unauthorizedAccount);
        globalPause.transferOwnershipFrom(address(pausableMock1), newOwner);

        // Test that signer cannot call transferOwnershipFrom (only owner can)
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, signer1));
        vm.prank(signer1);
        globalPause.transferOwnershipFrom(address(pausableMock1), newOwner);

        // Test that authorized account cannot call transferOwnershipFrom (only owner can)
        vm.prank(address(gnosisSafeMock));
        globalPause.grantAuthorization(authorizedAccount);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, authorizedAccount));
        vm.prank(authorizedAccount);
        globalPause.transferOwnershipFrom(address(pausableMock1), newOwner);
    }

    /*//////////////////////////////////////////////////////////////
                  AUTHORIZED ACCOUNTS MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_grantAuthorization_addsAuthorizedAccount
    */
    function test_grantAuthorization_addsAuthorizedAccount() public {
        vm.expectEmit(true, false, false, false);
        emit Authorized(authorizedAccount);

        vm.prank(address(gnosisSafeMock));
        globalPause.grantAuthorization(authorizedAccount);

        vm.prank(authorizedAccount);
        globalPause.pause(address(pausableMock1));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_revokeAuthorization_removesAuthorizedAccount
    */
    function test_revokeAuthorization_removesAuthorizedAccount() public {
        vm.prank(address(gnosisSafeMock));
        globalPause.grantAuthorization(authorizedAccount);

        vm.expectEmit(true, false, false, false);
        emit Unauthorized(authorizedAccount);

        vm.prank(address(gnosisSafeMock));
        globalPause.revokeAuthorization(authorizedAccount);

        vm.expectRevert(IGlobalPause.Forbidden.selector);
        vm.prank(authorizedAccount);
        globalPause.pause(address(pausableMock1));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_grantAuthorization_onlyOwner
    */
    function test_grantAuthorization_onlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorizedAccount));
        vm.prank(unauthorizedAccount);
        globalPause.grantAuthorization(authorizedAccount);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_revokeAuthorization_onlyOwner
    */
    function test_revokeAuthorization_onlyOwner() public {
        vm.prank(address(gnosisSafeMock));
        globalPause.grantAuthorization(authorizedAccount);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorizedAccount));
        vm.prank(unauthorizedAccount);
        globalPause.revokeAuthorization(authorizedAccount);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_authorizedToPause_returnsAuthorizedAccounts
    */
    function test_authorizedToPause_returnsAuthorizedAccounts() public {
        address[] memory authorized = globalPause.authorizedToPause();
        assertEq(authorized.length, 0);

        vm.prank(address(gnosisSafeMock));
        globalPause.grantAuthorization(authorizedAccount);

        authorized = globalPause.authorizedToPause();
        assertEq(authorized.length, 1);
        assertEq(authorized[0], authorizedAccount);
    }

    /*//////////////////////////////////////////////////////////////
                      CONTRACT MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_addContract_addsToList
    */
    function test_addContract_addsToList() public {
        vm.prank(pausableMock1.owner());
        pausableMock1.transferOwnership(address(globalPause));

        vm.prank(signer1);
        globalPause.acceptOwnership(address(pausableMock1));

        vm.expectEmit(true, false, false, false);
        emit ContractAdded(address(pausableMock1));

        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock1));

        address[] memory contracts = globalPause.allContracts();
        assertEq(contracts.length, 1);
        assertEq(contracts[0], address(pausableMock1));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_addContract_allowsAuthorizedWithoutOwnership
    */
    function test_addContract_allowsAuthorizedWithoutOwnership() public {
        // Test that authorized users can add contracts even if GlobalPause is not the owner
        vm.expectEmit(true, false, false, false);
        emit ContractAdded(address(pausableMock1));

        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock1));

        address[] memory contracts = globalPause.allContracts();
        assertEq(contracts.length, 1);
        assertEq(contracts[0], address(pausableMock1));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_removeContract_removesFromList
    */
    function test_removeContract_removesFromList() public {
        vm.prank(pausableMock1.owner());
        pausableMock1.transferOwnership(address(globalPause));

        vm.prank(signer1);
        globalPause.acceptOwnership(address(pausableMock1));

        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock1));

        vm.prank(address(gnosisSafeMock));
        globalPause.transferOwnershipFrom(address(pausableMock1), newOwner);

        vm.prank(newOwner);
        pausableMock1.acceptOwnership();

        vm.expectEmit(true, false, false, false);
        emit ContractRemoved(address(pausableMock1));

        vm.prank(address(gnosisSafeMock));
        globalPause.removeContract(address(pausableMock1));

        address[] memory contracts = globalPause.allContracts();
        assertEq(contracts.length, 0);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_removeContract_allowsRemovalEvenIfStillOwner
    */
    function test_removeContract_allowsRemovalEvenIfStillOwner() public {
        vm.prank(pausableMock1.owner());
        pausableMock1.transferOwnership(address(globalPause));

        vm.prank(signer1);
        globalPause.acceptOwnership(address(pausableMock1));

        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock1));

        // The contract can be removed even if GlobalPause is still the owner
        vm.expectEmit(true, false, false, false);
        emit ContractRemoved(address(pausableMock1));

        vm.prank(address(gnosisSafeMock));
        globalPause.removeContract(address(pausableMock1));

        address[] memory contracts = globalPause.allContracts();
        assertEq(contracts.length, 0);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_removeContract_onlyOwner
    */
    function test_removeContract_onlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorizedAccount));
        vm.prank(unauthorizedAccount);
        globalPause.removeContract(address(pausableMock1));
    }

    /*//////////////////////////////////////////////////////////////
                        PAUSE/UNPAUSE TESTS
    //////////////////////////////////////////////////////////////*/

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_pause_pausesSingleContract
    */
    function test_pause_pausesSingleContract() public {
        vm.prank(pausableMock1.owner());
        pausableMock1.transferOwnership(address(globalPause));

        vm.prank(signer1);
        globalPause.acceptOwnership(address(pausableMock1));

        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock1));

        assertFalse(pausableMock1.paused());

        vm.expectEmit(true, false, false, false);
        emit Paused(address(pausableMock1));

        vm.prank(signer1);
        globalPause.pause(address(pausableMock1));

        assertTrue(pausableMock1.paused());
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_unpause_unpausesSingleContract
    */
    function test_unpause_unpausesSingleContract() public {
        vm.prank(pausableMock1.owner());
        pausableMock1.transferOwnership(address(globalPause));

        vm.prank(signer1);
        globalPause.acceptOwnership(address(pausableMock1));

        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock1));

        vm.prank(signer1);
        globalPause.pause(address(pausableMock1));

        assertTrue(pausableMock1.paused());

        vm.expectEmit(true, false, false, false);
        emit Unpaused(address(pausableMock1));

        vm.prank(signer1);
        globalPause.unpause(address(pausableMock1));

        assertFalse(pausableMock1.paused());
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_pauseAll_pausesAllContracts
    */
    function test_pauseAll_pausesAllContracts() public {
        vm.prank(pausableMock1.owner());
        pausableMock1.transferOwnership(address(globalPause));
        vm.prank(pausableMock2.owner());
        pausableMock2.transferOwnership(address(globalPause));

        vm.prank(signer1);
        globalPause.acceptOwnership(address(pausableMock1));
        vm.prank(signer1);
        globalPause.acceptOwnership(address(pausableMock2));

        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock1));
        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock2));

        assertFalse(pausableMock1.paused());
        assertFalse(pausableMock2.paused());

        vm.expectEmit(true, false, false, false);
        emit Paused(address(pausableMock1));
        vm.expectEmit(true, false, false, false);
        emit Paused(address(pausableMock2));

        vm.prank(signer1);
        globalPause.pauseAll();

        assertTrue(pausableMock1.paused());
        assertTrue(pausableMock2.paused());
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_unpauseAll_unpausesAllContracts
    */
    function test_unpauseAll_unpausesAllContracts() public {
        vm.prank(pausableMock1.owner());
        pausableMock1.transferOwnership(address(globalPause));
        vm.prank(pausableMock2.owner());
        pausableMock2.transferOwnership(address(globalPause));

        vm.prank(signer1);
        globalPause.acceptOwnership(address(pausableMock1));
        vm.prank(signer1);
        globalPause.acceptOwnership(address(pausableMock2));

        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock1));
        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock2));

        vm.prank(signer1);
        globalPause.pauseAll();

        assertTrue(pausableMock1.paused());
        assertTrue(pausableMock2.paused());

        vm.expectEmit(true, false, false, false);
        emit Unpaused(address(pausableMock1));
        vm.expectEmit(true, false, false, false);
        emit Unpaused(address(pausableMock2));

        vm.prank(signer1);
        globalPause.unpauseAll();

        assertFalse(pausableMock1.paused());
        assertFalse(pausableMock2.paused());
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_pauseAll_skipsContractsNotOwned
    */
    function test_pauseAll_skipsContractsNotOwned() public {
        vm.prank(pausableMock1.owner());
        pausableMock1.transferOwnership(address(globalPause));

        vm.prank(signer1);
        globalPause.acceptOwnership(address(pausableMock1));

        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock1));

        vm.prank(address(gnosisSafeMock));
        globalPause.transferOwnershipFrom(address(pausableMock1), newOwner);

        vm.prank(newOwner);
        pausableMock1.acceptOwnership();

        vm.prank(signer1);
        globalPause.pauseAll();

        assertFalse(pausableMock1.paused());
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_pause_revertsForUnauthorized
    */
    function test_pause_revertsForUnauthorized() public {
        vm.expectRevert(IGlobalPause.Forbidden.selector);
        vm.prank(unauthorizedAccount);
        globalPause.pause(address(pausableMock1));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_unpause_revertsForUnauthorized
    */
    function test_unpause_revertsForUnauthorized() public {
        vm.expectRevert(IGlobalPause.Forbidden.selector);
        vm.prank(unauthorizedAccount);
        globalPause.unpause(address(pausableMock1));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_pauseAll_revertsForUnauthorized
    */
    function test_pauseAll_revertsForUnauthorized() public {
        vm.expectRevert(IGlobalPause.Forbidden.selector);
        vm.prank(unauthorizedAccount);
        globalPause.pauseAll();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_unpauseAll_revertsForUnauthorized
    */
    function test_unpauseAll_revertsForUnauthorized() public {
        vm.expectRevert(IGlobalPause.Forbidden.selector);
        vm.prank(unauthorizedAccount);
        globalPause.unpauseAll();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_pauseAll_emitsFailedToPauseForContractsNotOwned
    */
    function test_pauseAll_emitsFailedToPauseForContractsNotOwned() public {
        // Transfer ownership to GlobalPause for pausableMock1 only
        vm.prank(pausableMock1.owner());
        pausableMock1.transferOwnership(address(globalPause));

        vm.prank(signer1);
        globalPause.acceptOwnership(address(pausableMock1));

        // Add both contracts - GlobalPause owns pausableMock1 but not pausableMock2
        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock1));
        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock2));

        // Expect Paused for pausableMock1 and FailedToPause for pausableMock2
        vm.expectEmit(true, false, false, false);
        emit Paused(address(pausableMock1));
        vm.expectEmit(true, false, false, false);
        emit FailedToPause(address(pausableMock2));

        // Call pauseAll - it should not revert
        vm.prank(signer1);
        globalPause.pauseAll();

        // Verify pausableMock1 is paused but pausableMock2 is not
        assertTrue(pausableMock1.paused());
        assertFalse(pausableMock2.paused());
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_unpauseAll_emitsFailedToUnpauseForContractsNotOwned
    */
    function test_unpauseAll_emitsFailedToUnpauseForContractsNotOwned() public {
        // Transfer ownership to GlobalPause for pausableMock1 only
        vm.prank(pausableMock1.owner());
        pausableMock1.transferOwnership(address(globalPause));

        vm.prank(signer1);
        globalPause.acceptOwnership(address(pausableMock1));

        // Add both contracts - GlobalPause owns pausableMock1 but not pausableMock2
        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock1));
        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock2));

        // Call pauseAll - it should not revert
        vm.prank(signer1);
        globalPause.pauseAll();

        assertTrue(pausableMock1.paused());

        // Expect Unpaused for pausableMock1 and FailedToUnpause for pausableMock2
        vm.expectEmit(true, false, false, false);
        emit Unpaused(address(pausableMock1));
        vm.expectEmit(true, false, false, false);
        emit FailedToUnpause(address(pausableMock2));

        // Call unpauseAll - it should not revert
        vm.prank(signer1);
        globalPause.unpauseAll();

        // Verify pausableMock1 is unpaused but pausableMock2 is not
        assertFalse(pausableMock1.paused());
        assertFalse(pausableMock2.paused());
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_unpause_neverRevertsFromAuthorizedAddress
    */
    function test_unpause_neverRevertsFromAuthorizedAddress() public {
        // Test 1: Unpause from owner (multisig) - contract not owned by GlobalPause
        // Should emit FailedToUnpause because GlobalPause doesn't own the contract
        vm.expectEmit(true, false, false, false);
        emit FailedToUnpause(address(pausableMock1));

        vm.prank(address(gnosisSafeMock));
        globalPause.unpause(address(pausableMock1)); // Should not revert, just emit FailedToUnpause

        // Test 2: Unpause from signer - contract not owned by GlobalPause
        vm.expectEmit(true, false, false, false);
        emit FailedToUnpause(address(pausableMock1));

        vm.prank(signer1);
        globalPause.unpause(address(pausableMock1)); // Should not revert, just emit FailedToUnpause

        // Test 3: Unpause from authorized account
        vm.prank(address(gnosisSafeMock));
        globalPause.grantAuthorization(authorizedAccount);

        vm.expectEmit(true, false, false, false);
        emit FailedToUnpause(address(pausableMock1));

        vm.prank(authorizedAccount);
        globalPause.unpause(address(pausableMock1)); // Should not revert, just emit FailedToUnpause

        // Test 4: Unpause a contract that's not owned by GlobalPause
        vm.expectEmit(true, false, false, false);
        emit FailedToUnpause(address(pausableMock2));

        vm.prank(signer1);
        globalPause.unpause(address(pausableMock2)); // Should not revert, just emit FailedToUnpause

        // Test 5: Unpause a contract that doesn't implement IPausable
        address nonPausableContract = address(gnosisSafeMock);
        vm.expectEmit(true, false, false, false);
        emit FailedToUnpause(nonPausableContract);

        vm.prank(signer1);
        globalPause.unpause(nonPausableContract); // Should not revert, just emit FailedToUnpause

        // Test 6: Add contract to list and unpause when GlobalPause owns it
        vm.prank(pausableMock1.owner());
        pausableMock1.transferOwnership(address(globalPause));

        vm.prank(signer1);
        globalPause.acceptOwnership(address(pausableMock1));

        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock1));

        // First pause it
        vm.expectEmit(true, false, false, false);
        emit Paused(address(pausableMock1));

        vm.prank(signer1);
        globalPause.pause(address(pausableMock1));
        assertTrue(pausableMock1.paused());

        // Now unpause - should succeed
        vm.expectEmit(true, false, false, false);
        emit Unpaused(address(pausableMock1));

        vm.prank(signer1);
        globalPause.unpause(address(pausableMock1)); // Should not revert and should emit Unpaused
        assertFalse(pausableMock1.paused());

        // Test 7: Unpause already unpaused contract - should still not revert
        // The mock contract will revert with ExpectedPause() when trying to unpause an unpaused contract
        vm.expectEmit(true, false, false, false);
        emit FailedToUnpause(address(pausableMock1));

        vm.prank(signer1);
        globalPause.unpause(address(pausableMock1)); // Should not revert, just emit FailedToUnpause
        assertFalse(pausableMock1.paused());
    }

    /*//////////////////////////////////////////////////////////////
                        FAILED TO ADD/REMOVE TESTS
    //////////////////////////////////////////////////////////////*/

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_addContract_revertsWhenAlreadyAdded
    */
    function test_addContract_revertsWhenAlreadyAdded() public {
        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock1));

        vm.expectRevert(IGlobalPause.FailedToAdd.selector);
        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock1));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_removeContract_revertsWhenNotInList
    */
    function test_removeContract_revertsWhenNotInList() public {
        vm.expectRevert(IGlobalPause.FailedToRemove.selector);
        vm.prank(address(gnosisSafeMock));
        globalPause.removeContract(address(pausableMock1));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_removeContract_revertsWhenAlreadyRemoved
    */
    function test_removeContract_revertsWhenAlreadyRemoved() public {
        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock1));

        vm.prank(address(gnosisSafeMock));
        globalPause.removeContract(address(pausableMock1));

        vm.expectRevert(IGlobalPause.FailedToRemove.selector);
        vm.prank(address(gnosisSafeMock));
        globalPause.removeContract(address(pausableMock1));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_grantAuthorization_revertsWhenAlreadyAuthorized
    */
    function test_grantAuthorization_revertsWhenAlreadyAuthorized() public {
        vm.prank(address(gnosisSafeMock));
        globalPause.grantAuthorization(authorizedAccount);

        vm.expectRevert(IGlobalPause.FailedToAdd.selector);
        vm.prank(address(gnosisSafeMock));
        globalPause.grantAuthorization(authorizedAccount);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_revokeAuthorization_revertsWhenNotAuthorized
    */
    function test_revokeAuthorization_revertsWhenNotAuthorized() public {
        vm.expectRevert(IGlobalPause.FailedToRemove.selector);
        vm.prank(address(gnosisSafeMock));
        globalPause.revokeAuthorization(authorizedAccount);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_revokeAuthorization_revertsWhenAlreadyRevoked
    */
    function test_revokeAuthorization_revertsWhenAlreadyRevoked() public {
        // Grant and then revoke authorization
        vm.prank(address(gnosisSafeMock));
        globalPause.grantAuthorization(authorizedAccount);

        vm.prank(address(gnosisSafeMock));
        globalPause.revokeAuthorization(authorizedAccount);

        // Try to revoke authorization again - should revert with FailedToRemove
        vm.expectRevert(IGlobalPause.FailedToRemove.selector);
        vm.prank(address(gnosisSafeMock));
        globalPause.revokeAuthorization(authorizedAccount);
    }

    /*//////////////////////////////////////////////////////////////
                        RENOUNCE OWNERSHIP TESTS
    //////////////////////////////////////////////////////////////*/

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_renounceOwnership_revertsWhenContractsNotEmpty
    */
    function test_renounceOwnership_revertsWhenContractsNotEmpty() public {
        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock1));

        vm.expectRevert(IGlobalPause.ContractsNotEmpty.selector);
        vm.prank(address(gnosisSafeMock));
        GlobalPause(address(globalPause)).renounceOwnership();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_renounceOwnership_revertsWhenAuthorizedToPauseNotEmpty
    */
    function test_renounceOwnership_revertsWhenAuthorizedToPauseNotEmpty() public {
        vm.prank(address(gnosisSafeMock));
        globalPause.grantAuthorization(authorizedAccount);

        vm.expectRevert(IGlobalPause.AuthorizedToPauseNotEmpty.selector);
        vm.prank(address(gnosisSafeMock));
        GlobalPause(address(globalPause)).renounceOwnership();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_renounceOwnership_revertsWhenBothNotEmpty
    */
    function test_renounceOwnership_revertsWhenBothNotEmpty() public {
        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock1));

        vm.prank(address(gnosisSafeMock));
        globalPause.grantAuthorization(authorizedAccount);

        vm.expectRevert(IGlobalPause.ContractsNotEmpty.selector);
        vm.prank(address(gnosisSafeMock));
        GlobalPause(address(globalPause)).renounceOwnership();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_renounceOwnership_succeedsWhenBothEmpty
    */
    function test_renounceOwnership_succeedsWhenBothEmpty() public {
        vm.prank(address(gnosisSafeMock));
        GlobalPause(address(globalPause)).renounceOwnership();

        assertEq(Ownable(address(globalPause)).owner(), address(0));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_renounceOwnership_succeedsAfterRemovingAll
    */
    function test_renounceOwnership_succeedsAfterRemovingAll() public {
        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock1));

        vm.prank(address(gnosisSafeMock));
        globalPause.grantAuthorization(authorizedAccount);

        vm.prank(address(gnosisSafeMock));
        globalPause.removeContract(address(pausableMock1));

        vm.prank(address(gnosisSafeMock));
        globalPause.revokeAuthorization(authorizedAccount);

        vm.prank(address(gnosisSafeMock));
        GlobalPause(address(globalPause)).renounceOwnership();

        assertEq(Ownable(address(globalPause)).owner(), address(0));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_renounceOwnership_onlyOwner
    */
    function test_renounceOwnership_onlyOwner() public {
        // Test that unauthorized account cannot renounce ownership
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorizedAccount));
        vm.prank(unauthorizedAccount);
        GlobalPause(address(globalPause)).renounceOwnership();

        // Test that signer cannot renounce ownership (only owner can)
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, signer1));
        vm.prank(signer1);
        GlobalPause(address(globalPause)).renounceOwnership();

        // Test that authorized account cannot renounce ownership (only owner can)
        // Note: When there are authorized accounts, renounceOwnership reverts with AuthorizedToPauseNotEmpty
        // before checking the onlyOwner modifier
        vm.prank(address(gnosisSafeMock));
        globalPause.grantAuthorization(authorizedAccount);

        vm.expectRevert(IGlobalPause.AuthorizedToPauseNotEmpty.selector);
        vm.prank(authorizedAccount);
        GlobalPause(address(globalPause)).renounceOwnership();

        // Remove the authorized account and try again with unauthorized account
        vm.prank(address(gnosisSafeMock));
        globalPause.revokeAuthorization(authorizedAccount);

        // Now it should revert with OwnableUnauthorizedAccount
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, authorizedAccount));
        vm.prank(authorizedAccount);
        GlobalPause(address(globalPause)).renounceOwnership();

        // Verify that the owner is still the multisig
        assertEq(Ownable(address(globalPause)).owner(), address(gnosisSafeMock));

        // Owner can renounce ownership
        vm.prank(address(gnosisSafeMock));
        GlobalPause(address(globalPause)).renounceOwnership();

        assertEq(Ownable(address(globalPause)).owner(), address(0));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mt test_getAllContractsPauseStatus_returnsDifferentStatuses
    */
    function test_getAllContractsPauseStatus_returnsDifferentStatuses() public {
        // Setup: Transfer ownership of both contracts to GlobalPause
        vm.prank(pausableMock1.owner());
        pausableMock1.transferOwnership(address(globalPause));
        vm.prank(pausableMock2.owner());
        pausableMock2.transferOwnership(address(globalPause));

        vm.prank(signer1);
        globalPause.acceptOwnership(address(pausableMock1));
        vm.prank(signer1);
        globalPause.acceptOwnership(address(pausableMock2));

        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock1));
        vm.prank(address(gnosisSafeMock));
        globalPause.addContract(address(pausableMock2));

        vm.prank(signer1);
        globalPause.pause(address(pausableMock1));

        IGlobalPause.ContractPauseStatus[] memory statuses = globalPause.getAllContractsPauseStatus();

        assertEq(statuses.length, 2);
        assertEq(statuses[0].contractAddress, address(pausableMock1));
        assertTrue(statuses[0].isPaused);
        assertEq(statuses[1].contractAddress, address(pausableMock2));
        assertFalse(statuses[1].isPaused);
    }
}
