// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// Utilities
import {VyperDeployer} from "./VyperDeployer.sol";
import {Data} from "../data/Data.sol";

// External dependencies
import {Ownable} from "openzeppelin5/access/Ownable.sol";

// silo-core dependencies
import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";
import {SiloFactory} from "silo-core/contracts/SiloFactory.sol";
import {ISiloDeployer, SiloDeployer} from "silo-core/contracts/SiloDeployer.sol";
import {Silo} from "silo-core/contracts/Silo.sol";
import {PartialLiquidation} from "silo-core/contracts/hooks/liquidation/PartialLiquidation.sol";
import {SiloHookV1} from "silo-core/contracts/hooks/SiloHookV1.sol";
import {SiloInternal} from "../internal_testing/SiloInternal.sol";
import {ShareProtectedCollateralToken} from "silo-core/contracts/utils/ShareProtectedCollateralToken.sol";
import {ShareDebtToken} from "silo-core/contracts/utils/ShareDebtToken.sol";
import {
    IInterestRateModelV2Factory,
    InterestRateModelV2Factory
} from "silo-core/contracts/interestRateModel/InterestRateModelV2Factory.sol";
import {
    IInterestRateModelV2,
    InterestRateModelV2
} from "silo-core/contracts/interestRateModel/InterestRateModelV2.sol";
import {
    IInterestRateModelV2Config,
    InterestRateModelV2Config
} from "silo-core/contracts/interestRateModel/InterestRateModelV2Config.sol";
import {IGaugeHookReceiver, GaugeHookReceiver} from "silo-core/contracts/hooks/gauge/GaugeHookReceiver.sol";
import {ISiloConfig, SiloConfig} from "silo-core/contracts/SiloConfig.sol";
import {CloneDeterministic} from "silo-core/contracts/lib/CloneDeterministic.sol";
import {Views} from "silo-core/contracts/lib/Views.sol";
import {DynamicKinkModelFactory} from "silo-core/contracts/interestRateModel/kink/DynamicKinkModelFactory.sol";
import {IDynamicKinkModelFactory} from "silo-core/contracts/interfaces/IDynamicKinkModelFactory.sol";
import {DynamicKinkModel} from "silo-core/contracts/interestRateModel/kink/DynamicKinkModel.sol";
import {ISiloIncentivesControllerFactory} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesControllerFactory.sol";
import {SiloIncentivesControllerFactory} from "silo-core/contracts/incentives/SiloIncentivesControllerFactory.sol";
import {
    IPermissionedLiquidationControllerFactory
} from "silo-core/contracts/incentives/functional/PermissionedLiquidationControllerFactory.sol";
import {PermissionedLiquidationControllerFactory} from "silo-core/contracts/incentives/functional/PermissionedLiquidationControllerFactory.sol";

