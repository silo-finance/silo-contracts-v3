// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {EmptySilo} from "silo-core/contracts/utils/siloWrappers/EmptySilo.sol";
import {EmptySiloArtifactLib} from "./EmptySiloArtifactLib.sol";

/*
    FOUNDRY_PROFILE=core_test forge test --mc EmptySiloTest
*/
contract EmptySiloTest is Test {
    EmptySilo internal _emptySilo;

    function setUp() public {
        _emptySilo = new EmptySilo();
    }

    function test_all_silo_abi_functions_are_covered() public view {
        string memory json = EmptySiloArtifactLib.siloArtifactJson();
        string[] memory keys = vm.parseJsonKeys(json, ".methodIdentifiers");

        EmptySiloArtifactLib.AbiFunctionCase[] memory cases = EmptySiloArtifactLib.loadAbiFunctionCases();
        assertEq(keys.length, cases.length, "artifact function count mismatch");

        for (uint256 i = 0; i < cases.length; i++) {
            _assertHasMethodIdentifier(keys, cases[i].signature);
        }
    }

    function test_all_silo_abi_functions_behavior() public {
        EmptySiloArtifactLib.AbiFunctionCase[] memory cases = EmptySiloArtifactLib.loadAbiFunctionCases();
        bytes memory notSupportedError = abi.encodeWithSelector(EmptySilo.NotSupported.selector);

        for (uint256 i = 0; i < cases.length; i++) {
            (bool success, bytes memory result) = address(_emptySilo).call(cases[i].callData);

            if (_shouldRevert(cases[i].signature, cases[i].shouldRevert)) {
                assertFalse(success, _failureMessage(cases[i].signature, "state-changing method should revert"));
                assertEq(
                    result,
                    notSupportedError,
                    _failureMessage(cases[i].signature, "unexpected revert data")
                );
            } else {
                assertTrue(success, _failureMessage(cases[i].signature, "method should not revert"));

                if (_isVersionSignature(cases[i].signature)) {
                    assertEq(
                        result,
                        abi.encode(_emptySilo.VERSION()),
                        _failureMessage(cases[i].signature, "VERSION should return contract version")
                    );
                } else {
                    assertEq(
                        result,
                        cases[i].expectedReturnData,
                        _failureMessage(cases[i].signature, "unexpected return data")
                    );
                }
            }
        }
    }

    function _assertHasMethodIdentifier(string[] memory keys, string memory expected) internal pure {
        for (uint256 i = 0; i < keys.length; i++) {
            if (keccak256(bytes(keys[i])) == keccak256(bytes(expected))) return;
        }

        revert(string.concat("missing method in artifact: ", expected));
    }

    function _shouldRevert(string memory signature, bool artifactMarksAsStateChanging)
        internal
        pure
        returns (bool)
    {
        if (_isNonRevertingException(signature)) return false;

        return artifactMarksAsStateChanging;
    }

    function _isNonRevertingException(string memory signature) internal pure returns (bool) {
        bytes32 sigHash = keccak256(bytes(signature));

        return sigHash == keccak256("VERSION()")
            || sigHash == keccak256("accrueInterest()")
            || sigHash == keccak256("accrueInterestForConfig(address,uint256,uint256)");
    }

    function _isVersionSignature(string memory signature) internal pure returns (bool) {
        return keccak256(bytes(signature)) == keccak256(bytes("VERSION()"));
    }

    function _failureMessage(string memory signature, string memory reason)
        internal
        pure
        returns (string memory message)
    {
        return string.concat(signature, " - ", reason);
    }
}
