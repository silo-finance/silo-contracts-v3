// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {CommonDeploy} from "./CommonDeploy.sol";

import {OracleForwarderFactoryDeploy} from "./OracleForwarderFactoryDeploy.sol";
import {ChainlinkV3OracleFactoryDeploy} from "./chainlink-v3-oracle/ChainlinkV3OracleFactoryDeploy.s.sol";
import {DIAOracleFactoryDeploy} from "./dia-oracle/DIAOracleFactoryDeploy.s.sol";
import {PythAggregatorFactoryDeploy} from "./pyth/PythAggregatorFactoryDeploy.s.sol";
import {OracleScalerFactoryDeploy} from "./oracle-scaler/OracleScalerFactoryDeploy.s.sol";

import {ERC4626OracleFactoryDeploy} from "./erc4626/ERC4626OracleFactoryDeploy.sol";
import {ERC4626OracleHardcodeQuoteFactoryDeploy} from "./erc4626/ERC4626OracleHardcodeQuoteFactoryDeploy.sol";
import {ERC4626OracleWithUnderlyingFactoryDeploy} from "./erc4626/ERC4626OracleWithUnderlyingFactoryDeploy.s.sol";

import {PendlePTOracleFactoryDeploy} from "./pendle/PendlePTOracleFactoryDeploy.s.sol";
import {PendlePTToAssetOracleFactoryDeploy} from "./pendle/PendlePTToAssetOracleFactoryDeploy.s.sol";
import {PendleLPTToSyOracleFactoryDeploy} from "./pendle/PendleLPTToSyOracleFactoryDeploy.s.sol";
import {PendleLPTToAssetOracleFactoryDeploy} from "./pendle/PendleLPTToAssetOracleFactoryDeploy.s.sol";
import {PendleWrapperLPTToAssetOracleFactoryDeploy} from "./pendle/PendleWrapperLPTToAssetOracleFactoryDeploy.s.sol";
import {PendleWrapperLPTToSyOracleFactoryDeploy} from "./pendle/PendleWrapperLPTToSyOracleFactoryDeploy.s.sol";
import {PTLinearOracleFactoryDeploy} from "./pendle/PTLinearOracleFactoryDeploy.s.sol";

import {ManageableOracleFactoryDeploy} from "./manageable/ManageableOracleFactoryDeploy.s.sol";
import {SiloVirtualAsset8DecimalsDeploy} from "./SiloVirtualAsset8DecimalsDeploy.s.sol";
/*
    FOUNDRY_PROFILE=oracles \
        forge script silo-oracles/deploy/MainnetDeploy.s.sol \
        --ffi --rpc-url $RPC_INJECTIVE --broadcast --slow --verify

    FOUNDRY_PROFILE=oracles \
        forge script silo-oracles/deploy/MainnetDeploy.s.sol \
        --ffi --rpc-url $RPC_INJECTIVE \
        --verify \
        --verifier blockscout \
        --verifier-url $VERIFIER_URL_INJECTIVE \
        --private-key $PRIVATE_KEY \
        --resume
*/
contract MainnetDeploy is CommonDeploy {
    function run() public {
        OracleForwarderFactoryDeploy oracleForwarderFactoryDeploy = new OracleForwarderFactoryDeploy();
        ChainlinkV3OracleFactoryDeploy chainlinkV3OracleFactoryDeploy = new ChainlinkV3OracleFactoryDeploy();
        DIAOracleFactoryDeploy diaOracleFactoryDeploy = new DIAOracleFactoryDeploy();
        PythAggregatorFactoryDeploy pythAggregatorFactoryDeploy = new PythAggregatorFactoryDeploy();
        OracleScalerFactoryDeploy oracleScalerFactoryDeploy = new OracleScalerFactoryDeploy();

        ERC4626OracleFactoryDeploy erc4626OracleFactoryDeploy = new ERC4626OracleFactoryDeploy();
        ERC4626OracleHardcodeQuoteFactoryDeploy erc4626OracleHardcodeQuoteFactoryDeploy =
            new ERC4626OracleHardcodeQuoteFactoryDeploy();
        ERC4626OracleWithUnderlyingFactoryDeploy erc4626OracleWithUnderlyingFactoryDeploy =
            new ERC4626OracleWithUnderlyingFactoryDeploy();

        PendlePTOracleFactoryDeploy pendlePTOracleFactoryDeploy = new PendlePTOracleFactoryDeploy();
        PendlePTToAssetOracleFactoryDeploy pendlePTToAssetOracleFactoryDeploy = new PendlePTToAssetOracleFactoryDeploy();
        PendleLPTToSyOracleFactoryDeploy pendleLPTToSyOracleFactoryDeploy = new PendleLPTToSyOracleFactoryDeploy();
        PendleLPTToAssetOracleFactoryDeploy pendleLPTToAssetOracleFactoryDeploy =
            new PendleLPTToAssetOracleFactoryDeploy();
        PendleWrapperLPTToAssetOracleFactoryDeploy pendleWrapperLPTToAssetOracleFactoryDeploy =
            new PendleWrapperLPTToAssetOracleFactoryDeploy();
        PendleWrapperLPTToSyOracleFactoryDeploy pendleWrapperLPTToSyOracleFactoryDeploy =
            new PendleWrapperLPTToSyOracleFactoryDeploy();
        PTLinearOracleFactoryDeploy ptLinearOracleFactoryDeploy = new PTLinearOracleFactoryDeploy();

        ManageableOracleFactoryDeploy manageableOracleFactoryDeploy = new ManageableOracleFactoryDeploy();
        SiloVirtualAsset8DecimalsDeploy siloVirtualAsset8DecimalsDeploy = new SiloVirtualAsset8DecimalsDeploy();

        // oracleForwarderFactoryDeploy.run();
        chainlinkV3OracleFactoryDeploy.run();
        // diaOracleFactoryDeploy.run();

        // erc4626OracleFactoryDeploy.run();
        // erc4626OracleHardcodeQuoteFactoryDeploy.run();
        // erc4626OracleWithUnderlyingFactoryDeploy.run();

        manageableOracleFactoryDeploy.run();

        oracleScalerFactoryDeploy.run();
        // pythAggregatorFactoryDeploy.run();

        // pendlePTOracleFactoryDeploy.run();
        // pendlePTToAssetOracleFactoryDeploy.run();
        // pendleLPTToSyOracleFactoryDeploy.run();
        // pendleLPTToAssetOracleFactoryDeploy.run();
        // pendleWrapperLPTToAssetOracleFactoryDeploy.run();
        // pendleWrapperLPTToSyOracleFactoryDeploy.run();
        // ptLinearOracleFactoryDeploy.run();

        // siloVirtualAsset8DecimalsDeploy.run();

        // UniswapV3 oracle deploy scripts are pinned to solc 0.7.6 and must be run separately.
    }
}
