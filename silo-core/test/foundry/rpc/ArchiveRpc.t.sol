// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";

/*
    Checks that RPC_URL can serve ARCHIVE_BLOCK (archive node).
    Block number 0 forks the latest block.

    FOUNDRY_PROFILE=core_test RPC_URL=$RPC_BASE forge test --mt test_skip_rpc_isArchive -vv
    FOUNDRY_PROFILE=core_test RPC_URL=https://bsc-dataseed.bnbchain.org forge test --mt test_skip_rpc_isArchive -vv
    FOUNDRY_PROFILE=core_test RPC_URL=https://arb1.arbitrum.io/rpc forge test --mt test_skip_rpc_isArchive -vv
    FOUNDRY_PROFILE=core_test RPC_URL=https://rpc.pharos.xyz forge test --mt test_skip_rpc_isArchive -vv

    see also:
    RPC_URL=https://rpc.pharos.xyz python3 scripts/check_rpc_is_archive.py 15091991

*/
contract ArchiveRpcTest is Test {
    uint256 internal constant LATEST_BLOCK = 0;
    uint256 internal constant ARCHIVE_BLOCK = 15091991;

    string internal archiveBlockDec;
    string internal archiveBlockHex;

    constructor() {
        archiveBlockDec = vm.toString(ARCHIVE_BLOCK);
        archiveBlockHex = _toQuantity(ARCHIVE_BLOCK);
    }

    function test_skip_rpc_isArchive() public {
        this.forkAt(LATEST_BLOCK);

        try this.forkAt(ARCHIVE_BLOCK) {
            console2.log("forked at archive block - success, historical state is available");
            try this.readArchiveBlockHistory() {
                console2.log(string.concat("block ", archiveBlockDec, " transactions and receipts were served"));
            } catch {
                assertTrue({
                    data: false,
                    err: string.concat(
                        "RPC state is archive, but block ",
                        archiveBlockDec,
                        " transactions or receipts were not served"
                    )
                });
            }
        } catch {
            assertTrue({
                data: false,
                err: string.concat("RPC is not archive: block ", archiveBlockDec, " was not served")
            });
        }
    }

    /// @dev External so a missing block body or receipt history revert can be caught. The payload is ignored.
    /// URL is passed explicitly: `vm.rpc` without it does not see a fork created in another external call.
    function readArchiveBlockHistory() external {
        string memory rpc = vm.envString("RPC_URL");

        vm.rpc({
            urlOrAlias: rpc,
            method: "eth_getBlockByNumber",
            params: string.concat('["', archiveBlockHex, '", true]')
        });
        vm.rpc({
            urlOrAlias: rpc,
            method: "eth_getBlockReceipts",
            params: string.concat('["', archiveBlockHex, '"]')
        });
    }

    /// @dev `blockNumber` 0 forks the chain tip. External so a failed historical fork can be caught.
    function forkAt(uint256 blockNumber) external {
        string memory rpc = vm.envString("RPC_URL");

        if (blockNumber == LATEST_BLOCK) {
            vm.createSelectFork(rpc);
        } else {
            vm.createSelectFork({urlOrAlias: rpc, blockNumber: blockNumber});
        }

        console2.log({p0: "block", p1: block.number});
        console2.log({p0: "timestamp", p1: block.timestamp});
    }

    /// @dev JSON-RPC quantity: hex without a leading zero nibble. `Strings.toHexString` pads to a whole byte.
    function _toQuantity(uint256 value) internal pure returns (string memory) {
        bytes memory hexed = bytes(Strings.toHexString(value));

        if (hexed.length > 3 && hexed[2] == "0") {
            bytes memory trimmed = new bytes(hexed.length - 1);
            trimmed[0] = "0";
            trimmed[1] = "x";

            for (uint256 i = 2; i < trimmed.length; i++) {
                trimmed[i] = hexed[i + 1];
            }

            return string(trimmed);
        }

        return string(hexed);
    }
}
