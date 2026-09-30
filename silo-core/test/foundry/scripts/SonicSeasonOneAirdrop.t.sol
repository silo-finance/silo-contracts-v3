// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {SonicSeasonOneAirdrop} from "silo-core/scripts/airdrop/SonicSeasonOneAirdrop.s.sol";
import {SonicSeasonOneVerifier} from "silo-core/scripts/airdrop/SonicSeasonOneVerifier.s.sol";
import {TransferData} from "silo-core/scripts/airdrop/SonicSeasonOneDataReader.s.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";

/*
    FOUNDRY_PROFILE=core_test forge test -vv --match-contract SonicSeasonOneAirdropTest --ffi
*/
contract SonicSeasonOneAirdropTest is Test {
    Vm.Wallet airdropWallet;
    uint256[] balancesBefore;

    function setUp() public {
        vm.createSelectFork(string(abi.encodePacked(vm.envString("RPC_SONIC"))), 40727841);
        airdropWallet = vm.createWallet(uint256(keccak256(bytes("1"))));
        // forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("AIRDROP_PRIVATE_KEY", Strings.toHexString(airdropWallet.privateKey));
        deal(airdropWallet.addr, 10 ** 18 * 10 ** 18);
    }

    function test_CheckQAWalletBalance() public view {
        assertTrue(airdropWallet.addr.balance > 0);
    }

    function test_VerifierDoesNotGiveFalsePositive() public {
        SonicSeasonOneVerifier verifier = new SonicSeasonOneVerifier();
        verifier.setBatch(0, 10, block.number - 100, block.number);
        vm.expectRevert();
        verifier.run();
    }

    function test_BalancesIncreaseExpected() public {
        SonicSeasonOneAirdrop airdrop = new SonicSeasonOneAirdrop();
        TransferData[] memory data = airdrop.readTransferData();
        uint256 start = 1234;
        uint256 batchLength = 100;
        uint256 end = start + batchLength;

        uint256 leftFromBatchBalance = data[start - 1].addr.balance;
        uint256 rightFromBatchBalance = data[end].addr.balance;
        uint256 firstFromBatchBalance = data[start].addr.balance;
        uint256 lastFromBatchBalance = data[end - 1].addr.balance;
        uint256 multicall3Balance = address(airdrop.MULTICALL3()).balance;

        uint256 totalToSend;
        uint256 senderBalance = airdropWallet.addr.balance;

        for (uint256 i = start; i < end; i++) {
            balancesBefore.push(data[i].addr.balance);
            totalToSend += data[i].amount;
        }

        airdrop.setBatch(start, end);
        airdrop.run();

        for (uint256 i; i < batchLength; i++) {
            assertEq(data[i + start].addr.balance, balancesBefore[i] + data[i + start].amount, "amount is received");
        }

        assertEq(airdropWallet.addr.balance, senderBalance - totalToSend, "sent expected total amount");
        assertEq(data[start - 1].addr.balance, leftFromBatchBalance, "left from batch address did not receive");
        assertEq(data[end].addr.balance, rightFromBatchBalance, "right from batch address did not receive");
        assertTrue(data[start].addr.balance > firstFromBatchBalance, "first from batch received");
        assertTrue(data[end - 1].addr.balance > lastFromBatchBalance, "last from batch received");
        assertEq(address(airdrop.MULTICALL3()).balance, multicall3Balance, "no dust left");

        SonicSeasonOneVerifier verifier = new SonicSeasonOneVerifier();
        verifier.setBatch(start, end, block.number - 100, block.number);
        verifier.run();

        verifier.setBatch(start - 1, end, block.number - 100, block.number);
        vm.expectRevert();
        verifier.run();

        verifier.setBatch(start, end + 1, block.number - 100, block.number);
        vm.expectRevert();
        verifier.run();

        verifier.setBatch(start, end, block.number - 100, block.number);
        verifier.run();
    }
}
