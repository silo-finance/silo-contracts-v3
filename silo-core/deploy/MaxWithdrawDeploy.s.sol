// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";

import {CommonDeploy} from "./_CommonDeploy.sol";

import {MaxWithdraw} from "silo-core/contracts/utils/liquidationHelper/MaxWithdraw.sol";

/*
    FOUNDRY_PROFILE=core forge clean
    FOUNDRY_PROFILE=core forge build --force

    XDC chain deployment use --legacy flag

    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/MaxWithdrawDeploy.s.sol \
        --ffi --rpc-url $RPC_SONIC --broadcast --verify --legacy

*/
contract MaxWithdrawDeploy is CommonDeploy {
    function run() public returns (MaxWithdraw maxWithdraw) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        vm.startBroadcast(deployerPrivateKey);
        maxWithdraw = new MaxWithdraw();
        vm.stopBroadcast();

        console2.log("New MaxWithdraw deployed", address(maxWithdraw));
    }
}
