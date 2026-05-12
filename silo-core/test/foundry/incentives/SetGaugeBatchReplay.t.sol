// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";

/*
How to use:

1) Point to any Safe batch JSON (Set Gauge / whitelist / etc):
   SET_GAUGE_BATCH_JSON="scripts/tasks/set-permissioned-liquidation/out/Set Gauge for Current Markets - bnb.json"

2) Run on a fork of the target chain:
   FOUNDRY_PROFILE=core_test forge test \
     --match-contract SetGaugeBatchReplayTest \
     -vvv
*/
contract SetGaugeBatchReplayTest is Test {
    using stdJson for string;

    error UnsupportedInputType(string solidityType);
    error BatchTxFailed(uint256 index, address target, bytes revertData);

    string internal constant DEFAULT_BATCH_PATH =
        "scripts/tasks/set-permissioned-liquidation/out/Set Gauge for Current Markets - mainnet - Part 3.json";

    function test_replayBatchTransactionsFromJson() external {
        vm.createSelectFork(vm.envString("RPC_MAINNET"), 25081808);

        string memory batchPath = vm.envOr("SET_GAUGE_BATCH_JSON", DEFAULT_BATCH_PATH);
        string memory json = vm.readFile(batchPath);

        if (!json.keyExists(".transactions[0]")) {
            return;
        }

        address owner = json.readAddress(".meta.createdFromSafeAddress");
        uint256 txCount = _transactionsCount({json: json});

        vm.startPrank(owner);

        for (uint256 i = 0; i < txCount; i++) {
            string memory txPath = _txPath({index: i});
            address target = json.readAddress(string.concat(txPath, ".to"));
            bytes memory callData = _buildCallData({json: json, txPath: txPath});

            (bool ok, bytes memory revertData) = target.call(callData);
            if (!ok) revert BatchTxFailed({index: i, target: target, revertData: revertData});
        }

        vm.stopPrank();
    }

    function _transactionsCount(string memory json) internal view returns (uint256 count) {
        while (json.keyExists(_txPath({index: count}))) {
            count++;
        }
    }

    function _txPath(uint256 index) internal pure returns (string memory) {
        return string.concat(".transactions[", vm.toString(index), "]");
    }

    function _buildCallData(string memory json, string memory txPath) internal view returns (bytes memory) {
        string memory methodName = json.readString(string.concat(txPath, ".contractMethod.name"));
        string memory typesCsv = _typesCsv({json: json, txPath: txPath});
        bytes4 selector = bytes4(keccak256(bytes(string.concat(methodName, "(", typesCsv, ")"))));
        bytes memory encodedArgs = _encodeArgs({json: json, txPath: txPath});
        return bytes.concat(selector, encodedArgs);
    }

    function _typesCsv(string memory json, string memory txPath) internal view returns (string memory out) {
        uint256 inputCount = _inputsCount({json: json, txPath: txPath});
        for (uint256 j = 0; j < inputCount; j++) {
            string memory inputPath = _inputPath({txPath: txPath, inputIndex: j});
            string memory solidityType = json.readString(string.concat(inputPath, ".type"));
            out = j == 0 ? solidityType : string.concat(out, ",", solidityType);
        }
    }

    function _encodeArgs(string memory json, string memory txPath) internal view returns (bytes memory encoded) {
        uint256 inputCount = _inputsCount({json: json, txPath: txPath});
        for (uint256 j = 0; j < inputCount; j++) {
            string memory inputPath = _inputPath({txPath: txPath, inputIndex: j});
            string memory solidityType = json.readString(string.concat(inputPath, ".type"));
            string memory inputName = json.readString(string.concat(inputPath, ".name"));
            string memory valuePath = string.concat(txPath, ".contractInputsValues.", inputName);
            bytes32 word = _encodeStaticWord({json: json, valuePath: valuePath, solidityType: solidityType});
            encoded = bytes.concat(encoded, abi.encodePacked(word));
        }
    }

    function _encodeStaticWord(string memory json, string memory valuePath, string memory solidityType)
        internal
        pure
        returns (bytes32)
    {
        bytes32 t = keccak256(bytes(solidityType));

        if (t == keccak256("address")) {
            return bytes32(uint256(uint160(json.readAddress(valuePath))));
        }

        if (t == keccak256("bool")) {
            return json.readBool(valuePath) ? bytes32(uint256(1)) : bytes32(0);
        }

        if (t == keccak256("bytes32")) {
            return json.readBytes32(valuePath);
        }

        if (t == keccak256("uint256") || t == keccak256("uint")) {
            return bytes32(json.readUint(valuePath));
        }

        revert UnsupportedInputType(solidityType);
    }

    function _inputsCount(string memory json, string memory txPath) internal view returns (uint256 count) {
        while (json.keyExists(_inputPath({txPath: txPath, inputIndex: count}))) {
            count++;
        }
    }

    function _inputPath(string memory txPath, uint256 inputIndex) internal pure returns (string memory) {
        return string.concat(txPath, ".contractMethod.inputs[", vm.toString(inputIndex), "]");
    }
}
