// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";
import {SiloVerifier} from "silo-core/deploy/silo/verifier/SiloVerifier.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {InjectiveWorkaround} from "silo-core/test/foundry/_common/InjectiveWorkaround.sol";

/*
FOUNDRY_INJECTIVE=true \
FOUNDRY_PROFILE=core CONFIG=0x0d419DC8128D5738a62753DeB8eA3508AEd95253 \
    EXTERNAL_PRICE_0=30 EXTERNAL_PRICE_1=1000 \
    forge script silo-core/deploy/silo/VerifySilo.s.sol \
    --ffi --rpc-url $RPC_XDC
 */
contract VerifySilo is Script, InjectiveWorkaround {
    function run() public {
        AddrLib.init();

        _customMocksOnInjective();

        emit log_named_address("VerifySilo", vm.envAddress("CONFIG"));

        SiloVerifier verifier = new SiloVerifier({
            _siloConfig: ISiloConfig(vm.envAddress("CONFIG")),
            _logDetails: true,
            _externalPrice0: vm.envUint("EXTERNAL_PRICE_0"),
            _externalPrice1: vm.envUint("EXTERNAL_PRICE_1")
        });

        verifier.verify();
    }
}
