// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {DynamicKinkModelHandlers} from "silo-core/test/echidna-dkink-irm/DynamicKinkModelHandlers.t.sol";

/// @title RcompInvariants
/// @notice Implements specific invariants for the DynamicKinkModel Interest Rate Model
abstract contract RcompInvariants is DynamicKinkModelHandlers {
    function assert_rcomp_bounds(uint24 _timeAddition) public view {
        uint256 rcomp = _irm.getCompoundInterestRate(address(_siloMock), block.timestamp + _timeAddition);
        assert(rcomp <= _siloMock.calculateMaxRcomp(block.timestamp + _timeAddition));
    }

    function echidna_rcomp_bounds() public view returns (bool) {
        assert_rcomp_bounds(0);

        return true;
    }
}
