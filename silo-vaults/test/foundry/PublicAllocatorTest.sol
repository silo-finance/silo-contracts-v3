// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {ErrorsLib} from "../../contracts/libraries/ErrorsLib.sol";
import {EventsLib} from "../../contracts/libraries/EventsLib.sol";
import {PublicAllocator, FlowCapsConfig, Withdrawal, FlowCaps} from "../../contracts/PublicAllocator.sol";
import {MarketAllocation} from "../../contracts/interfaces/ISiloVault.sol";
import {IPublicAllocator, MAX_SETTABLE_FLOW_CAP} from "../../contracts/interfaces/IPublicAllocator.sol";

import {IntegrationTest} from "./helpers/IntegrationTest.sol";

uint256 constant CAP2 = 100e18;
uint256 constant INITIAL_DEPOSIT = 4 * CAP2;

contract CantReceive {
    receive() external payable {
        require(false, "cannot receive");
    }
}

// Withdrawal sorting snippet
library SortWithdrawals {
    // Sorts withdrawals in-place using gnome sort.
    // Does not detect duplicates.
    // The sort will not be in-place if you pass a storage array.

    function sort(Withdrawal[] memory ws) internal pure returns (Withdrawal[] memory) {
        uint256 i;
        while (i < ws.length) {
            if (i == 0 || address(ws[i].market) >= address(ws[i - 1].market)) {
                i++;
            } else {
                (ws[i], ws[i - 1]) = (ws[i - 1], ws[i]);
                i--;
            }
        }
        return ws;
    }
}


