// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";

/// @dev Helpers to drive EmptySilo tests from Foundry's Silo.sol artifact JSON.
library EmptySiloArtifactLib {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    struct AbiFunctionCase {
        string signature;
        bytes4 selector;
        bytes callData;
        bool shouldRevert;
        bytes expectedReturnData;
    }

    string internal constant SILO_ARTIFACT_PATH = "/cache/foundry/out/silo-core/Silo.sol/Silo.json";

    function siloArtifactJson() internal view returns (string memory json) {
        string memory path = string.concat(VM.projectRoot(), SILO_ARTIFACT_PATH);
        json = VM.readFile(path);
    }

    function loadAbiFunctionCases() internal view returns (AbiFunctionCase[] memory cases) {
        string memory json = siloArtifactJson();
        uint256 abiLength = _abiEntryCount(json);
        uint256 functionCount;

        for (uint256 i = 0; i < abiLength; i++) {
            if (_isAbiFunction(json, i)) functionCount++;
        }

        cases = new AbiFunctionCase[](functionCount);
        uint256 caseIndex;

        for (uint256 i = 0; i < abiLength; i++) {
            if (!_isAbiFunction(json, i)) continue;

            string memory signature = _abiFunctionSignature(json, i);
            bytes4 selector = _selectorFromArtifact(json, signature);
            string memory stateMutability = VM.parseJsonString(
                json, string.concat(".abi[", VM.toString(i), "].stateMutability")
            );

            cases[caseIndex] = AbiFunctionCase({
                signature: signature,
                selector: selector,
                callData: abi.encodePacked(selector, _encodeDefaultInputs(signature)),
                shouldRevert: !_isReadOnly(stateMutability),
                expectedReturnData: _encodeDefaultOutputs(json, i)
            });

            caseIndex++;
        }
    }

    function _abiEntryCount(string memory json) internal pure returns (uint256 count) {
        while (true) {
            string memory path = string.concat(".abi[", VM.toString(count), "].type");
            try VM.parseJsonString(json, path) returns (string memory) {
                count++;
            } catch {
                break;
            }
        }
    }

    function _isAbiFunction(string memory json, uint256 index) internal pure returns (bool) {
        string memory entryType =
            VM.parseJsonString(json, string.concat(".abi[", VM.toString(index), "].type"));
        return keccak256(bytes(entryType)) == keccak256(bytes("function"));
    }

    function _abiFunctionSignature(string memory json, uint256 index) internal pure returns (string memory signature) {
        string memory name = VM.parseJsonString(json, string.concat(".abi[", VM.toString(index), "].name"));
        uint256 inputsLength = _abiArrayLength(json, string.concat(".abi[", VM.toString(index), "].inputs"));

        if (inputsLength == 0) {
            return string.concat(name, "()");
        }

        string memory params = VM.parseJsonString(json, string.concat(".abi[", VM.toString(index), "].inputs[0].type"));

        for (uint256 j = 1; j < inputsLength; j++) {
            string memory inputType = VM.parseJsonString(
                json, string.concat(".abi[", VM.toString(index), "].inputs[", VM.toString(j), "].type")
            );
            params = string.concat(params, ",", inputType);
        }

        return string.concat(name, "(", params, ")");
    }

    function _abiArrayLength(string memory json, string memory basePath) internal pure returns (uint256 length) {
        while (true) {
            string memory path = string.concat(basePath, "[", VM.toString(length), "].type");
            try VM.parseJsonString(json, path) returns (string memory) {
                length++;
            } catch {
                break;
            }
        }
    }

    function _selectorFromArtifact(string memory json, string memory signature)
        internal
        pure
        returns (bytes4 selector)
    {
        string memory key = string.concat(".methodIdentifiers[\"", signature, "\"]");
        string memory selectorHex = VM.parseJsonString(json, key);
        selector = bytes4(VM.parseBytes(string(abi.encodePacked("0x", selectorHex))));
        require(selector != bytes4(0), "missing selector in artifact");
    }

    function _isReadOnly(string memory stateMutability) internal pure returns (bool) {
        bytes32 mut = keccak256(bytes(stateMutability));
        return mut == keccak256("view") || mut == keccak256("pure");
    }

    function _encodeDefaultInputs(string memory signature) internal pure returns (bytes memory encoded) {
        string[] memory types = _paramTypesFromSignature(signature);
        return _abiEncode(types);
    }

    function _encodeDefaultOutputs(string memory json, uint256 abiIndex) internal view returns (bytes memory encoded) {
        string memory basePath = string.concat(".abi[", VM.toString(abiIndex), "].outputs");
        uint256 outputsLength = _abiArrayLength(json, basePath);

        if (outputsLength == 0) return "";

        string[] memory types = new string[](_flattenedOutputTypeCount(json, basePath, outputsLength));
        uint256 typeIndex;

        for (uint256 i = 0; i < outputsLength; i++) {
            string memory outputPath = string.concat(basePath, "[", VM.toString(i), "]");
            typeIndex = _collectOutputTypes(json, outputPath, types, typeIndex);
        }

        return _abiEncode(types);
    }

    function _flattenedOutputTypeCount(string memory json, string memory basePath, uint256 outputsLength)
        internal
        view
        returns (uint256 count)
    {
        for (uint256 i = 0; i < outputsLength; i++) {
            string memory outputPath = string.concat(basePath, "[", VM.toString(i), "]");
            count += _outputTypeCount(json, outputPath);
        }
    }

    function _outputTypeCount(string memory json, string memory outputPath) internal view returns (uint256 count) {
        string memory outputType = VM.parseJsonString(json, string.concat(outputPath, ".type"));

        if (keccak256(bytes(outputType)) == keccak256(bytes("tuple"))) {
            string memory componentsPath = string.concat(outputPath, ".components");
            uint256 componentsLength = _abiArrayLength(json, componentsPath);

            for (uint256 i = 0; i < componentsLength; i++) {
                count += _outputTypeCount(json, string.concat(componentsPath, "[", VM.toString(i), "]"));
            }

            return count;
        }

        return 1;
    }

    function _collectOutputTypes(
        string memory json,
        string memory outputPath,
        string[] memory types,
        uint256 typeIndex
    ) internal view returns (uint256 nextTypeIndex) {
        string memory outputType = VM.parseJsonString(json, string.concat(outputPath, ".type"));

        if (keccak256(bytes(outputType)) == keccak256(bytes("tuple"))) {
            string memory componentsPath = string.concat(outputPath, ".components");
            uint256 componentsLength = _abiArrayLength(json, componentsPath);

            for (uint256 i = 0; i < componentsLength; i++) {
                typeIndex = _collectOutputTypes(
                    json, string.concat(componentsPath, "[", VM.toString(i), "]"), types, typeIndex
                );
            }

            return typeIndex;
        }

        types[typeIndex] = outputType;
        return typeIndex + 1;
    }

    function _paramTypesFromSignature(string memory signature) internal pure returns (string[] memory types) {
        bytes memory sigBytes = bytes(signature);
        uint256 openParen;
        uint256 closeParen;

        for (uint256 i = 0; i < sigBytes.length; i++) {
            if (sigBytes[i] == "(") openParen = i;
            if (sigBytes[i] == ")") closeParen = i;
        }

        if (closeParen <= openParen + 1) {
            return new string[](0);
        }

        bytes memory paramsBytes = new bytes(closeParen - openParen - 1);
        for (uint256 i = openParen + 1; i < closeParen; i++) {
            paramsBytes[i - openParen - 1] = sigBytes[i];
        }

        return _splitCommaSeparatedTypes(string(paramsBytes));
    }

    function _splitCommaSeparatedTypes(string memory params) internal pure returns (string[] memory types) {
        bytes memory paramsBytes = bytes(params);
        uint256 count = 1;

        if (paramsBytes.length == 0) return new string[](0);

        for (uint256 i = 0; i < paramsBytes.length; i++) {
            if (paramsBytes[i] == ",") count++;
        }

        types = new string[](count);
        uint256 partIndex;
        uint256 start;

        for (uint256 i = 0; i <= paramsBytes.length; i++) {
            if (i == paramsBytes.length || paramsBytes[i] == ",") {
                uint256 len = i - start;
                bytes memory part = new bytes(len);
                for (uint256 j = 0; j < len; j++) {
                    part[j] = paramsBytes[start + j];
                }
                types[partIndex++] = string(part);
                start = i + 1;
            }
        }
    }

    function _abiEncode(string[] memory types) internal pure returns (bytes memory encoded) {
        if (types.length == 0) return "";

        bytes[] memory head = new bytes[](types.length);
        bytes memory tail;
        uint256 tailOffset = types.length * 32;

        for (uint256 i = 0; i < types.length; i++) {
            if (_isDynamicType(types[i])) {
                head[i] = abi.encode(tailOffset);
                bytes memory dynamicEncoded = _encodeDynamicEmpty(types[i]);
                tail = abi.encodePacked(tail, dynamicEncoded);
                tailOffset += dynamicEncoded.length;
            } else {
                head[i] = _encodeStaticEmpty(types[i]);
            }
        }

        encoded = _concatBytes(head);
        if (tail.length > 0) encoded = abi.encodePacked(encoded, tail);
    }

    function _isDynamicType(string memory t) internal pure returns (bool) {
        bytes32 typeHash = keccak256(bytes(t));
        if (typeHash == keccak256("bytes") || typeHash == keccak256("string")) return true;

        bytes memory tb = bytes(t);
        return tb.length > 0 && tb[tb.length - 1] == "]";
    }

    function _encodeDynamicEmpty(string memory t) internal pure returns (bytes memory encoded) {
        bytes32 typeHash = keccak256(bytes(t));
        if (typeHash == keccak256("bytes") || typeHash == keccak256("string")) return abi.encode(uint256(0));

        return abi.encode(uint256(0));
    }

    function _encodeStaticEmpty(string memory t) internal pure returns (bytes memory encoded) {
        bytes32 typeHash = keccak256(bytes(t));

        if (typeHash == keccak256("address") || typeHash == keccak256("bool") || typeHash == keccak256("bytes32")) {
            return abi.encode(uint256(0));
        }

        if (_isUintType(t) || _isIntType(t) || _isFixedBytesType(t)) {
            return abi.encode(uint256(0));
        }

        revert(string.concat("unsupported type: ", t));
    }

    function _isUintType(string memory t) internal pure returns (bool) {
        bytes memory tb = bytes(t);
        return tb.length >= 4 && tb[0] == "u" && tb[1] == "i" && tb[2] == "n" && tb[3] == "t";
    }

    function _isIntType(string memory t) internal pure returns (bool) {
        bytes memory tb = bytes(t);
        return tb.length >= 3 && tb[0] == "i" && tb[1] == "n" && tb[2] == "t";
    }

    function _isFixedBytesType(string memory t) internal pure returns (bool) {
        bytes memory tb = bytes(t);
        return tb.length >= 5 && tb[0] == "b" && tb[1] == "y" && tb[2] == "t" && tb[3] == "e" && tb[4] == "s"
            && tb.length > 5;
    }

    function _concatBytes(bytes[] memory parts) internal pure returns (bytes memory result) {
        uint256 total;
        for (uint256 i = 0; i < parts.length; i++) {
            total += parts[i].length;
        }

        result = new bytes(total);
        uint256 offset;

        for (uint256 i = 0; i < parts.length; i++) {
            for (uint256 j = 0; j < parts[i].length; j++) {
                result[offset++] = parts[i][j];
            }
        }
    }
}
