// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IERC20Metadata} from "silo-oracles/test/foundry/interfaces/IERC20Metadata.sol";
import {ManageableOracleFactory} from "silo-oracles/contracts/manageable/ManageableOracleFactory.sol";
import {IManageableOracleFactory} from "silo-oracles/contracts/interfaces/IManageableOracleFactory.sol";
import {IManageableOracle} from "silo-oracles/contracts/interfaces/IManageableOracle.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";

import {SiloOracleMock1} from "silo-oracles/test/foundry/_mocks/silo-oracles/SiloOracleMock1.sol";
import {MintableToken} from "silo-core/test/foundry/_common/MintableToken.sol";
import {MockOracleFactory} from "silo-oracles/test/foundry/manageable/common/MockOracleFactory.sol";
/*
 FOUNDRY_PROFILE=oracles forge test --mc ManageableOracleBase
 (base is abstract; run ManageableOracleBaseWithOracleTest or ManageableOracleBaseWithFactoryTest)
*/

abstract contract ManageableOracleBase is Test {
    error OracleCustomError();

    address internal owner = makeAddr("Owner");
    uint32 internal constant timelock = 1 days;
    address internal baseToken;

    IManageableOracleFactory internal factory;
    SiloOracleMock1 internal oracleMock;
    IManageableOracle internal oracle;

    function setUp() public virtual {
        oracleMock = new SiloOracleMock1();
        factory = new ManageableOracleFactory();
        baseToken = oracleMock.baseToken();

        _beforeOracleCreation();

        oracle = _createManageableOracle();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ManageableOracle_creation_emitsAllEvents
    */
    function test_ManageableOracle_creation_emitsAllEvents() public {
        vm.expectEmit(true, true, true, true, address(factory));
        emit IManageableOracleFactory.ManageableOracleCreated(_predictOracleAddress());

        vm.expectEmit(true, true, true, true);
        emit IManageableOracle.OwnershipTransferred(address(0), owner);

        vm.expectEmit(true, true, true, true);
        emit IManageableOracle.OracleUpdated(ISiloOracle(address(oracleMock)));

        vm.expectEmit(true, true, true, true);
        emit IManageableOracle.TimelockUpdated(timelock);

        _createManageableOracle();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ManageableOracle_VERSION
    */
    function test_ManageableOracle_VERSION() public view {
        assertEq(IVersioned(address(oracle)).VERSION(), "ManageableOracle 4.0.0");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_oracleVerification_revert_ZeroOracle
    */
    function test_oracleVerification_revert_ZeroOracle() public {
        vm.expectRevert(IManageableOracle.ZeroOracle.selector);
        oracle.oracleVerification(ISiloOracle(address(0)));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_oracleVerification_revert_QuoteTokenMustBeTheSame
    */
    function test_oracleVerification_revert_QuoteTokenMustBeTheSame() public {
        address wrongQuoteTokenOracle = makeAddr("wrongQuoteTokenOracle");

        vm.mockCall(
            wrongQuoteTokenOracle,
            abi.encodeWithSelector(ISiloOracle.quoteToken.selector),
            abi.encode(makeAddr("differentQuoteToken"))
        );

        vm.expectRevert(IManageableOracle.QuoteTokenMustBeTheSame.selector);
        oracle.oracleVerification(ISiloOracle(wrongQuoteTokenOracle));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_oracleVerification_revert_OracleQuoteFailed
    */
    function test_oracleVerification_revert_OracleQuoteFailed() public {
        address zeroQuoteOracle = makeAddr("zeroQuoteOracle");

        vm.mockCall(
            zeroQuoteOracle,
            abi.encodeWithSelector(ISiloOracle.quoteToken.selector),
            abi.encode(oracleMock.quoteToken())
        );

        vm.mockCall(
            zeroQuoteOracle,
            abi.encodeWithSelector(ISiloOracle.quote.selector, 10 ** 18, baseToken),
            abi.encode(uint256(0))
        );

        vm.mockCall(
            zeroQuoteOracle,
            abi.encodeWithSelector(IManageableOracle.baseToken.selector),
            abi.encode(oracle.baseToken())
        );

        vm.expectRevert(IManageableOracle.OracleQuoteFailed.selector);
        oracle.oracleVerification(ISiloOracle(zeroQuoteOracle));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_oracleVerification_revert_whenOracleReverts
    */
    function test_oracleVerification_revert_whenOracleReverts() public {
        address revertingOracle = makeAddr("revertingOracle");
        vm.mockCall(
            revertingOracle,
            abi.encodeWithSelector(ISiloOracle.quoteToken.selector),
            abi.encode(oracleMock.quoteToken())
        );
        vm.mockCall(
            revertingOracle, abi.encodeWithSelector(IManageableOracle.baseToken.selector), abi.encode(baseToken)
        );
        vm.mockCallRevert(
            revertingOracle, abi.encodeWithSelector(ISiloOracle.quote.selector, 10 ** 18, baseToken), ""
        );
        vm.expectRevert(IManageableOracle.OracleQuoteFailed.selector);
        oracle.oracleVerification(ISiloOracle(revertingOracle));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_oracleVerification_revert_propagatesCustomError
    */
    function test_oracleVerification_revert_propagatesCustomError() public {
        address customErrorOracle = makeAddr("customErrorOracle");

        vm.mockCall(
            customErrorOracle,
            abi.encodeWithSelector(ISiloOracle.quoteToken.selector),
            abi.encode(oracleMock.quoteToken())
        );
        vm.mockCallRevert(
            customErrorOracle,
            abi.encodeWithSelector(ISiloOracle.quote.selector, 10 ** 18, baseToken),
            abi.encodeWithSelector(OracleCustomError.selector)
        );
        vm.mockCall(
            customErrorOracle, abi.encodeWithSelector(IManageableOracle.baseToken.selector), abi.encode(baseToken)
        );

        vm.expectRevert(OracleCustomError.selector);
        oracle.oracleVerification(ISiloOracle(customErrorOracle));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_oracleVerification_succeeds
    */
    function test_oracleVerification_succeeds() public view {
        oracle.oracleVerification(ISiloOracle(address(oracleMock)));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_whenNotPending_proposeOracle
    */
    function test_whenNotPending_proposeOracle() public {
        SiloOracleMock1 otherOracleMock = new SiloOracleMock1();
        otherOracleMock.setQuoteToken(oracleMock.quoteToken());
        SiloOracleMock1 yetAnotherOracleMock = new SiloOracleMock1();
        yetAnotherOracleMock.setQuoteToken(oracleMock.quoteToken());

        vm.startPrank(owner);
        oracle.proposeOracle(ISiloOracle(address(otherOracleMock)));
        (address pendingOracleValue,) = oracle.pendingOracle();
        assertEq(pendingOracleValue, address(otherOracleMock), "pending oracle should be set");

        vm.expectRevert(IManageableOracle.PendingUpdate.selector);
        oracle.proposeOracle(ISiloOracle(address(yetAnotherOracleMock)));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_whenNotPending_proposeTimelock
    */
    function test_whenNotPending_proposeTimelock() public {
        uint32 newTimelock = 2 days;
        uint32 anotherTimelock = 3 days;
        vm.startPrank(owner);

        oracle.proposeTimelock(newTimelock);
        (uint192 pendingTimelockValue,) = oracle.pendingTimelock();
        assertEq(pendingTimelockValue, newTimelock, "pending timelock should be set");

        vm.expectRevert(IManageableOracle.PendingUpdate.selector);
        oracle.proposeTimelock(anotherTimelock);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_whenNotPending_proposeTransferOwnership
    */
    function test_whenNotPending_proposeTransferOwnership() public {
        address newOwner = makeAddr("NewOwner");
        address anotherNewOwner = makeAddr("AnotherNewOwner");
        vm.startPrank(owner);

        oracle.proposeTransferOwnership(newOwner);
        (address pendingOwnershipValue,) = oracle.pendingOwnership();
        assertEq(pendingOwnershipValue, newOwner, "pending ownership should be set");

        vm.expectRevert(IManageableOracle.PendingUpdate.selector);
        oracle.proposeTransferOwnership(anotherNewOwner);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_whenNotPending_proposeRenounceOwnership
    */
    function test_whenNotPending_proposeRenounceOwnership() public {
        vm.startPrank(owner);
        oracle.proposeRenounceOwnership();
        (address pendingOwnershipValue, uint64 pendingOwnershipValidAt) = oracle.pendingOwnership();
        assertEq(pendingOwnershipValue, address(0), "pending renounce: value should be zero");
        assertTrue(pendingOwnershipValidAt != 0, "pending renounce: validAt should be set");

        vm.expectRevert(IManageableOracle.PendingUpdate.selector);
        oracle.proposeRenounceOwnership();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_NoChange_proposeOracle_revert_whenSameOracle
    */
    function test_NoChange_proposeOracle_revert_whenSameOracle() public {
        vm.expectRevert(IManageableOracle.NoChange.selector);
        vm.prank(owner);
        oracle.proposeOracle(ISiloOracle(address(oracleMock)));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_NoChange_proposeTimelock_revert_whenSameTimelock
    */
    function test_NoChange_proposeTimelock_revert_whenSameTimelock() public {
        vm.expectRevert(IManageableOracle.NoChange.selector);
        vm.prank(owner);
        oracle.proposeTimelock(timelock);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_NoChange_proposeTransferOwnership_revert_whenSameOwner
    */
    function test_NoChange_proposeTransferOwnership_revert_whenSameOwner() public {
        vm.expectRevert(IManageableOracle.NoChange.selector);
        vm.prank(owner);
        oracle.proposeTransferOwnership(owner);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_onlyOwner_proposeOracle_revert_whenNotOwner
    */
    function test_onlyOwner_proposeOracle_revert_whenNotOwner() public {
        vm.expectRevert(IManageableOracle.OnlyOwner.selector);
        oracle.proposeOracle(ISiloOracle(address(oracleMock)));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_onlyOwner_proposeTimelock_revert_whenNotOwner
    */
    function test_onlyOwner_proposeTimelock_revert_whenNotOwner() public {
        vm.expectRevert(IManageableOracle.OnlyOwner.selector);
        oracle.proposeTimelock(timelock);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_onlyOwner_proposeTransferOwnership_revert_whenNotOwner
    */
    function test_onlyOwner_proposeTransferOwnership_revert_whenNotOwner() public {
        vm.expectRevert(IManageableOracle.OnlyOwner.selector);
        oracle.proposeTransferOwnership(makeAddr("NewOwner"));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_onlyOwner_proposeRenounceOwnership_revert_whenNotOwner
    */
    function test_onlyOwner_proposeRenounceOwnership_revert_whenNotOwner() public {
        vm.expectRevert(IManageableOracle.OnlyOwner.selector);
        oracle.proposeRenounceOwnership();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_onlyOwner_acceptOracle_revert_whenNotOwner
    */
    function test_onlyOwner_acceptOracle_revert_whenNotOwner() public {
        vm.expectRevert(IManageableOracle.OnlyOwner.selector);
        oracle.acceptOracle();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_onlyOwner_acceptTimelock_revert_whenNotOwner
    */
    function test_onlyOwner_acceptTimelock_revert_whenNotOwner() public {
        vm.expectRevert(IManageableOracle.OnlyOwner.selector);
        oracle.acceptTimelock();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_onlyOwner_acceptRenounceOwnership_revert_whenNotOwner
    */
    function test_onlyOwner_acceptRenounceOwnership_revert_whenNotOwner() public {
        vm.expectRevert(IManageableOracle.OnlyOwner.selector);
        oracle.acceptRenounceOwnership();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_onlyOwner_acceptOwnership_revert_whenNotOwner
    */
    function test_onlyOwner_acceptOwnership_revert_whenNotOwner() public {
        vm.prank(owner);
        oracle.proposeTransferOwnership(makeAddr("NewOwner"));

        vm.warp(block.timestamp + timelock + 1);
        vm.prank(owner);
        vm.expectRevert(IManageableOracle.OnlyOwner.selector);
        oracle.acceptOwnership();

        vm.expectRevert(IManageableOracle.OnlyOwner.selector);
        oracle.acceptOwnership();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_onlyOwner_cancelOracle_revert_whenNotOwner
    */
    function test_onlyOwner_cancelOracle_revert_whenNotOwner() public {
        vm.expectRevert(IManageableOracle.OnlyOwner.selector);
        oracle.cancelOracle();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_onlyOwner_cancelTimelock_revert_whenNotOwner
    */
    function test_onlyOwner_cancelTimelock_revert_whenNotOwner() public {
        vm.expectRevert(IManageableOracle.OnlyOwner.selector);
        oracle.cancelTimelock();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_onlyOwner_cancelTransferOwnership_revert_whenNotOwner
    */
    function test_onlyOwner_cancelTransferOwnership_revert_whenNotOwner() public {
        vm.expectRevert(IManageableOracle.OnlyOwner.selector);
        oracle.cancelTransferOwnership();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_onlyOwner_cancelRenounceOwnership_revert_whenNotOwner
    */
    function test_onlyOwner_cancelRenounceOwnership_revert_whenNotOwner() public {
        vm.expectRevert(IManageableOracle.OnlyOwner.selector);
        oracle.cancelRenounceOwnership();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_proposeOracle_acceptAfterTimelock
    */
    function test_proposeOracle_acceptAfterTimelock() public {
        SiloOracleMock1 otherOracleMock = new SiloOracleMock1();
        otherOracleMock.setQuoteToken(oracleMock.quoteToken());

        uint256 proposeTime = block.timestamp;
        vm.prank(owner);
        oracle.proposeOracle(ISiloOracle(address(otherOracleMock)));
        (address pendingOracleValue, uint64 pendingOracleValidAt) = oracle.pendingOracle();
        assertEq(pendingOracleValue, address(otherOracleMock), "invalid pendingOracle value after propose");
        assertEq(pendingOracleValidAt, proposeTime + timelock, "invalid pendingOracle validAt after propose");

        vm.prank(owner);
        vm.expectRevert(IManageableOracle.TimelockNotExpired.selector);
        oracle.acceptOracle();

        vm.warp(proposeTime + timelock - 1);
        vm.prank(owner);
        vm.expectRevert(IManageableOracle.TimelockNotExpired.selector);
        oracle.acceptOracle();

        vm.warp(proposeTime + timelock);
        assertEq(address(oracle.oracle()), address(oracleMock), "oracle should still be old before accept");
        vm.expectEmit(true, true, true, true, address(oracle));
        emit IManageableOracle.OracleUpdated(ISiloOracle(address(otherOracleMock)));
        vm.prank(owner);
        oracle.acceptOracle();

        (pendingOracleValue, pendingOracleValidAt) = oracle.pendingOracle();
        assertEq(pendingOracleValue, address(0), "pendingOracle not cleared after accept");
        assertEq(pendingOracleValidAt, 0, "pendingOracle validAt not cleared after accept");
        assertEq(address(oracle.oracle()), address(otherOracleMock), "oracle not updated after accept");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_proposeTimelock_acceptAfterTimelock
    */
    function test_proposeTimelock_acceptAfterTimelock() public {
        uint32 newTimelock = 2 days;
        uint256 proposeTime = block.timestamp;
        vm.prank(owner);
        oracle.proposeTimelock(newTimelock);
        (uint192 pendingTimelockValue, uint64 pendingTimelockValidAt) = oracle.pendingTimelock();
        assertEq(pendingTimelockValue, newTimelock, "invalid pendingTimelock value after propose");
        assertEq(pendingTimelockValidAt, proposeTime + timelock, "invalid pendingTimelock validAt after propose");

        vm.prank(owner);
        vm.expectRevert(IManageableOracle.TimelockNotExpired.selector);
        oracle.acceptTimelock();

        vm.warp(proposeTime + timelock - 1);
        vm.prank(owner);
        vm.expectRevert(IManageableOracle.TimelockNotExpired.selector);
        oracle.acceptTimelock();

        vm.warp(proposeTime + timelock);
        assertEq(oracle.timelock(), timelock, "timelock should still be old before accept");
        vm.expectEmit(true, true, true, true, address(oracle));
        emit IManageableOracle.TimelockUpdated(newTimelock);
        vm.prank(owner);
        oracle.acceptTimelock();

        (pendingTimelockValue, pendingTimelockValidAt) = oracle.pendingTimelock();
        assertEq(pendingTimelockValue, 0, "pendingTimelock not cleared after accept");
        assertEq(pendingTimelockValidAt, 0, "pendingTimelock validAt not cleared after accept");
        assertEq(oracle.timelock(), newTimelock, "timelock not updated after accept");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_proposeTransferOwnership_acceptOwnershipAfterTimelock
    */
    function test_proposeTransferOwnership_acceptOwnershipAfterTimelock() public {
        address newOwner = makeAddr("NewOwner");
        uint256 proposeTime = block.timestamp;
        vm.prank(owner);
        oracle.proposeTransferOwnership(newOwner);
        (address pendingOwnershipValue, uint64 pendingOwnershipValidAt) = oracle.pendingOwnership();
        assertEq(pendingOwnershipValue, newOwner, "invalid pendingOwnership value after propose");
        assertEq(pendingOwnershipValidAt, proposeTime + timelock, "invalid pendingOwnership validAt after propose");

        vm.prank(newOwner);
        vm.expectRevert(IManageableOracle.TimelockNotExpired.selector);
        oracle.acceptOwnership();

        vm.warp(proposeTime + timelock - 1);
        vm.prank(newOwner);
        vm.expectRevert(IManageableOracle.TimelockNotExpired.selector);
        oracle.acceptOwnership();

        vm.warp(proposeTime + timelock);
        assertEq(oracle.owner(), owner, "owner should still be old before accept");
        vm.expectEmit(true, true, true, true, address(oracle));
        emit IManageableOracle.OwnershipTransferred(owner, newOwner);
        vm.prank(newOwner);
        oracle.acceptOwnership();

        (pendingOwnershipValue, pendingOwnershipValidAt) = oracle.pendingOwnership();
        assertEq(pendingOwnershipValue, address(0), "pendingOwnership not cleared after accept");
        assertEq(pendingOwnershipValidAt, 0, "pendingOwnership validAt not cleared after accept");
        assertEq(oracle.owner(), newOwner, "owner not updated after accept");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_proposeRenounceOwnership_acceptRenounceOwnershipAfterTimelock
    */
    function test_proposeRenounceOwnership_acceptRenounceOwnershipAfterTimelock() public {
        uint256 proposeTime = block.timestamp;
        vm.prank(owner);
        oracle.proposeRenounceOwnership();
        (address pendingOwnershipValue, uint64 pendingOwnershipValidAt) = oracle.pendingOwnership();
        assertEq(pendingOwnershipValue, address(0), "invalid pendingOwnership value after propose");
        assertEq(pendingOwnershipValidAt, proposeTime + timelock, "invalid pendingOwnership validAt after propose");

        vm.prank(owner);
        vm.expectRevert(IManageableOracle.TimelockNotExpired.selector);
        oracle.acceptRenounceOwnership();

        vm.warp(proposeTime + timelock - 1);
        vm.prank(owner);
        vm.expectRevert(IManageableOracle.TimelockNotExpired.selector);
        oracle.acceptRenounceOwnership();

        vm.warp(proposeTime + timelock);
        assertEq(oracle.owner(), owner, "owner should still be set before accept renounce");
        vm.expectEmit(true, true, true, false, address(oracle));
        emit IManageableOracle.OwnershipTransferred(owner, address(0));
        vm.prank(owner);
        oracle.acceptRenounceOwnership();

        (pendingOwnershipValue, pendingOwnershipValidAt) = oracle.pendingOwnership();
        assertEq(pendingOwnershipValue, address(0), "pendingOwnership not cleared after accept");
        assertEq(pendingOwnershipValidAt, 0, "pendingOwnership validAt not cleared after accept");
        assertEq(oracle.owner(), address(0), "owner not cleared after accept renounce");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_acceptRenounceOwnership_revert_whenPendingOracleOrPendingTimelock
    */
    function test_acceptRenounceOwnership_revert_whenPendingOracleOrPendingTimelock() public {
        SiloOracleMock1 otherOracleMock = new SiloOracleMock1();
        otherOracleMock.setQuoteToken(oracleMock.quoteToken());
        uint32 newTimelock = 2 days;
        uint256 proposeTime = block.timestamp;

        vm.startPrank(owner);
        oracle.proposeRenounceOwnership();

        oracle.proposeOracle(ISiloOracle(address(otherOracleMock)));

        vm.warp(proposeTime + timelock);
        vm.expectRevert(IManageableOracle.PendingOracleUpdate.selector);
        oracle.acceptRenounceOwnership();

        oracle.proposeTimelock(newTimelock);
        vm.expectRevert(IManageableOracle.PendingOracleUpdate.selector);
        oracle.acceptRenounceOwnership();

        oracle.acceptOracle();

        vm.expectRevert(IManageableOracle.PendingTimelockUpdate.selector);
        oracle.acceptRenounceOwnership();

        oracle.cancelTimelock();

        oracle.acceptRenounceOwnership();
        assertEq(oracle.owner(), address(0), "invalid owner after accept renounce");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_cancelOracle_cancelPossibleAlways
    */
    function test_cancelOracle_cancelPossibleAlways(uint256 _time) public {
        vm.assume(_time <= 30 days);
        address oracleBeforeCancel = address(oracle.oracle());
        SiloOracleMock1 otherOracleMock = new SiloOracleMock1();
        otherOracleMock.setQuoteToken(oracleMock.quoteToken());

        vm.prank(owner);
        oracle.proposeOracle(ISiloOracle(address(otherOracleMock)));
        vm.warp(block.timestamp + _time);
        vm.expectEmit(true, false, false, false, address(oracle));
        emit IManageableOracle.OracleProposalCanceled();
        vm.prank(owner);
        oracle.cancelOracle();

        (address pendingOracleValue, uint64 pendingOracleValidAt) = oracle.pendingOracle();
        assertEq(pendingOracleValue, address(0), "pendingOracle not cleared after cancel");
        assertEq(pendingOracleValidAt, 0, "pendingOracle validAt not cleared after cancel");
        assertEq(address(oracle.oracle()), oracleBeforeCancel, "oracle value should not change after cancel");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_cancelTimelock_cancelPossibleAlways
    */
    function test_cancelTimelock_cancelPossibleAlways(uint256 _time) public {
        vm.assume(_time <= 30 days);
        uint32 timelockBeforeCancel = oracle.timelock();
        uint32 newTimelock = 2 days;
        vm.prank(owner);
        oracle.proposeTimelock(newTimelock);
        vm.warp(block.timestamp + _time);
        vm.expectEmit(true, false, false, false, address(oracle));
        emit IManageableOracle.TimelockProposalCanceled();
        vm.prank(owner);
        oracle.cancelTimelock();

        (uint192 pendingTimelockValue, uint64 pendingTimelockValidAt) = oracle.pendingTimelock();
        assertEq(pendingTimelockValue, 0, "pendingTimelock not cleared after cancel");
        assertEq(pendingTimelockValidAt, 0, "pendingTimelock validAt not cleared after cancel");
        assertEq(oracle.timelock(), timelockBeforeCancel, "timelock value should not change after cancel");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_cancelTransferOwnership_cancelPossibleAlways
    */
    function test_cancelTransferOwnership_cancelPossibleAlways(uint256 _time) public {
        vm.assume(_time <= 30 days);
        address ownerBeforeCancel = oracle.owner();
        address newOwner = makeAddr("NewOwner");
        vm.prank(owner);
        oracle.proposeTransferOwnership(newOwner);
        vm.warp(block.timestamp + _time);
        vm.expectEmit(true, false, false, false, address(oracle));
        emit IManageableOracle.OwnershipTransferCanceled();
        vm.prank(owner);
        oracle.cancelTransferOwnership();

        (address pendingOwnershipValue, uint64 pendingOwnershipValidAt) = oracle.pendingOwnership();
        assertEq(pendingOwnershipValue, address(0), "pendingOwnership not cleared after cancel");
        assertEq(pendingOwnershipValidAt, 0, "pendingOwnership validAt not cleared after cancel");
        assertEq(oracle.owner(), ownerBeforeCancel, "owner value should not change after cancel");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_cancelRenounceOwnership_cancelPossibleAlways
    */
    function test_cancelRenounceOwnership_cancelPossibleAlways(uint256 _time) public {
        vm.assume(_time <= 30 days);
        address ownerBeforeCancel = oracle.owner();
        vm.prank(owner);
        oracle.proposeRenounceOwnership();
        vm.warp(block.timestamp + _time);
        vm.expectEmit(true, false, false, false, address(oracle));
        emit IManageableOracle.OwnershipRenounceCanceled();
        vm.prank(owner);
        oracle.cancelRenounceOwnership();

        (address pendingOwnershipValue, uint64 pendingOwnershipValidAt) = oracle.pendingOwnership();
        assertEq(pendingOwnershipValue, address(0), "pendingOwnership not cleared after cancel");
        assertEq(pendingOwnershipValidAt, 0, "pendingOwnership validAt not cleared after cancel");
        assertEq(oracle.owner(), ownerBeforeCancel, "owner value should not change after cancel");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_cancelOracle_revert_whenNothingProposed
    */
    function test_cancelOracle_revert_whenNothingProposed() public {
        vm.expectRevert(IManageableOracle.NoPendingUpdateToCancel.selector);
        vm.prank(owner);
        oracle.cancelOracle();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_cancelTimelock_revert_whenNothingProposed
    */
    function test_cancelTimelock_revert_whenNothingProposed() public {
        vm.expectRevert(IManageableOracle.NoPendingUpdateToCancel.selector);
        vm.prank(owner);
        oracle.cancelTimelock();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_cancelTransferOwnership_revert_whenNothingProposed
    */
    function test_cancelTransferOwnership_revert_whenNothingProposed() public {
        vm.expectRevert(IManageableOracle.NoPendingUpdateToCancel.selector);
        vm.prank(owner);
        oracle.cancelTransferOwnership();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_cancelRenounceOwnership_revert_whenNothingProposed
    */
    function test_cancelRenounceOwnership_revert_whenNothingProposed() public {
        vm.expectRevert(IManageableOracle.NoPendingUpdateToCancel.selector);
        vm.prank(owner);
        oracle.cancelRenounceOwnership();
    }

    function _beforeOracleCreation() internal virtual {
        vm.mockCall(baseToken, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));

        vm.mockCall(baseToken, abi.encodeWithSelector(IERC20Metadata.symbol.selector), abi.encode("BASE_TOKEN"));
    }

    function _predictOracleAddress() internal view virtual returns (address) {
        return factory.predictAddress(address(this), bytes32(0));
    }

    /// @return manageableOracle Created oracle (via create with oracle or create with factory)
    function _createManageableOracle() internal virtual returns (IManageableOracle manageableOracle);
}
