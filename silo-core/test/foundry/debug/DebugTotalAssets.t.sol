// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

/*
    Ethereum mainnet — `ISilo` implements `IERC4626`; `totalAssets()` is the ERC-4626 view on managed underlying.

    Tx 1 — block 24717386 (tx index 131). Router multicall touches Silo below.
    https://etherscan.io/tx/0xb7a83fe095955ac06f6fd839d128ff4aaca7bd3ee3e65950596f9f809026e682

    Tx 2 — block 24749064 (tx index 38). `reallocate` on vault coordinator; first market in calldata is the Silo below.
    https://etherscan.io/tx/0x5d943a5d67aec215c45c070a4d975b92212a93cb90cd5c91496a2a6fd623c64e

    Uses `vm.rollFork(txHash)` so the fork replays all txs in the block before this one (state immediately before the tx).
    Then `vm.transact(txHash)` replays the on-chain transaction locally.

    FOUNDRY_PROFILE=core_with_test forge test --mc DebugTotalAssetsTest --mt test_skip -vv --gas-price 1 

    Requires `RPC_MAINNET` with archive state (Alchemy, Infura, etc.) — full nodes often cannot serve `rollFork` / `transact`.
*/
contract DebugTotalAssetsTest is Test {
    bytes32 internal constant TX_1 = 0xb7a83fe095955ac06f6fd839d128ff4aaca7bd3ee3e65950596f9f809026e682;
    bytes32 internal constant TX_2 = 0x5d943a5d67aec215c45c070a4d975b92212a93cb90cd5c91496a2a6fd623c64e;

    /// @dev Silo called inside tx 1 multicall (deposit path on USDC silo).
    ISilo internal constant SILO_1 = ISilo(0xc2B4316331303Bf31fEe9854709271851099138E);

    /// @dev First `(address,uint256)` market in tx 2 `reallocate` payload.
    ISilo internal constant SILO_2 = ISilo(0x5B3E7d6795bB8670A88d64BbF7ca1CCA69F1f69c);

    function test_skip_totalAssets_tx1_multicall() public {
        uint256 blockNumber = 24717386;
        vm.createSelectFork(vm.envString("RPC_MAINNET"), blockNumber - 1);
        // vm.rollFork(TX_1);

        uint256 beforeTotal = SILO_1.totalAssets();
        console2.log("simulation on block", block.number);
        console2.logBytes32(TX_1);
        console2.log("tx1 block (from rollFork)", block.number);
        console2.log("SILO_1 totalAssets before transact", beforeTotal);

        vm.transact(TX_1);

        uint256 afterTotal = SILO_1.totalAssets();
        console2.log("SILO_1 totalAssets after transact ", afterTotal);
        vm.createSelectFork(vm.envString("RPC_MAINNET"), blockNumber + 1);

        afterTotal = SILO_1.totalAssets();
        console2.log("SILO_1 totalAssets on block after tx", afterTotal);
    }

    function test_skip_totalAssets_tx2_reallocate() public {
        uint256 blockNumber = 24749064;
        vm.createSelectFork(vm.envString("RPC_MAINNET"), blockNumber - 1);
        // vm.rollFork(TX_2);

        uint256 beforeTotal = SILO_2.totalAssets();
        console2.log("simulation on block", block.number);
        console2.logBytes32(TX_2);
        console2.log("tx2 block (from rollFork)", block.number);
        console2.log("SILO_2 totalAssets before transact", beforeTotal);

        vm.transact(TX_2);

        uint256 afterTotal = SILO_2.totalAssets();
        console2.log("SILO_2 totalAssets after transact ", afterTotal);
        vm.createSelectFork(vm.envString("RPC_MAINNET"), blockNumber + 1);

        afterTotal = SILO_2.totalAssets();
        console2.log("SILO_2 totalAssets on block after tx", afterTotal);
    }
}
