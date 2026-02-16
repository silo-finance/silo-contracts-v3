// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {CommonDeploy} from "./_CommonDeploy.sol";

import {InterestRateModelV2FactoryDeploy} from "./InterestRateModelV2FactoryDeploy.s.sol";
import {InterestRateModelV2Deploy} from "./InterestRateModelV2Deploy.s.sol";
import {SiloHookV1Deploy} from "./SiloHookV1Deploy.s.sol";
import {SiloHookV2Deploy} from "./SiloHookV2Deploy.s.sol";
import {SiloHookV3Deploy} from "./SiloHookV3Deploy.s.sol";
import {SiloDeployerDeploy} from "./SiloDeployerDeploy.s.sol";
import {LiquidationHelperDeploy} from "./LiquidationHelperDeploy.s.sol";
import {TowerDeploy} from "./TowerDeploy.s.sol";
import {SiloLensDeploy} from "./SiloLensDeploy.s.sol";
import {SiloRouterV2Deploy} from "./SiloRouterV2Deploy.s.sol";
import {SiloFactoryDeploy} from "./SiloFactoryDeploy.s.sol";
import {SiloIncentivesControllerFactoryDeploy} from "silo-core/deploy/SiloIncentivesControllerFactoryDeploy.s.sol";
import {ManualLiquidationHelperDeploy} from "silo-core/deploy/ManualLiquidationHelperDeploy.s.sol";
import {DKinkIRMFactoryDeploy} from "silo-core/deploy/DKinkIRMFactoryDeploy.s.sol";
import {SiloImplementationDeploy} from "silo-core/deploy/SiloImplementationDeploy.s.sol";
import {
    LeverageRouterUsingSiloFlashloanWithGeneralSwapDeploy
} from "silo-core/deploy/LeverageRouterUsingSiloFlashloanWithGeneralSwapDeploy.s.sol";

/*
    FOUNDRY_PROFILE=core AGGREGATOR=1INCH \
        forge script silo-core/deploy/MainnetDeploy.s.sol \
        --ffi --rpc-url $RPC_BNB --broadcast --verify
 */
contract MainnetDeploy is CommonDeploy {
    function run() public {
        SiloFactoryDeploy siloFactoryDeploy = new SiloFactoryDeploy();
        SiloImplementationDeploy siloImplementationDeploy = new SiloImplementationDeploy();
        InterestRateModelV2FactoryDeploy interestRateModelV2ConfigFactoryDeploy =
            new InterestRateModelV2FactoryDeploy();
        InterestRateModelV2Deploy interestRateModelV2Deploy = new InterestRateModelV2Deploy();
        SiloHookV1Deploy siloHookV1Deploy = new SiloHookV1Deploy();
        SiloHookV2Deploy siloHookV2Deploy = new SiloHookV2Deploy();
        SiloHookV3Deploy siloHookV3Deploy = new SiloHookV3Deploy();
        SiloDeployerDeploy siloDeployerDeploy = new SiloDeployerDeploy();
        LiquidationHelperDeploy liquidationHelperDeploy = new LiquidationHelperDeploy();
        SiloLensDeploy siloLensDeploy = new SiloLensDeploy();
        TowerDeploy towerDeploy = new TowerDeploy();
        SiloRouterV2Deploy siloRouterV2Deploy = new SiloRouterV2Deploy();
        ManualLiquidationHelperDeploy manualLiquidationHelperDeploy = new ManualLiquidationHelperDeploy();
        DKinkIRMFactoryDeploy dkinkIRMFactoryDeploy = new DKinkIRMFactoryDeploy();

        SiloIncentivesControllerFactoryDeploy siloIncentivesControllerFactoryDeploy =
            new SiloIncentivesControllerFactoryDeploy();

        LeverageRouterUsingSiloFlashloanWithGeneralSwapDeploy leverageRouterDeploy =
            new LeverageRouterUsingSiloFlashloanWithGeneralSwapDeploy();

        siloFactoryDeploy.run();
        siloImplementationDeploy.run();
        // interestRateModelV2ConfigFactoryDeploy.run(); // not for V3
        dkinkIRMFactoryDeploy.run();
        // interestRateModelV2Deploy.run(); // not for V3
        siloHookV1Deploy.run();
        siloHookV2Deploy.run();
        siloHookV3Deploy.run();
        liquidationHelperDeploy.run();
        siloLensDeploy.run();
        siloRouterV2Deploy.run();
        siloIncentivesControllerFactoryDeploy.run();
        leverageRouterDeploy.run();

        // manualLiquidationHelperDeploy.run(); // not for V3
        // towerDeploy.run();

        // execute deployer at the end, to make sure we est factories
        siloDeployerDeploy.run();

    }
}