/*
 FOUNDRY_PROFILE=vaults_tests forge test --ffi --mc PublicAllocatorTest -vvv
*/
contract PublicAllocatorTest is IntegrationTest {
    IPublicAllocator public publicAllocator;
    Withdrawal[] internal withdrawals;
    FlowCapsConfig[] internal flowCaps;

    using SortWithdrawals for Withdrawal[];

    function setUp() public override {
        super.setUp();

        publicAllocator = IPublicAllocator(address(new PublicAllocator()));
        vm.prank(OWNER);
        vault.setIsAllocator(address(publicAllocator), true);

        vm.prank(SUPPLIER);
        vault.deposit(INITIAL_DEPOSIT, ONBEHALF);

        _setCap(allMarkets[0], CAP2);
        _sortSupplyQueueIdleLast();
    }

    function testAdmin() public view {
        assertEq(publicAllocator.admin(vault), address(0));
    }

    function testSetAdmin() public {
        vm.prank(OWNER);
        publicAllocator.setAdmin(vault, address(1));
        assertEq(publicAllocator.admin(vault), address(1));
    }

    function testSetAdminByAdmin(address sender, address newAdmin) public {
        vm.assume(publicAllocator.admin(vault) != sender);
        vm.assume(sender != newAdmin);
        vm.prank(OWNER);
        publicAllocator.setAdmin(vault, sender);
        vm.prank(sender);
        publicAllocator.setAdmin(vault, newAdmin);
        assertEq(publicAllocator.admin(vault), newAdmin);
    }

    function testSetAdminAlreadySet() public {
        vm.expectRevert(ErrorsLib.AlreadySet.selector);
        vm.prank(OWNER);
        publicAllocator.setAdmin(vault, address(0));
    }

    function testSetAdminAccessFail(address sender, address newAdmin) public {
        vm.assume(sender != OWNER);
        vm.assume(publicAllocator.admin(vault) != sender);
        vm.assume(publicAllocator.admin(vault) != newAdmin);

        vm.expectRevert(ErrorsLib.NotAdminNorVaultOwner.selector);
        vm.prank(sender);
        publicAllocator.setAdmin(vault, newAdmin);
    }

    function testReallocateCapZeroOutflowByDefault(uint128 flow) public {
        flow = uint128(bound(flow, 1, CAP2));
        flowCaps.push(FlowCapsConfig({market: allMarkets[0], caps: FlowCaps({maxIn: MAX_SETTABLE_FLOW_CAP, maxOut: 0}})));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);
        withdrawals.push(Withdrawal({market: idleMarket, amount: flow}));
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.MaxOutflowExceeded.selector, idleMarket));
        publicAllocator.reallocateTo(vault, withdrawals, allMarkets[0]);
    }

    function testReallocateCapZeroInflowByDefault(uint128 flow) public {
        flow = uint128(bound(flow, 1, CAP2));
        deal(address(loanToken), address(vault), flow);
        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: 0, maxOut: MAX_SETTABLE_FLOW_CAP}})));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);
        withdrawals.push(Withdrawal({market: idleMarket, amount: flow}));
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.MaxInflowExceeded.selector, allMarkets[0]));
        publicAllocator.reallocateTo(vault, withdrawals, allMarkets[0]);
    }

    function testConfigureFlowAccessFail(address sender) public {
        vm.assume(sender != OWNER);
        vm.assume(publicAllocator.admin(vault) != sender);

        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: 0, maxOut: 0}})));

        vm.prank(sender);
        vm.expectRevert(ErrorsLib.NotAdminNorVaultOwner.selector);
        publicAllocator.setFlowCaps(vault, flowCaps);
    }

    function testTransferFeeAccessFail(address sender, address payable recipient) public {
        vm.assume(sender != OWNER);
        vm.assume(publicAllocator.admin(vault) != sender);
        vm.prank(sender);
        vm.expectRevert(ErrorsLib.NotAdminNorVaultOwner.selector);
        publicAllocator.transferFee(vault, recipient);
    }

    function testSetFeeAccessFail(address sender, uint256 fee) public {
        vm.assume(sender != OWNER);
        vm.assume(publicAllocator.admin(vault) != sender);
        vm.prank(sender);
        vm.expectRevert(ErrorsLib.NotAdminNorVaultOwner.selector);
        publicAllocator.setFee(vault, fee);
    }

    function testSetFee(uint256 fee) public {
        vm.assume(fee != publicAllocator.fee(vault));
        vm.prank(OWNER);
        vm.expectEmit(address(publicAllocator));
        emit EventsLib.SetFee(OWNER, vault, fee);
        publicAllocator.setFee(vault, fee);
        assertEq(publicAllocator.fee(vault), fee);
    }

    function testSetFeeByAdmin(uint256 fee, address sender) public {
        vm.assume(publicAllocator.admin(vault) != sender);
        vm.assume(fee != publicAllocator.fee(vault));
        vm.prank(OWNER);
        publicAllocator.setAdmin(vault, sender);
        vm.prank(sender);
        vm.expectEmit(address(publicAllocator));
        emit EventsLib.SetFee(sender, vault, fee);
        publicAllocator.setFee(vault, fee);
        assertEq(publicAllocator.fee(vault), fee);
    }

    function testSetFeeAlreadySet(uint256 fee) public {
        vm.assume(fee != publicAllocator.fee(vault));
        vm.prank(OWNER);
        publicAllocator.setFee(vault, fee);
        vm.prank(OWNER);
        vm.expectRevert(ErrorsLib.AlreadySet.selector);
        publicAllocator.setFee(vault, fee);
    }

    function testSetFlowCaps(uint128 in0, uint128 out0, uint128 in1, uint128 out1) public {
        in0 = uint128(bound(in0, 0, MAX_SETTABLE_FLOW_CAP));
        out0 = uint128(bound(out0, 0, MAX_SETTABLE_FLOW_CAP));
        in1 = uint128(bound(in1, 0, MAX_SETTABLE_FLOW_CAP));
        out1 = uint128(bound(out1, 0, MAX_SETTABLE_FLOW_CAP));

        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: in0, maxOut: out0}})));
        flowCaps.push(FlowCapsConfig({market: allMarkets[0], caps: FlowCaps({maxIn: in1, maxOut: out1}})));

        vm.expectEmit(address(publicAllocator));
        emit EventsLib.SetFlowCaps(OWNER, vault, flowCaps);

        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);

        FlowCaps memory flowCap;
        flowCap = publicAllocator.flowCaps(vault, idleMarket);
        assertEq(flowCap.maxIn, in0);
        assertEq(flowCap.maxOut, out0);

        flowCap = publicAllocator.flowCaps(vault, allMarkets[0]);
        assertEq(flowCap.maxIn, in1);
        assertEq(flowCap.maxOut, out1);
    }

    function testSetFlowCapsByAdmin(uint128 in0, uint128 out0, uint128 in1, uint128 out1, address sender) public {
        vm.assume(publicAllocator.admin(vault) != sender);
        in0 = uint128(bound(in0, 0, MAX_SETTABLE_FLOW_CAP));
        out0 = uint128(bound(out0, 0, MAX_SETTABLE_FLOW_CAP));
        in1 = uint128(bound(in1, 0, MAX_SETTABLE_FLOW_CAP));
        out1 = uint128(bound(out1, 0, MAX_SETTABLE_FLOW_CAP));

        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: in0, maxOut: out0}})));
        flowCaps.push(FlowCapsConfig({market: allMarkets[0], caps: FlowCaps({maxIn: in1, maxOut: out1}})));

        vm.prank(OWNER);
        publicAllocator.setAdmin(vault, sender);

        vm.expectEmit(address(publicAllocator));
        emit EventsLib.SetFlowCaps(sender, vault, flowCaps);

        vm.prank(sender);
        publicAllocator.setFlowCaps(vault, flowCaps);

        FlowCaps memory flowCap;
        flowCap = publicAllocator.flowCaps(vault, idleMarket);
        assertEq(flowCap.maxIn, in0);
        assertEq(flowCap.maxOut, out0);

        flowCap = publicAllocator.flowCaps(vault, allMarkets[0]);
        assertEq(flowCap.maxIn, in1);
        assertEq(flowCap.maxOut, out1);
    }

    function testPublicReallocateEvent(uint128 flow, address sender) public {
        flow = uint128(bound(flow, 1, CAP2 / 2));

        // Prepare public reallocation from 2 markets to 1
        _setCap(allMarkets[1], CAP2);

        MarketAllocation[] memory allocations = new MarketAllocation[](2);
        allocations[0] = MarketAllocation({market: idleMarket, assets: INITIAL_DEPOSIT - flow});
        allocations[1] = MarketAllocation({market: allMarkets[1], assets: flow});
        vm.prank(OWNER);
        vault.reallocate(allocations);

        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: 0, maxOut: flow}})));
        flowCaps.push(FlowCapsConfig({market: allMarkets[1], caps: FlowCaps({maxIn: 0, maxOut: flow}})));
        flowCaps.push(FlowCapsConfig({market: allMarkets[0], caps: FlowCaps({maxIn: 2 * flow, maxOut: 0}})));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);

        withdrawals.push(Withdrawal({market: idleMarket, amount: flow}));
        withdrawals.push(Withdrawal({market: allMarkets[1], amount: flow}));

        vm.expectEmit(address(publicAllocator));
        emit EventsLib.PublicWithdrawal(sender, vault, idleMarket, flow);
        emit EventsLib.PublicWithdrawal(sender, vault, allMarkets[1], flow);
        emit EventsLib.PublicReallocateTo(sender, vault, allMarkets[0], 2 * flow);

        vm.prank(sender);
        publicAllocator.reallocateTo(vault, withdrawals.sort(), allMarkets[0]);
    }

    function testReallocateNetting(uint128 flow) public {
        flow = uint128(bound(flow, 1, CAP2));

        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: 0, maxOut: flow}})));
        flowCaps.push(FlowCapsConfig({market: allMarkets[0], caps: FlowCaps({maxIn: flow, maxOut: 0}})));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);

        withdrawals.push(Withdrawal({market: idleMarket, amount: flow}));
        publicAllocator.reallocateTo(vault, withdrawals, allMarkets[0]);

        delete withdrawals;
        withdrawals.push(Withdrawal({market: allMarkets[0], amount: flow}));
        publicAllocator.reallocateTo(vault, withdrawals, idleMarket);
    }

    function testReallocateReset(uint128 flow) public {
        flow = uint128(bound(flow, 1, CAP2 / 2));

        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: 0, maxOut: flow}})));
        flowCaps.push(FlowCapsConfig({market: allMarkets[0], caps: FlowCaps({maxIn: flow, maxOut: 0}})));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);

        withdrawals.push(Withdrawal({market: idleMarket, amount: flow}));
        publicAllocator.reallocateTo(vault, withdrawals, allMarkets[0]);

        delete flowCaps;
        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: 0, maxOut: flow}})));
        flowCaps.push(FlowCapsConfig({market: allMarkets[0], caps: FlowCaps({maxIn: flow, maxOut: 0}})));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);

        delete withdrawals;

        withdrawals.push(Withdrawal({market: idleMarket, amount: flow}));
        publicAllocator.reallocateTo(vault, withdrawals, allMarkets[0]);
    }

    function testFeeAmountSuccess(uint256 requiredFee) public {
        vm.assume(requiredFee != publicAllocator.fee(vault));
        vm.prank(OWNER);
        publicAllocator.setFee(vault, requiredFee);

        vm.deal(address(this), requiredFee);

        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: 0, maxOut: 1 ether}})));
        flowCaps.push(FlowCapsConfig({market: allMarkets[0], caps: FlowCaps({maxIn: 1 ether, maxOut: 0}})));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);
        withdrawals.push(Withdrawal({market: idleMarket, amount: 1 ether}));

        publicAllocator.reallocateTo{value: requiredFee}(vault, withdrawals, allMarkets[0]);
    }

    function testFeeAmountFail(uint256 requiredFee, uint256 givenFee) public {
        vm.assume(requiredFee > 0);
        vm.assume(requiredFee != givenFee);

        vm.prank(OWNER);
        publicAllocator.setFee(vault, requiredFee);

        vm.deal(address(this), givenFee);
        vm.expectRevert(ErrorsLib.IncorrectFee.selector);
        publicAllocator.reallocateTo{value: givenFee}(vault, withdrawals, allMarkets[0]);
    }

    function testTransferFeeSuccess() public {
        vm.prank(OWNER);
        publicAllocator.setFee(vault, 0.001 ether);

        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: 0, maxOut: 2 ether}})));
        flowCaps.push(FlowCapsConfig({market: allMarkets[0], caps: FlowCaps({maxIn: 2 ether, maxOut: 0}})));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);
        withdrawals.push(Withdrawal({market: idleMarket, amount: 1 ether}));

        publicAllocator.reallocateTo{value: 0.001 ether}(vault, withdrawals, allMarkets[0]);
        publicAllocator.reallocateTo{value: 0.001 ether}(vault, withdrawals, allMarkets[0]);

        uint256 before = address(this).balance;

        vm.prank(OWNER);
        publicAllocator.transferFee(vault, payable(address(this)));

        assertEq(address(this).balance - before, 2 * 0.001 ether, "wrong fee transferred");
    }

    function testTransferFeeByAdminSuccess(address sender) public {
        vm.assume(publicAllocator.admin(vault) != sender);
        vm.prank(OWNER);
        publicAllocator.setAdmin(vault, sender);
        vm.prank(sender);
        publicAllocator.setFee(vault, 0.001 ether);

        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: 0, maxOut: 2 ether}})));
        flowCaps.push(FlowCapsConfig({market: allMarkets[0], caps: FlowCaps({maxIn: 2 ether, maxOut: 0}})));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);
        withdrawals.push(Withdrawal({market: idleMarket, amount: 1 ether}));

        publicAllocator.reallocateTo{value: 0.001 ether}(vault, withdrawals, allMarkets[0]);
        publicAllocator.reallocateTo{value: 0.001 ether}(vault, withdrawals, allMarkets[0]);

        uint256 before = address(this).balance;

        vm.prank(sender);
        publicAllocator.transferFee(vault, payable(address(this)));

        assertEq(address(this).balance - before, 2 * 0.001 ether, "wrong fee transferred");
    }

    function testTransferFeeFail() public {
        vm.prank(OWNER);
        publicAllocator.setFee(vault, 0.001 ether);

        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: 0, maxOut: 1 ether}})));
        flowCaps.push(FlowCapsConfig({market: allMarkets[0], caps: FlowCaps({maxIn: 1 ether, maxOut: 0}})));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);
        withdrawals.push(Withdrawal({market: idleMarket, amount: 1 ether}));

        publicAllocator.reallocateTo{value: 0.001 ether}(vault, withdrawals, allMarkets[0]);

        CantReceive cr = new CantReceive();
        vm.expectRevert("cannot receive");
        vm.prank(OWNER);
        publicAllocator.transferFee(vault, payable(address(cr)));
    }

    function testTransferOKOnZerobalance() public {
        vm.prank(OWNER);
        publicAllocator.transferFee(vault, payable(address(this)));
    }

    receive() external payable {}

    function testMaxOutNoOverflow(uint128 flow) public {
        flow = uint128(bound(flow, 1, CAP2));

        // Set flow limits with supply market's maxOut to max
        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: 0, maxOut: MAX_SETTABLE_FLOW_CAP}})));
        flowCaps.push(FlowCapsConfig({market: allMarkets[0], caps: FlowCaps({maxIn: MAX_SETTABLE_FLOW_CAP, maxOut: MAX_SETTABLE_FLOW_CAP}})));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);

        withdrawals.push(Withdrawal({market: idleMarket, amount: flow}));
        publicAllocator.reallocateTo(vault, withdrawals, allMarkets[0]);
    }

    function testMaxInNoOverflow(uint128 flow) public {
        flow = uint128(bound(flow, 1, CAP2));

        // Set flow limits with withdraw market's maxIn to max
        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: MAX_SETTABLE_FLOW_CAP, maxOut: MAX_SETTABLE_FLOW_CAP}})));
        flowCaps.push(FlowCapsConfig({market: allMarkets[0], caps: FlowCaps({maxIn: MAX_SETTABLE_FLOW_CAP, maxOut: 0}})));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);

        withdrawals.push(Withdrawal({market: idleMarket, amount: flow}));
        publicAllocator.reallocateTo(vault, withdrawals, allMarkets[0]);
    }

    function testReallocationReallocates(uint128 flow) public {
        flow = uint128(bound(flow, 1, CAP2));

        // Set flow limits
        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: MAX_SETTABLE_FLOW_CAP, maxOut: MAX_SETTABLE_FLOW_CAP}})));
        flowCaps.push(FlowCapsConfig({market: allMarkets[0], caps: FlowCaps({maxIn: MAX_SETTABLE_FLOW_CAP, maxOut: 0}})));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);

        uint256 idleBefore = _expectedSupplyAssets(idleMarket, address(vault));
        uint256 marketBefore = _expectedSupplyAssets(allMarkets[0], address(vault));
        withdrawals.push(Withdrawal({market: idleMarket, amount: flow}));
        publicAllocator.reallocateTo(vault, withdrawals, allMarkets[0]);
        uint256 idleAfter = _expectedSupplyAssets(idleMarket, address(vault));
        uint256 marketAfter = _expectedSupplyAssets(allMarkets[0], address(vault));

        assertEq(idleBefore - idleAfter, flow);
        assertEq(marketAfter - marketBefore, flow);
    }

    function testDuplicateInWithdrawals() public {
        // Set flow limits
        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: MAX_SETTABLE_FLOW_CAP, maxOut: MAX_SETTABLE_FLOW_CAP}})));
        flowCaps.push(FlowCapsConfig({market: allMarkets[0], caps: FlowCaps({maxIn: MAX_SETTABLE_FLOW_CAP, maxOut: 0}})));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);

        // Prepare public reallocation from 2 markets to 1
        // _setCap(allMarkets[1], CAP2);
        withdrawals.push(Withdrawal({market: idleMarket, amount: 1e18}));
        withdrawals.push(Withdrawal({market: idleMarket, amount: 1e18}));
        vm.expectRevert(ErrorsLib.InconsistentWithdrawals.selector);
        publicAllocator.reallocateTo(vault, withdrawals, allMarkets[0]);
    }

    function testSupplyMarketInWithdrawals() public {
        // Set flow limits
        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: MAX_SETTABLE_FLOW_CAP, maxOut: MAX_SETTABLE_FLOW_CAP}})));
        flowCaps.push(FlowCapsConfig({market: allMarkets[0], caps: FlowCaps({maxIn: MAX_SETTABLE_FLOW_CAP, maxOut: 0}})));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);

        withdrawals.push(Withdrawal({market: idleMarket, amount: 1e18}));
        vm.expectRevert(ErrorsLib.DepositMarketInWithdrawals.selector);
        publicAllocator.reallocateTo(vault, withdrawals, idleMarket);
    }

    function testReallocateMarketNotEnabledWithdrawn(IERC4626 market) public {
        vm.assume(!vault.config(market).enabled);

        withdrawals.push(Withdrawal({market: market, amount: 1e18}));

        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.MarketNotEnabled.selector, market));
        publicAllocator.reallocateTo(vault, withdrawals, idleMarket);
    }

    function testReallocateMarketNotEnabledSupply(IERC4626 market) public {
        vm.assume(!vault.config(market).enabled);

        withdrawals.push(Withdrawal({market: idleMarket, amount: 1e18}));

        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.MarketNotEnabled.selector, market));
        publicAllocator.reallocateTo(vault, withdrawals, market);
    }

    function testReallocateWithdrawZero() public {
        withdrawals.push(Withdrawal({market: idleMarket, amount: 0}));

        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.WithdrawZero.selector, idleMarket));
        publicAllocator.reallocateTo(vault, withdrawals, allMarkets[0]);
    }

    function testReallocateEmptyWithdrawals() public {
        vm.expectRevert(ErrorsLib.EmptyWithdrawals.selector);
        publicAllocator.reallocateTo(vault, withdrawals, allMarkets[0]);
    }

    function testMaxFlowCapValue() public pure {
        assertEq(MAX_SETTABLE_FLOW_CAP, 170141183460469231731687303715884105727);
    }

    function testMaxFlowCapLimit(uint128 cap) public {
        cap = uint128(bound(cap, MAX_SETTABLE_FLOW_CAP + 1, type(uint128).max));

        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: 0, maxOut: cap}})));

        vm.expectRevert(ErrorsLib.MaxSettableFlowCapExceeded.selector);
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);

        delete flowCaps;
        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: cap, maxOut: 0}})));

        vm.expectRevert(ErrorsLib.MaxSettableFlowCapExceeded.selector);
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);
    }

    function testSetFlowCapsMarketNotEnabled(IERC4626 market, uint128 maxIn, uint128 maxOut) public {
        vm.assume(!vault.config(market).enabled);
        vm.assume(maxIn != 0 || maxOut != 0);

        flowCaps.push(FlowCapsConfig({market: market, caps: FlowCaps({maxIn: maxIn, maxOut: maxOut}})));

        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.MarketNotEnabled.selector, market));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);
    }

    function testSetFlowCapsToZeroForMarketNotEnabled(IERC4626 market) public {
        vm.assume(!vault.config(market).enabled);

        flowCaps.push(FlowCapsConfig({market: market, caps: FlowCaps({maxIn: 0, maxOut: 0}})));

        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);

        assertEq(publicAllocator.flowCaps(vault, market).maxIn, 0);
        assertEq(publicAllocator.flowCaps(vault, market).maxOut, 0);
    }

    function testNotEnoughSupply() public {
        uint128 flow = 1e18;
        // Set flow limits with withdraw market's maxIn to max
        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: MAX_SETTABLE_FLOW_CAP, maxOut: MAX_SETTABLE_FLOW_CAP}})));
        flowCaps.push(FlowCapsConfig({market: allMarkets[0], caps: FlowCaps({maxIn: MAX_SETTABLE_FLOW_CAP, maxOut: MAX_SETTABLE_FLOW_CAP}})));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);

        withdrawals.push(Withdrawal({market: idleMarket, amount: flow}));
        publicAllocator.reallocateTo(vault, withdrawals, allMarkets[0]);

        delete withdrawals;

        withdrawals.push(Withdrawal({market: allMarkets[0], amount: flow + 1}));
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.NotEnoughSupply.selector, allMarkets[0]));
        publicAllocator.reallocateTo(vault, withdrawals, idleMarket);
    }

    function testMaxOutflowExceeded() public {
        uint128 cap = 1e18;
        // Set flow limits with withdraw market's maxIn to max
        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: MAX_SETTABLE_FLOW_CAP, maxOut: cap}})));
        flowCaps.push(FlowCapsConfig({market: allMarkets[0], caps: FlowCaps({maxIn: MAX_SETTABLE_FLOW_CAP, maxOut: MAX_SETTABLE_FLOW_CAP}})));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);

        withdrawals.push(Withdrawal({market: idleMarket, amount: cap + 1}));
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.MaxOutflowExceeded.selector, idleMarket));
        publicAllocator.reallocateTo(vault, withdrawals, allMarkets[0]);
    }

    function testMaxInflowExceeded() public {
        uint128 cap = 1e18;
        // Set flow limits with withdraw market's maxIn to max
        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: MAX_SETTABLE_FLOW_CAP, maxOut: MAX_SETTABLE_FLOW_CAP}})));
        flowCaps.push(FlowCapsConfig({market: allMarkets[0], caps: FlowCaps({maxIn: cap, maxOut: MAX_SETTABLE_FLOW_CAP}})));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);

        withdrawals.push(Withdrawal({market: idleMarket, amount: cap + 1}));
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.MaxInflowExceeded.selector, allMarkets[0]));
        publicAllocator.reallocateTo(vault, withdrawals, allMarkets[0]);
    }

    function testReallocateToNotSorted() public {
        // Prepare public reallocation from 2 markets to 1
        _setCap(allMarkets[1], CAP2);

        MarketAllocation[] memory allocations = new MarketAllocation[](3);
        allocations[0] = MarketAllocation({market: idleMarket, assets: INITIAL_DEPOSIT - 2e18});
        allocations[1] = MarketAllocation({market: allMarkets[0], assets: 1e18});
        allocations[2] = MarketAllocation({market: allMarkets[1], assets: 1e18});
        vm.prank(OWNER);
        vault.reallocate(allocations);

        flowCaps.push(FlowCapsConfig({market: idleMarket, caps: FlowCaps({maxIn: MAX_SETTABLE_FLOW_CAP, maxOut: MAX_SETTABLE_FLOW_CAP}})));
        flowCaps.push(FlowCapsConfig({market: allMarkets[0], caps: FlowCaps({maxIn: MAX_SETTABLE_FLOW_CAP, maxOut: MAX_SETTABLE_FLOW_CAP}})));
        flowCaps.push(FlowCapsConfig({market: allMarkets[1], caps: FlowCaps({maxIn: MAX_SETTABLE_FLOW_CAP, maxOut: MAX_SETTABLE_FLOW_CAP}})));
        vm.prank(OWNER);
        publicAllocator.setFlowCaps(vault, flowCaps);

        withdrawals.push(Withdrawal({market: allMarkets[0], amount: 1e18}));
        withdrawals.push(Withdrawal({market: allMarkets[1], amount: 1e18}));
        Withdrawal[] memory sortedWithdrawals = withdrawals.sort();
        // Created non-sorted withdrawals list
        withdrawals[0] = sortedWithdrawals[1];
        withdrawals[1] = sortedWithdrawals[0];

        vm.expectRevert(ErrorsLib.InconsistentWithdrawals.selector);
        publicAllocator.reallocateTo(vault, withdrawals, idleMarket);
    }
}
