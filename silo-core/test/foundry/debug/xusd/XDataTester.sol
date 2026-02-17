// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {IsContract} from "silo-core/contracts/lib/IsContract.sol";

import {EnumerableSet} from "openzeppelin5/utils/structs/EnumerableSet.sol";

import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {SiloLens} from "silo-core/contracts/SiloLens.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {XDataReader} from "./XDataReader.sol";

/*
FOUNDRY_PROFILE=core_test forge test --mc XDataTester --ffi -vv
*/
contract XDataTester is XDataReader {
    using EnumerableSet for EnumerableSet.UintSet;

    string constant MARKETS_FILE = "stream_markets_positions.json";
    string constant VAULTS_FILE = "stream_vaults_positions.json";

    mapping(uint256 chainId => bool checked) public chainIdChecked;
    mapping(uint256 chainId => uint256 forkingBlock) public forkingBlock;

    // I assume markets adresses are unique across all chains
    mapping(address market => uint256 totalShares) public marketShares;
    mapping(address market => uint256 totalAssets) public marketAssets;

    EnumerableSet.UintSet internal chainIds;

    /* 
    FOUNDRY_PROFILE=core_test forge test --mt test_skip_xData_markets --ffi -vvv
    */
    function test_skip_xData_markets() public {
        _check_xData_markets(MARKETS_FILE);
    }

    /* 
    FOUNDRY_PROFILE=core_test forge test --mt test_skip_xData_vaults --ffi -vvv
    */
    function test_skip_xData_vaults() public {
        _check_xData_markets(VAULTS_FILE);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_skip_check_manually --ffi -vvv
    */
    function test_skip_check_manually() public {
        _fork(42161, 397731469);

        ISilo silo = ISilo(0xACb7432a4BB15402CE2afe0A7C9D5b738604F6F9);
        address account = 0xF4Db2E9d49817EE4D1B89C214a0Dd76b603f9C33;

        SiloLens siloLens = SiloLens(0xB627bdf951889deaAFbE4CF1E8a8aE6DED8338F8);

        uint256 ltv = siloLens.getLtv(silo, account);
        emit log_named_decimal_uint("ltv %", ltv, 16);
    }

    function _check_xData_markets(string memory _fileName) public {
        Position[] memory markets = _readDataFromJson(_fileName);
        _resolveChainIds(markets);

        console2.log("all chainIds", chainIds.length());
        console2.log("all positions", markets.length);
        console2.log("--------------------------------");

        for (uint256 i = 0; i < chainIds.length(); i++) {
            uint256 chainId = chainIds.at(i);
            console2.log("checking chainId", chainId);
            _fork(chainId, forkingBlock[chainId]);

            for (uint256 j = 0; j < markets.length; j++) {
                Position memory position = markets[j];
                if (position.network_id != chainId) continue;

                _checkAccountBalance(position, j);
            }

            for (uint256 j = 0; j < markets.length; j++) {
                Position memory position = markets[j];
                if (position.network_id != chainId) continue;

                uint256 totalShares = marketShares[position.market];
                uint256 totalAssets = marketAssets[position.market];

                if (totalShares == type(uint256).max) continue; // we already checked

                assertLe(
                    totalAssets,
                    ISilo(position.market).totalAssets(),
                    string.concat("invalid total assets for market ", vm.toString(position.market))
                );
                uint256 assetsDiff = ISilo(position.market).totalAssets() - totalAssets;

                console2.log("shares diff", totalShares - ISilo(position.market).totalSupply());
                console2.log("assets diff", assetsDiff); // it is ok to have mote in Silo, because or rounding on withdraw

                assertEq(
                    totalShares,
                    ISilo(position.market).totalSupply(),
                    string.concat("invalid total shares for market ", vm.toString(position.market))
                );

                marketShares[position.market] = type(uint256).max;
                marketAssets[position.market] = type(uint256).max;
            }
        }
    }

    function _checkAccountBalance(Position memory _position, uint256 _id) internal {
        uint256 shares = IShareToken(_position.market).balanceOf(_position.account);
        uint256 assets = ISilo(_position.market).previewRedeem(shares);

        marketShares[_position.market] += shares;
        marketAssets[_position.market] += assets;

        if (assets != _position.assets) {
            console2.log("INVALID DATA FOR RECORD id", _id);
            _print(_position);
            console2.log("[%s] on chain shares %s, on chain assets %s", _id, shares, assets);
        }

        assertEq(
            assets, _position.assets, string.concat("assets mismatch for account ", vm.toString(_position.account))
        );

        assertEq(
            IsContract.isContract(_position.account),
            _position.is_contract,
            string.concat("contract detection mismatch for account ", vm.toString(_position.account))
        );
    }

    function _resolveChainIds(Position[] memory _data) internal {
        for (uint256 i = 0; i < _data.length; i++) {
            if (chainIds.contains(_data[i].network_id)) continue;

            chainIds.add(_data[i].network_id);
            forkingBlock[_data[i].network_id] = _data[i].block_number;

            // console2.log("adding chainId", _data[i].network_id);
            // _print(_data[i]);
        }
    }

    function _fork(uint256 _chainId, uint256 _blockNumber) internal {
        console2.log("\n--------------------------------");
        console2.log("forking to chainId", _chainId);
        console2.log("forking to block number", _blockNumber);
        console2.log("--------------------------------\n");

        if (_chainId == 146) {
            console2.log("forking to sonic");
            assertEq(_blockNumber, 54144258);
            vm.createSelectFork(vm.envString("RPC_SONIC"), _blockNumber);
        } else if (_chainId == 1) {
            console2.log("forking to mainnet");
            assertEq(_blockNumber, 23747030);
            vm.createSelectFork(vm.envString("RPC_MAINNET"), _blockNumber);
        } else if (_chainId == 42161) {
            console2.log("forking to arbitrum");
            assertEq(_blockNumber, 397731469);
            vm.createSelectFork(vm.envString("RPC_ARBITRUM"), _blockNumber);
        } else if (_chainId == 43114) {
            console2.log("forking to avalanche");
            assertEq(_blockNumber, 71568890);
            vm.createSelectFork(vm.envString("RPC_AVALANCHE"), _blockNumber);
        } else {
            revert("chainId not supported (make sure you replace `vault` => `market` in json file)");
        }
    }
}
