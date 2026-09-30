// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";

import {IInterestRateModelV2} from "silo-core/contracts/interfaces/IInterestRateModelV2.sol";
import {IInterestRateModelV2Config} from "silo-core/contracts/interfaces/IInterestRateModelV2Config.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {SiloLens} from "silo-core/contracts/SiloLens.sol";

import {console} from "forge-std/console.sol";

interface IRMGetters {
    struct Setup {
        // ri ≥ 0 – initial value of the integrator
        int128 ri;
        // Tcrit ≥ 0 - the time during which the utilization exceeds the critical value
        int128 Tcrit;
        IInterestRateModelV2Config config;
    }

    function getSetup(address _silo) external view returns (Setup memory setup);
}

// FOUNDRY_PROFILE=core_test forge test --mc SiloDebugTest --ffi -vvv
contract SiloDebugTest is IntegrationTest {
    address internal constant _SILO_ADDR = 0x7abd3124E1e2F5f8aBF8b862d086647A5141bf4c;
    address internal constant _IRM_ADDR = 0x9d33d45AA7E1B45c65EA4b36b0c586B58a4796cE;

    IInterestRateModelV2 internal constant _IRM = IInterestRateModelV2(_IRM_ADDR);
    IRMGetters internal constant _IRM_GETTERS = IRMGetters(_IRM_ADDR);

    function setUp() public {
        vm.createSelectFork(getChainRpcUrl(ARBITRUM_ONE_ALIAS), 279148740);

        vm.label(address(_IRM), "irm");
        vm.label(_SILO_ADDR, "silo");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mc SiloDebugTest --mt test_skip_It --ffi -vvv
    */
    function test_skip_It() public view {
        // IInterestRateModelV2.ConfigWithState memory config = _IRM.getConfig(_SILO_ADDR);

        IRMGetters.Setup memory setup = _IRM_GETTERS.getSetup(_SILO_ADDR);

        console.log("ri: ", uint256(int256(setup.ri)));
        console.log("Tcrit: ", uint256(int256(setup.Tcrit)));
        console.log("config: ", address(setup.config));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mc SiloDebugTest --mt test_skip_siloLens_getLtv --ffi -vvv
    */
    function test_skip_siloLens_getLtv() public {
        SiloLens siloLens = SiloLens(0xF56ccaa52f95C7CCE6c21df9636a5Dcefa22aa96);

        address borrower = 0xdEDcF5806c4968C6397eeE97e68047bdA339d0c1;

        // this silo is not compatible with lens, it is from different deployment
        ISilo silo = ISilo(0x5d216642CE5936177f39EE12d57b1fE0d934bcb1);
        vm.expectRevert();
        siloLens.getLtv(silo, borrower);

        // silo from newest deployment
        silo = ISilo(0x0f3E42679f6Cf6Ee00b7eAC7b1676CA044615402);
        console.log("ltv: ", siloLens.getLtv(silo, borrower));
    }
}
