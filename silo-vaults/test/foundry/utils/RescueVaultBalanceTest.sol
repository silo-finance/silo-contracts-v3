// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {ISiloVault} from "../../../contracts/interfaces/ISiloVault.sol";
import {IVaultIncentivesModule} from "../../../contracts/interfaces/IVaultIncentivesModule.sol";
import {RescueVaultBalance} from "../../../contracts/utils/RescueVaultBalance.sol";

/*
    FOUNDRY_PROFILE=vaults forge test --ffi --mc RescueVaultBalanceTest -vvv
*/
contract RescueVaultBalanceTest is Test {
    // vault address on Arbitrum
    ISiloVault constant VAULT = ISiloVault(0xd8c989aB5f5b2ABDc76a8D3Acec165300BF30ecD);
    IERC4626 constant MARKET = IERC4626(0xB77FF64638A2CaB0a102B3c7964514Cb50D577ca);

    event VaultBalanceRescued(address indexed token, uint256 amount);

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_ARBITRUM"), 471674718);
    }

    /// @dev when the market is NOT present in the vault queues, the idle balance is rescued to the receiver.
    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_rescueVaultBalance -vvv
    */
    function test_rescueVaultBalance() public {
        address receiver = makeAddr("RECEIVER");

        // a market that is not present in the vault deposit/withdraw queue, so the rescue is allowed.
        RescueVaultBalance claimingLogic = new RescueVaultBalance(receiver, MARKET);

        _registerClaimingLogic(MARKET, claimingLogic);

        uint256 vaultBalance = 2315048562846303750875;
        IERC20 asset = IERC20(VAULT.asset());

        // the logic is delegatecalled by the vault, so the event is emitted from the vault address.
        vm.expectEmit(true, true, true, true, address(VAULT));
        emit VaultBalanceRescued(address(MARKET), vaultBalance);

        // any action that triggers `_claimRewards` will run the rescue logic.
        VAULT.claimRewards();

        assertEq(asset.balanceOf(receiver), vaultBalance, "receiver should have received the rescued balance");

        // again, to make sure we will not revert or something
        VAULT.claimRewards();
    }

    /// @dev when the market is still present in the vault withdraw queue, the balance must NOT be rescued.
    function test_rescueVaultBalance_skipsWhenMarketInQueue() public {
        address receiver = makeAddr("RECEIVER");

        // pick a market that is still present in the vault withdraw queue.
        IERC4626 connectedMarket = VAULT.withdrawQueue(0);

        RescueVaultBalance claimingLogic = new RescueVaultBalance(receiver, connectedMarket);

        _registerClaimingLogic(connectedMarket, claimingLogic);

        IERC20 asset = IERC20(VAULT.asset());

        deal(address(asset), address(VAULT), 1_000e6);

        uint256 vaultBalanceBefore = asset.balanceOf(address(VAULT));

        VAULT.claimRewards();

        assertEq(asset.balanceOf(receiver), 0, "receiver must not receive anything while market is connected");
        assertEq(asset.balanceOf(address(VAULT)), vaultBalanceBefore, "vault balance must stay untouched");
    }

    /// @dev registers the claiming logic in the incentives module following the owner + timelock flow.
    function _registerClaimingLogic(IERC4626 _market, RescueVaultBalance _logic) internal {
        IVaultIncentivesModule incentivesModule = VAULT.INCENTIVES_MODULE();
        address owner = VAULT.owner();

        vm.prank(owner);
        incentivesModule.submitIncentivesClaimingLogic(_market, _logic);

        // the logic comes from an untrusted factory, so the submission is subject to the vault timelock.
        vm.warp(block.timestamp + VAULT.timelock() + 1);

        incentivesModule.acceptIncentivesClaimingLogic(_market, _logic);
    }
}
