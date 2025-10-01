// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {CommonDeploy} from "./_CommonDeploy.sol";
import {Debugger} from "common/utils/Debugger.sol";

/**
    forge script silo-core/deploy/DebuggerDeploy.s.sol \
    --ffi --rpc-url $RPC_XDC --legacy --broadcast --verify
*/
contract DebuggerDeploy is CommonDeploy {
    function run() public {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        vm.startBroadcast(deployerPrivateKey);

        Debugger d = new Debugger();

        vm.stopBroadcast();

        _registerDeployment(address(d), "Debugger.sol");
    }
}