contract Deployers is VyperDeployer, Data {
    address timelockAdmin = address(0xb4b3);

    /* ================================================================
                            State
       ================================================================ */

    // silo-core
    ISiloFactory siloFactory;
    IInterestRateModelV2Factory interestRateModelV2ConfigFactory;
    IInterestRateModelV2 interestRateModelV2;
    IGaugeHookReceiver hookReceiver;
    ISiloDeployer siloDeployer;
    PartialLiquidation liquidationModule;

    address SILO80_WETH20_TOKEN = 0x9CC64EE4CB672Bc04C54B00a37E1Ed75b2Cc19Dd;
    address SILO_TOKEN = 0x6f80310CA7F2C654691D1383149Fa1A57d8AB1f8;

    constructor() {}

    /* ================================================================
                            data setup
       ================================================================ */
    /// @notice used to set up addresses that can be used as oracles/receivers
    function _setupBasicData() internal {
        // set oracles
        oracles["DIA"] = address(0);
        oracles["CHAINLINK"] = address(0);
        oracles["UniV3-ETH-USDC-0.3"] = address(0);

        // hook receivers
        hookReceivers["GaugeHookReceiver"] = address(0);
    }

    function _initData(address mock0, address mock1) internal {
        // The FULL data relies on addresses set in _setupBasicData()
        siloData["FULL"] = ISiloConfig.InitData({
            deployer: timelockAdmin,
            daoFee: 0.15e18,
            deployerFee: 0.1e18,
            token0: _tokens["WETH"],
            solvencyOracle0: oracles["DIA"],
            maxLtvOracle0: oracles["CHAINLINK"],
            interestRateModel0: address(interestRateModelV2),
            maxLtv0: 0.75e18,
            lt0: 0.85e18,
            liquidationTargetLtv0: 0.85e18 * 0.9e19 / 1e18,
            liquidationFee0: 0.05e18,
            flashloanFee0: 0.01e18,
            callBeforeQuote0: true,
            hookReceiver: address(liquidationModule),
            token1: _tokens["USDC"],
            solvencyOracle1: oracles["UniV3-ETH-USDC-0.3"],
            maxLtvOracle1: oracles[""],
            interestRateModel1: address(interestRateModelV2),
            maxLtv1: 0.85e18,
            lt1: 0.95e18,
            liquidationTargetLtv1: 0.95e18 * 0.9e18 / 1e18,
            liquidationFee1: 0.025e18,
            flashloanFee1: 0.01e18,
            callBeforeQuote1: true
        });

        // We set up the mock data, without oracles and receivers
        ISiloConfig.InitData memory mocks = siloData["FULL"];
        mocks.token0 = mock0;
        mocks.token1 = mock1;
        mocks.solvencyOracle0 = address(0);
        mocks.solvencyOracle1 = address(0);
        mocks.maxLtvOracle0 = address(0);
        mocks.callBeforeQuote0 = false;
        mocks.callBeforeQuote1 = false;
        mocks.hookReceiver = address(0);

        siloData["MOCK"] = mocks;
    }

    /* ================================================================
                            silo-core deployments
       ================================================================ */

    function core_setUp(address feeReceiver) internal {
        core_deploySiloLiquidation();
        core_deploySiloFactory(feeReceiver);
        core_deployInterestRateConfigFactory();
        core_deployInterestRateModel();
        core_deployGaugeHookReceiver();
        core_deploySiloDeployer();
    }

    function core_deploySiloFactory(address feeReceiver) internal {
        address daoFeeReceiver = feeReceiver == address(0) ? address(0) : feeReceiver;

        siloFactory = ISiloFactory(address(new SiloFactory(daoFeeReceiver)));
    }

    function core_deployInterestRateConfigFactory() internal {
        interestRateModelV2ConfigFactory = IInterestRateModelV2Factory(address(new InterestRateModelV2Factory()));
    }

    function core_deployInterestRateModel() internal {
        (, interestRateModelV2) = interestRateModelV2ConfigFactory.create(presetIRMConfigs[0], bytes32(0));
    }

    function core_deployGaugeHookReceiver() internal {
        hookReceiver = IGaugeHookReceiver(address(new SiloHookV1()));
    }

    function core_deploySiloLiquidation() internal {
        liquidationModule = PartialLiquidation(address(new SiloHookV1()));
    }

    function core_deploySiloDeployer() internal {
        address dkinkIRMConfigFactory = address(new DynamicKinkModelFactory(new DynamicKinkModel()));
        address siloImpl = address(new Silo(siloFactory));
        address shareProtectedCollateralTokenImpl = address(new ShareProtectedCollateralToken());
        address shareDebtTokenImpl = address(new ShareDebtToken());
        address siloIncentivesControllerFactory = address(new SiloIncentivesControllerFactory());
        address permissionedLiquidationControllerFactory = address(new PermissionedLiquidationControllerFactory());
        
        siloDeployer = ISiloDeployer(
            address(
                new SiloDeployer(
                    interestRateModelV2ConfigFactory,
                    IDynamicKinkModelFactory(dkinkIRMConfigFactory),
                    siloFactory,
                    ISiloIncentivesControllerFactory(siloIncentivesControllerFactory),
                    IPermissionedLiquidationControllerFactory(siloIncentivesControllerFactory),
                    siloImpl,
                    shareProtectedCollateralTokenImpl,
                    shareDebtTokenImpl
                )
            )
        );
    }

    function _deploySiloConfig(
        ISiloConfig.InitData memory _siloInitData,
        address _siloImpl,
        address _shareProtectedCollateralTokenImpl,
        address _shareDebtTokenImpl
    ) internal returns (ISiloConfig siloConfig) {
        uint256 nextSiloId = siloFactory.getNextSiloId();
        uint256 creatorSiloCounter = siloFactory.creatorSiloCounter(msg.sender);

        ISiloConfig.ConfigData memory configData0;
        ISiloConfig.ConfigData memory configData1;

        (configData0, configData1) = Views.copySiloConfig(
            _siloInitData,
            siloFactory.daoFeeRange(),
            siloFactory.maxDeployerFee(),
            siloFactory.maxFlashloanFee(),
            siloFactory.maxLiquidationFee()
        );

        configData0.silo =
            CloneDeterministic.predictSilo0Addr(_siloImpl, creatorSiloCounter, address(siloFactory), msg.sender);

        configData1.silo =
            CloneDeterministic.predictSilo1Addr(_siloImpl, creatorSiloCounter, address(siloFactory), msg.sender);

        configData0.collateralShareToken = configData0.silo;
        configData1.collateralShareToken = configData1.silo;

        configData0.protectedShareToken = CloneDeterministic.predictShareProtectedCollateralToken0Addr(
            _shareProtectedCollateralTokenImpl, creatorSiloCounter, address(siloFactory), msg.sender
        );

        configData1.protectedShareToken = CloneDeterministic.predictShareProtectedCollateralToken1Addr(
            _shareProtectedCollateralTokenImpl, creatorSiloCounter, address(siloFactory), msg.sender
        );

        configData0.debtShareToken = CloneDeterministic.predictShareDebtToken0Addr(
            _shareDebtTokenImpl, creatorSiloCounter, address(siloFactory), msg.sender
        );

        configData1.debtShareToken = CloneDeterministic.predictShareDebtToken1Addr(
            _shareDebtTokenImpl, creatorSiloCounter, address(siloFactory), msg.sender
        );

        siloConfig = ISiloConfig(address(new SiloConfig(nextSiloId, configData0, configData1)));
    }
}
