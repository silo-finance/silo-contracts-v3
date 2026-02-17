// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

contract XDataReader is Test {
    bytes32 constant TRUE = keccak256("True");

    /*
        "network_id": "146",
    "account": "0x9a1bf5365edbb99c2c61ca6d9ffad0b705acfc6f",
    "market": "0x27968d36b937dcb26f33902fa489e5b228b104be",
    "asset_symbol": "dUSD",
    "assets": "23174657540190411039416",
    "is_contract": "True",
    "assets_normalized": "23174.657540190411039416",
    "block_number": "54144258"
    */
    // must be in alphabetic order
    struct Position {
        address account;
        string asset_symbol;
        uint256 assets;
        string assets_normalized;
        uint256 block_number;
        bool is_contract;
        address market;
        uint256 network_id;
    }

    function _readDataFromJson(string memory _fileName) internal view returns (Position[] memory) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/silo-core/test/foundry/data/stream/", _fileName);
        string memory json = vm.readFile(path);

        return abi.decode(vm.parseJson(json, string(abi.encodePacked("."))), (Position[]));
    }

    function _print(Position memory _data) internal {
        emit log_named_uint("/njson.network_id", _data.network_id);
        emit log_named_uint("json.block_number", _data.block_number);
        emit log_named_address("json.market", _data.market);

        emit log_named_address("json.account", _data.account);
        emit log_named_string("json.is_contract", _data.is_contract ? "true" : "false");

        emit log_named_uint("json.assets", _data.assets);
        // emit log_named_string("json.assets_normalized", _data.assets_normalized);
        emit log_named_string("json.asset_symbol", _data.asset_symbol);
        console2.log("--------------------------------");
    }
}
