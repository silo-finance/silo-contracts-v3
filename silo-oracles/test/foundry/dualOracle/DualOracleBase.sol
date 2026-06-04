// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";
import {OwnableUpgradeable} from "openzeppelin5-upgradeable/access/OwnableUpgradeable.sol";
import {Pausable} from "openzeppelin5/utils/Pausable.sol";
import {PausableUpgradeable} from "openzeppelin5-upgradeable/utils/PausableUpgradeable.sol";

import {DualOracleFactory} from "silo-oracles/contracts/dualOracle/DualOracleFactory.sol";
import {DualOracle} from "silo-oracles/contracts/dualOracle/DualOracle.sol";
import {IDualOracle} from "silo-oracles/contracts/interfaces/IDualOracle.sol";
import {IDualOracleFactory} from "silo-oracles/contracts/interfaces/IDualOracleFactory.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";
import {IERC20Metadata} from "silo-oracles/test/foundry/interfaces/IERC20Metadata.sol";
import {SiloOracleMock1} from "silo-oracles/test/foundry/_mocks/silo-oracles/SiloOracleMock1.sol";

/*
 FOUNDRY_PROFILE=oracles forge test --mc DualOracleBase
 (abstract — run DualOracleBaseWithOracleTest or DualOracleBaseWithFactoryTest)
*/
abstract contract DualOracleBase is Test {
    uint256 internal constant LOWER_BOUND = 0.5e18;
    uint256 internal constant UPPER_BOUND = 2e18;
    uint32 internal constant TIMELOCK = 1 days;

    address internal owner = makeAddr("Owner");
    address internal nonOwner = makeAddr("NonOwner");
    address internal baseToken;

    DualOracleFactory internal factory;
    SiloOracleMock1 internal oracleMock;
    IDualOracle internal oracle;

    function setUp() public virtual {
        oracleMock = new SiloOracleMock1();
        factory = new DualOracleFactory();
        baseToken = oracleMock.baseToken();

        _beforeOracleCreation();

        oracle = _createDualOracle();
    }

    // ─── creation ─────────────────────────────────────────────────────────────

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_DualOracle_creation_emitsEvents
    */
    function test_DualOracle_creation_emitsEvents() public {
        vm.expectEmit(true, false, false, false, address(factory));
        emit IDualOracleFactory.DualOracleCreated(_predictOracleAddress());

        _createDualOracle();
    }

    // ─── VERSION ──────────────────────────────────────────────────────────────

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_DualOracle_VERSION
    */
    function test_DualOracle_VERSION() public view {
        assertEq(IVersioned(address(oracle)).VERSION(), "DualOracle 4.23.0");
    }

    // ─── baseToken ────────────────────────────────────────────────────────────

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_DualOracle_baseToken
    */
    function test_DualOracle_baseToken() public view {
        assertEq(oracle.baseToken(), oracleMock.baseToken());
    }

    // ─── isOverrideActive ─────────────────────────────────────────────────────

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_isOverrideActive_false_initially
    */
    function test_isOverrideActive_false_initially() public view {
        assertFalse(oracle.isOverrideActive(), "override should not be active initially");
        assertEq(oracle.overrideValidAt(), 0, "overrideValidAt should be zero initially");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_isOverrideActive_false_beforeTimelockExpiry
    */
    function test_isOverrideActive_false_beforeTimelockExpiry() public {
        vm.prank(owner);
        oracle.setManualPrice(1e18);

        vm.warp(block.timestamp + TIMELOCK - 1);
        assertFalse(oracle.isOverrideActive(), "override should not be active before timelock expiry");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_isOverrideActive_true_atTimelockExpiry
    */
    function test_isOverrideActive_true_atTimelockExpiry() public {
        vm.prank(owner);
        oracle.setManualPrice(1e18);

        vm.warp(block.timestamp + TIMELOCK);
        assertTrue(oracle.isOverrideActive(), "override should be active at timelock expiry");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_isOverrideActive_true_afterTimelockExpiry
    */
    function test_isOverrideActive_true_afterTimelockExpiry() public {
        vm.prank(owner);
        oracle.setManualPrice(1e18);

        vm.warp(block.timestamp + TIMELOCK + 100);
        assertTrue(oracle.isOverrideActive(), "override should be active after timelock expiry");
    }

    // ─── pause ────────────────────────────────────────────────────────────────

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_pause_revert_whenNotOwner
    */
    function test_pause_revert_whenNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        oracle.pause();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_pause_success_setsState_emitsEvent
    */
    function test_pause_success_setsState_emitsEvent() public {
        assertFalse(DualOracle(address(oracle)).paused(), "should not be paused initially");

        vm.expectEmit(true, false, false, false, address(oracle));
        emit Pausable.Paused(owner);

        vm.prank(owner);
        oracle.pause();

        assertTrue(DualOracle(address(oracle)).paused(), "should be paused after pause()");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_pause_revert_whenAlreadyPaused
    */
    function test_pause_revert_whenAlreadyPaused() public {
        vm.startPrank(owner);
        oracle.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        oracle.pause();
        vm.stopPrank();
    }

    // ─── unpause ──────────────────────────────────────────────────────────────

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_unpause_revert_whenNotOwner
    */
    function test_unpause_revert_whenNotOwner() public {
        vm.prank(owner);
        oracle.pause();

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        oracle.unpause();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_unpause_revert_whenNotPaused
    */
    function test_unpause_revert_whenNotPaused() public {
        vm.prank(owner);
        vm.expectRevert(Pausable.ExpectedPause.selector);
        oracle.unpause();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_unpause_success_clearsState_emitsEvent
    */
    function test_unpause_success_clearsState_emitsEvent() public {
        vm.prank(owner);
        oracle.pause();

        vm.expectEmit(true, false, false, false, address(oracle));
        emit Pausable.Unpaused(owner);

        vm.prank(owner);
        oracle.unpause();

        assertFalse(DualOracle(address(oracle)).paused(), "should not be paused after unpause()");
    }

    // ─── setManualPrice ───────────────────────────────────────────────────────

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_setManualPrice_revert_whenNotOwner
    */
    function test_setManualPrice_revert_whenNotOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        oracle.setManualPrice(1e18);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_setManualPrice_revert_PriceNotChanged_whenBothZero
    */
    function test_setManualPrice_revert_PriceNotChanged_whenBothZero() public {
        assertEq(oracle.manualPrice(), 0, "manualPrice should start at 0");
        vm.prank(owner);
        vm.expectRevert(IDualOracle.PriceNotChanged.selector);
        oracle.setManualPrice(0);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_setManualPrice_revert_PriceNotChanged_whenSameNonzero
    */
    function test_setManualPrice_revert_PriceNotChanged_whenSameNonzero() public {
        vm.startPrank(owner);
        oracle.setManualPrice(1e18);

        vm.expectRevert(IDualOracle.PriceNotChanged.selector);
        oracle.setManualPrice(1e18);
        vm.stopPrank();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_setManualPrice_revert_PriceBelowLowerBound
    */
    function test_setManualPrice_revert_PriceBelowLowerBound() public {
        vm.prank(owner);
        vm.expectRevert(IDualOracle.PriceBelowLowerBound.selector);
        oracle.setManualPrice(LOWER_BOUND - 1);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_setManualPrice_revert_PriceAboveUpperBound
    */
    function test_setManualPrice_revert_PriceAboveUpperBound() public {
        vm.prank(owner);
        vm.expectRevert(IDualOracle.PriceAboveUpperBound.selector);
        oracle.setManualPrice(UPPER_BOUND + 1);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_setManualPrice_nonzero_storesPrice_startsTimelock_emitsEvent
    */
    function test_setManualPrice_nonzero_storesPrice_startsTimelock_emitsEvent() public {
        uint256 price = 1e18;
        uint64 expectedValidAt = SafeCast.toUint64(block.timestamp + TIMELOCK);

        vm.expectEmit(true, false, false, true, address(oracle));
        emit IDualOracle.ManualPriceUpdated(price, expectedValidAt);

        vm.prank(owner);
        oracle.setManualPrice(price);

        assertEq(oracle.manualPrice(), price, "manualPrice not stored");
        assertEq(oracle.overrideValidAt(), expectedValidAt, "overrideValidAt set incorrectly");
        assertFalse(oracle.isOverrideActive(), "override should not be active immediately");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_setManualPrice_atLowerBound_succeeds
    */
    function test_setManualPrice_atLowerBound_succeeds() public {
        vm.prank(owner);
        oracle.setManualPrice(LOWER_BOUND);
        assertEq(oracle.manualPrice(), LOWER_BOUND);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_setManualPrice_atUpperBound_succeeds
    */
    function test_setManualPrice_atUpperBound_succeeds() public {
        vm.prank(owner);
        oracle.setManualPrice(UPPER_BOUND);
        assertEq(oracle.manualPrice(), UPPER_BOUND);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_setManualPrice_updateWhileActive_doesNotRestartTimelock
    */
    function test_setManualPrice_updateWhileActive_doesNotRestartTimelock() public {
        vm.prank(owner);
        oracle.setManualPrice(1e18);

        uint64 firstValidAt = oracle.overrideValidAt();

        vm.warp(block.timestamp + TIMELOCK);
        assertTrue(oracle.isOverrideActive(), "override should be active");

        // update price while override is already active — should NOT emit OverrideEnabled
        vm.prank(owner);
        oracle.setManualPrice(1.1e18);

        assertEq(oracle.manualPrice(), 1.1e18, "manualPrice should update");
        assertEq(oracle.overrideValidAt(), firstValidAt, "overrideValidAt must not change when already active");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_setManualPrice_updateWhileActive_emitsEventWithUnchangedValidAt
    */
    function test_setManualPrice_updateWhileActive_emitsEventWithUnchangedValidAt() public {
        vm.prank(owner);
        oracle.setManualPrice(1e18);
        vm.warp(block.timestamp + TIMELOCK);

        uint64 firstValidAt = oracle.overrideValidAt();
        assertTrue(oracle.isOverrideActive(), "override should be active");

        vm.expectEmit(true, false, false, true, address(oracle));
        emit IDualOracle.ManualPriceUpdated(1.1e18, firstValidAt);

        vm.prank(owner);
        oracle.setManualPrice(1.1e18);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_setManualPrice_zero_disablesOverride_clears_state_emitsEvents
    */
    function test_setManualPrice_zero_disablesOverride_clears_state_emitsEvents() public {
        vm.prank(owner);
        oracle.setManualPrice(1e18);
        assertFalse(oracle.isOverrideActive());

        vm.expectEmit(true, false, false, true, address(oracle));
        emit IDualOracle.ManualPriceUpdated(0, 0);

        vm.prank(owner);
        oracle.setManualPrice(0);

        assertEq(oracle.manualPrice(), 0, "manualPrice should be cleared");
        assertEq(oracle.overrideValidAt(), 0, "overrideValidAt should be cleared");
        assertFalse(oracle.isOverrideActive(), "override should be disabled");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_setManualPrice_zero_disablesOverride_whileActive
    */
    function test_setManualPrice_zero_disablesOverride_whileActive() public {
        vm.prank(owner);
        oracle.setManualPrice(1e18);
        vm.warp(block.timestamp + TIMELOCK);
        assertTrue(oracle.isOverrideActive(), "override should be active");

        vm.prank(owner);
        oracle.setManualPrice(0);

        assertEq(oracle.manualPrice(), 0);
        assertEq(oracle.overrideValidAt(), 0);
        assertFalse(oracle.isOverrideActive());
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_setManualPrice_canReactivateAfterDisable
    */
    function test_setManualPrice_canReactivateAfterDisable() public {
        vm.startPrank(owner);
        oracle.setManualPrice(1e18);
        vm.warp(block.timestamp + TIMELOCK);
        oracle.setManualPrice(0);

        uint256 reactivateTime = block.timestamp;
        oracle.setManualPrice(1.5e18);
        vm.stopPrank();

        assertEq(oracle.overrideValidAt(), reactivateTime + TIMELOCK, "fresh timelock should start");
        assertFalse(oracle.isOverrideActive(), "should not be immediately active");

        vm.warp(reactivateTime + TIMELOCK);
        assertTrue(oracle.isOverrideActive());
    }

    // ─── quote ────────────────────────────────────────────────────────────────

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_quote_revert_whenPaused
    */
    function test_quote_revert_whenPaused() public {
        vm.prank(owner);
        oracle.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        oracle.quote(1e18, baseToken);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_quote_delegatesToPrimary_whenOverrideNotActive
    */
    function test_quote_delegatesToPrimary_whenOverrideNotActive() public view {
        assertFalse(oracle.isOverrideActive());
        assertEq(oracle.quote(1e18, baseToken), oracleMock.price(), "should delegate to primary oracle");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_quote_delegatesToPrimary_duringTimelockPending
    */
    function test_quote_delegatesToPrimary_duringTimelockPending() public {
        vm.prank(owner);
        oracle.setManualPrice(1e18);

        // warp to just before expiry
        vm.warp(block.timestamp + TIMELOCK - 1);
        assertFalse(oracle.isOverrideActive());

        assertEq(oracle.quote(1e18, baseToken), oracleMock.price(), "should use primary oracle before timelock");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_quote_returnsManualPrice_whenOverrideActive
    */
    function test_quote_returnsManualPrice_whenOverrideActive() public {
        uint256 manualPrice = 1e18;
        vm.prank(owner);
        oracle.setManualPrice(manualPrice);

        vm.warp(block.timestamp + TIMELOCK);
        assertTrue(oracle.isOverrideActive());

        assertEq(oracle.quote(1e18, baseToken), manualPrice, "should return manualPrice when override active");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_quote_returnsUpdatedManualPrice_whenOverrideActive
    */
    function test_quote_returnsUpdatedManualPrice_whenOverrideActive() public {
        vm.prank(owner);
        oracle.setManualPrice(1e18);
        vm.warp(block.timestamp + TIMELOCK);

        vm.prank(owner);
        oracle.setManualPrice(1.8e18);

        assertEq(oracle.quote(1e18, baseToken), 1.8e18, "should return updated manualPrice");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_quote_returnsPrimaryOracle_afterOverrideDisabled
    */
    function test_quote_returnsPrimaryOracle_afterOverrideDisabled() public {
        vm.prank(owner);
        oracle.setManualPrice(1e18);
        vm.warp(block.timestamp + TIMELOCK);

        vm.prank(owner);
        oracle.setManualPrice(0);

        assertFalse(oracle.isOverrideActive());
        assertEq(oracle.quote(1e18, baseToken), oracleMock.price(), "should use primary oracle after override disabled");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_quote_pause_hasPriorityOverOverride
    */
    function test_quote_pause_hasPriorityOverOverride() public {
        vm.prank(owner);
        oracle.setManualPrice(1e18);
        vm.warp(block.timestamp + TIMELOCK);
        assertTrue(oracle.isOverrideActive());

        vm.prank(owner);
        oracle.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        oracle.quote(1e18, baseToken);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_quote_resumesAfterUnpause_withOverrideActive
    */
    function test_quote_resumesAfterUnpause_withOverrideActive() public {
        uint256 manualPrice = 1e18;
        vm.startPrank(owner);
        oracle.setManualPrice(manualPrice);
        vm.warp(block.timestamp + TIMELOCK);
        oracle.pause();
        oracle.unpause();
        vm.stopPrank();

        assertEq(oracle.quote(1e18, baseToken), manualPrice, "should return manualPrice after unpause with override active");
    }

    // ─── beforeQuote ──────────────────────────────────────────────────────────

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_beforeQuote_forwardsToPrimaryOracle
    */
    function test_beforeQuote_forwardsToPrimaryOracle() public {
        vm.expectEmit(true, false, false, false, address(oracleMock));
        emit SiloOracleMock1.BeforeQuoteSiloOracleMock1();
        oracle.beforeQuote(baseToken);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_beforeQuote_revert_whenPaused
    */
    function test_beforeQuote_revert_whenPaused() public {
        vm.prank(owner);
        oracle.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        oracle.beforeQuote(baseToken);
    }

    // ─── latestRoundData (Aggregator compatibility) ───────────────────────────

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_latestRoundData_normalMode
    */
    function test_latestRoundData_normalMode() public view {
        (, int256 answer,,,) = DualOracle(address(oracle)).latestRoundData();
        assertEq(answer, SafeCast.toInt256(oracleMock.price()), "answer should match primary oracle price");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_latestRoundData_overrideMode
    */
    function test_latestRoundData_overrideMode() public {
        uint256 manualPrice = 1e18;
        vm.prank(owner);
        oracle.setManualPrice(manualPrice);
        vm.warp(block.timestamp + TIMELOCK);

        (, int256 answer,,,) = DualOracle(address(oracle)).latestRoundData();
        assertEq(answer, SafeCast.toInt256(manualPrice), "answer should return manualPrice in override mode");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_latestRoundData_revert_whenPaused
    */
    function test_latestRoundData_revert_whenPaused() public {
        vm.prank(owner);
        oracle.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        DualOracle(address(oracle)).latestRoundData();
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_aggregator_decimals
    */
    function test_aggregator_decimals() public view {
        assertEq(DualOracle(address(oracle)).decimals(), 18);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_aggregator_description
    */
    function test_aggregator_description() public view {
        assertEq(DualOracle(address(oracle)).description(), "Silo Oracle");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_aggregator_version
    */
    function test_aggregator_version() public view {
        assertEq(DualOracle(address(oracle)).version(), 1);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_aggregator_getRoundData_returnsZeros
    */
    function test_aggregator_getRoundData_returnsZeros() public view {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            DualOracle(address(oracle)).getRoundData(0);
        assertEq(roundId, 0);
        assertEq(answer, 0);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(answeredInRound, 0);
    }

    // ─── ownership (Ownable2StepUpgradeable) ──────────────────────────────────

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ownership_initialOwner
    */
    function test_ownership_initialOwner() public view {
        assertEq(DualOracle(address(oracle)).owner(), owner);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ownership_transferOwnership_onlyOwner
    */
    function test_ownership_transferOwnership_onlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        DualOracle(address(oracle)).transferOwnership(makeAddr("NewOwner"));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ownership_transferAndAccept
    */
    function test_ownership_transferAndAccept() public {
        address newOwner = makeAddr("NewOwner");

        vm.prank(owner);
        DualOracle(address(oracle)).transferOwnership(newOwner);

        assertEq(DualOracle(address(oracle)).owner(), owner, "owner should not change until accepted");
        assertEq(DualOracle(address(oracle)).pendingOwner(), newOwner, "pendingOwner should be set");

        vm.prank(newOwner);
        DualOracle(address(oracle)).acceptOwnership();

        assertEq(DualOracle(address(oracle)).owner(), newOwner, "owner should be updated after accept");
        assertEq(DualOracle(address(oracle)).pendingOwner(), address(0), "pendingOwner should be cleared");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ownership_acceptOwnership_revert_whenNotPendingOwner
    */
    function test_ownership_acceptOwnership_revert_whenNotPendingOwner() public {
        address newOwner = makeAddr("NewOwner");

        vm.prank(owner);
        DualOracle(address(oracle)).transferOwnership(newOwner);

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, nonOwner));
        DualOracle(address(oracle)).acceptOwnership();
    }

    // ─── immutable config getters ─────────────────────────────────────────────

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_getters_postInit
    */
    function test_getters_postInit() public view {
        assertEq(address(oracle.oracle()), address(oracleMock), "oracle mismatch");
        assertEq(oracle.quoteToken(), oracleMock.quoteToken(), "quoteToken mismatch");
        assertEq(oracle.baseToken(), oracleMock.baseToken(), "baseToken mismatch");
        assertEq(oracle.baseTokenDecimals(), 18, "baseTokenDecimals mismatch");
        assertEq(oracle.timelock(), TIMELOCK, "timelock mismatch");
        assertEq(oracle.lowerPriceBound(), LOWER_BOUND, "lowerPriceBound mismatch");
        assertEq(oracle.upperPriceBound(), UPPER_BOUND, "upperPriceBound mismatch");
        assertEq(oracle.manualPrice(), 0, "manualPrice should be zero initially");
        assertEq(oracle.overrideValidAt(), 0, "overrideValidAt should be zero initially");
    }

    // ─── helpers ──────────────────────────────────────────────────────────────

    function _beforeOracleCreation() internal virtual {
        vm.mockCall(baseToken, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));
    }

    function _predictOracleAddress() internal view virtual returns (address) {
        return factory.predictAddress(address(this), bytes32(0));
    }

    function _createDualOracle() internal virtual returns (IDualOracle dualOracle);
}
