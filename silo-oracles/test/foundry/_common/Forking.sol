// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {Test} from "forge-std/Test.sol";
import {IForking} from "../interfaces/IForking.sol";

contract Forking is IForking, Test {
    BlockChain public FORKED_CHAIN;

    uint256 public FORK_ID;
    uint256 forkedBlockNumber;

    string ARBITRUM_RPC_URL;
    string ETHEREUM_RPC_URL;
    string SONIC_RPC_URL;
    string AVALANCHE_RPC_URL;

    /// @dev arbitrum checkpoints to ethereum, so block.number on Arbitrum is actually ethereum block.
    /// To handle this case and be able to add unit tests for expected block we will be using mapping
    /// Arbitrum block number => ETH block number (checkpoint)
    mapping(uint256 => uint256) public arbitrumToEthereumCheckout;

    constructor(BlockChain _chain) {
        ARBITRUM_RPC_URL = string(abi.encodePacked(vm.envString("RPC_ARBITRUM")));
        ETHEREUM_RPC_URL = string(abi.encodePacked(vm.envString("RPC_MAINNET")));
        SONIC_RPC_URL = string(abi.encodePacked(vm.envString("RPC_SONIC")));
        AVALANCHE_RPC_URL = string(abi.encodePacked(vm.envString("RPC_AVALANCHE")));

        FORKED_CHAIN = _chain;
    }

    function initFork() public virtual {
        if (FORKED_CHAIN == BlockChain.ARBITRUM) {
            FORK_ID = _createFork(ARBITRUM_RPC_URL);
        } else if (FORKED_CHAIN == BlockChain.ETHEREUM) {
            FORK_ID = _createFork(ETHEREUM_RPC_URL);
        } else if (FORKED_CHAIN == BlockChain.SONIC) {
            FORK_ID = _createFork(SONIC_RPC_URL);
        } else if (FORKED_CHAIN == BlockChain.AVALANCHE) {
            FORK_ID = _createFork(AVALANCHE_RPC_URL);
        }
    }

    function initFork(uint256 _forkingBlockNumber) public virtual {
        forkedBlockNumber = _forkingBlockNumber;

        if (FORKED_CHAIN == BlockChain.ARBITRUM) {
            FORK_ID = _createFork(ARBITRUM_RPC_URL, _forkingBlockNumber);
        } else if (FORKED_CHAIN == BlockChain.ETHEREUM) {
            FORK_ID = _createFork(ETHEREUM_RPC_URL, _forkingBlockNumber);
        } else if (FORKED_CHAIN == BlockChain.SONIC) {
            FORK_ID = _createFork(SONIC_RPC_URL, _forkingBlockNumber);
        } else if (FORKED_CHAIN == BlockChain.AVALANCHE) {
            FORK_ID = _createFork(AVALANCHE_RPC_URL, _forkingBlockNumber);
        }
    }

    function isArbitrum() public view returns (bool) {
        return FORKED_CHAIN == BlockChain.ARBITRUM;
    }

    function isArbitrum(BlockChain _chain) public pure returns (bool) {
        return _chain == BlockChain.ARBITRUM;
    }

    function isEthereum() public view returns (bool) {
        return FORKED_CHAIN == BlockChain.ETHEREUM;
    }

    function isEthereum(BlockChain _chain) public pure returns (bool) {
        return _chain == BlockChain.ETHEREUM;
    }

    function isSonic() public view returns (bool) {
        return FORKED_CHAIN == BlockChain.SONIC;
    }

    function isSonic(BlockChain _chain) public pure returns (bool) {
        return _chain == BlockChain.SONIC;
    }

    function isAvalanche() public view returns (bool) {
        return FORKED_CHAIN == BlockChain.AVALANCHE;
    }

    function isAvalanche(BlockChain _chain) public pure returns (bool) {
        return _chain == BlockChain.AVALANCHE;
    }

    function getBlockChainID() public view returns (uint256 id) {
        assembly {
            id := chainid()
        }
        
        FORK_ID; // to silence warnings about making this method pure
    }

    function _createFork(string memory _rpc) internal returns (uint256) {
        return vm.createSelectFork(_rpc);
    }

    function _createFork(string memory _rpc, uint256 blockNumber) internal returns (uint256) {
        return vm.createSelectFork(_rpc, blockNumber);
    }

    function _testExpectedBlockNumber(string memory _msg) internal view {
        uint256 expectedBlock = isArbitrum() ? arbitrumToEthereumCheckout[forkedBlockNumber] : forkedBlockNumber;
        assertEq(block.number, expectedBlock, string(abi.encodePacked("forked block number is invalid: ", _msg)));
    }
}
