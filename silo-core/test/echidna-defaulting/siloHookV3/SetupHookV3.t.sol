// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";

// Contracts
import {PartialLiquidation} from "silo-core/contracts/hooks/liquidation/PartialLiquidation.sol";
import {SiloHookV3} from "silo-core/contracts/hooks/SiloHookV3.sol";
import {SetupDefaulting} from "../siloHookV2/SetupDefaulting.t.sol";

/// @notice Setup contract for the invariant test Suite, inherited by Tester
contract SetupHookV3 is SetupDefaulting {
    function _hookImplementation() internal override returns (address hook) {
        hook = address(new SiloHookV3());
    }
}
