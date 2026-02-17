// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";

import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";

import {ManualLiquidationHelper} from "silo-core/contracts/utils/liquidationHelper/ManualLiquidationHelper.sol";

import {CommonDeploy} from "./_CommonDeploy.sol";
import {LiquidationHelperDeploy} from "./LiquidationHelperDeploy.s.sol";

/*
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/ManualLiquidationHelperDeploy.s.sol:ManualLiquidationHelperDeploy \
        --ffi --rpc-url $RPC_INJECTIVE \
        --broadcast --verify

    Resume verification:
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/ManualLiquidationHelperDeploy.s.sol:ManualLiquidationHelperDeploy \
        --ffi --rpc-url $RPC_INK \
        --verify \
        --verifier blockscout \
        --verifier-url $VERIFIER_URL_INK \
        --private-key $PRIVATE_KEY \
        --resume

    NOTICE: remember to register it in Tower
*/
contract ManualLiquidationHelperDeploy is LiquidationHelperDeploy {
    function run() public override returns (address manualLiquidation) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        address nativeToken = _nativeToken();
        address payable tokenReceiver = _tokenReceiver();

        console2.log("[ManualLiquidationHelperDeploy] nativeToken: ", nativeToken);
        require(nativeToken != address(0), "Native token is not set");
        
        console2.log("[ManualLiquidationHelperDeploy] tokensReceiver: ", tokenReceiver);
        require(tokenReceiver != address(0), "Token receiver is not set");

        vm.startBroadcast(deployerPrivateKey);

        manualLiquidation = address(new ManualLiquidationHelper(nativeToken, tokenReceiver));

        vm.stopBroadcast();

        _registerDeployment(manualLiquidation, SiloCoreContracts.MANUAL_LIQUIDATION_HELPER);
    }
}
