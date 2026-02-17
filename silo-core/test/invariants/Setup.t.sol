// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {console2} from "forge-std/console2.sol";

// Utils
import {Actor} from "./utils/Actor.sol";
import {Clones} from "openzeppelin5/proxy/Clones.sol";

// Contracts
import {SiloFactory} from "silo-core/contracts/SiloFactory.sol";
import {Silo} from "silo-core/contracts/Silo.sol";
import {ShareProtectedCollateralToken} from "silo-core/contracts/utils/ShareProtectedCollateralToken.sol";
import {ShareDebtToken} from "silo-core/contracts/utils/ShareDebtToken.sol";
import {IInterestRateModelV2} from "silo-core/contracts/interestRateModel/InterestRateModelV2.sol";
import {PartialLiquidation} from "silo-core/contracts/hooks/liquidation/PartialLiquidation.sol";
import {SiloHookV1} from "silo-core/contracts/hooks/SiloHookV1.sol";
import {ISiloDeployer, SiloDeployer} from "silo-core/contracts/SiloDeployer.sol";
import {CloneDeterministic} from "silo-core/contracts/lib/CloneDeterministic.sol";
import {Views} from "silo-core/contracts/lib/Views.sol";
import {SiloLens} from "silo-core/contracts/SiloLens.sol";

// Test Contracts
import {BaseTest} from "./base/BaseTest.t.sol";
import {MockFlashLoanReceiver} from "./helpers/FlashLoanReceiver.sol";

// Mock Contracts
import {TestERC20} from "./utils/mocks/TestERC20.sol";
import {MockSiloOracle} from "./utils/mocks/MockSiloOracle.sol";

// Interfaces
import {ISiloConfig, SiloConfig} from "silo-core/contracts/SiloConfig.sol";
import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";
import {
    IInterestRateModelV2Factory,
    InterestRateModelV2Factory
} from "silo-core/contracts/interestRateModel/InterestRateModelV2Factory.sol";
import {ISilo} from "silo-core/contracts/Silo.sol";
import {DynamicKinkModelFactory} from "silo-core/contracts/interestRateModel/kink/DynamicKinkModelFactory.sol";
import {IDynamicKinkModelFactory} from "silo-core/contracts/interfaces/IDynamicKinkModelFactory.sol";
import {DynamicKinkModel} from "silo-core/contracts/interestRateModel/kink/DynamicKinkModel.sol";

/// @notice Setup contract for the invariant test Suite, inherited by Tester
contract Setup is BaseTest {
    function _setUp() internal virtual {
        // Deploy assets
        _deployAssets();

        // Deploy protocol core contracts
        _deployCoreProtocol(address(this));

        // Deploy Oracles
        _deployOracles();

        // Deploy Silos
        _deploySilos();

        // Initialize hook
        _initHook();

        // Deploy External contracts
        _deployExternalContracts();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          SETUP FUNCTIONS                                  //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _deployAssets() internal virtual {
        console2.log("/_deployAssets/");
        _asset0 = new TestERC20("Test Token0", "TT0", 18);
        _asset1 = new TestERC20("Test Token1", "TT1", 6);
        baseAssets.push(address(_asset0));
        baseAssets.push(address(_asset1));
    }

    function _deployCoreProtocol(address feeReceiver) internal {
        console2.log("/_deployCoreProtocol/");
        core_deploySiloLiquidation();
        core_deploySiloFactory(feeReceiver);
        core_deployInterestRateConfigFactory();
        core_deployInterestRateModel();
        core_deploySiloDeployer();
    }

    function _deployOracles() internal {
        console2.log("/_deployOracles/");
        oracle0 = address(new MockSiloOracle(address(_asset0), 1 ether, QUOTE_TOKEN_ADDRESS, 18));
        oracle1 = address(new MockSiloOracle(address(_asset1), 1 ether, QUOTE_TOKEN_ADDRESS, 18));
    }

    function _deploySilos() internal {
        console2.log("/_deploySilos/");
        // Setup initData
        _initData(address(_asset0), address(_asset1));

        // Deploy silo config
        siloConfig = _deploySiloConfig(
            siloData[_siloInitDataIdentifier()], siloImpl, shareProtectedCollateralTokenImpl, shareDebtTokenImpl
        );

        // Deploy silos
        siloFactory.createSilo(
            siloConfig,
            siloImpl,
            shareProtectedCollateralTokenImpl,
            shareDebtTokenImpl,
            siloData[_siloInitDataIdentifier()].deployer,
            msg.sender
        );

        (_vault0, _vault1) = siloConfig.getSilos();
        vault0 = Silo(payable(_vault0));
        vault1 = Silo(payable(_vault1));
        silos.push(_vault0);
        silos.push(_vault1);

        // Store all collateral (silos) & debt shareTokens in helper arrays
        shareTokens.push(_vault0);
        shareTokens.push(_vault1);

        (address debtToken0,) = siloConfig.getDebtShareTokenAndAsset(address(vault0));
        shareTokens.push(debtToken0);
        (address debtToken1,) = siloConfig.getDebtShareTokenAndAsset(address(vault1));
        shareTokens.push(debtToken1);

        debtTokens.push(debtToken0);
        debtTokens.push(debtToken1);

        // Store the protected collateral tokens in an array
        (, address protectedCollateralToken0) =
            siloConfig.getCollateralShareTokenAndAsset(address(vault0), ISilo.CollateralType.Protected);

        (, address protectedCollateralToken1) =
            siloConfig.getCollateralShareTokenAndAsset(address(vault1), ISilo.CollateralType.Protected);

        protectedTokens.push(protectedCollateralToken0);
        protectedTokens.push(protectedCollateralToken1);
    }

    function _initHook() internal virtual {
        console2.log("/_initHook/");
        liquidationModule.initialize(siloConfig, abi.encode(address(this)));
    }

    function _siloInitDataIdentifier() internal pure virtual returns (string memory) {
        return "MOCK";
    }

    /// @notice Setup liquidation module and flashLoan receiver
    function _deployExternalContracts() internal {
        console2.log("/_deployExternalContracts/");
        flashLoanReceiver = address(new MockFlashLoanReceiver());

        siloLens = new SiloLens();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   SILO-CORE SETUP FUNCTIONS                               //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function core_deploySiloLiquidation() internal virtual {
        console2.log("/core_deploySiloLiquidation (SiloHookV1)/");
        liquidationModule = PartialLiquidation(_cloneHook());
    }

    function _cloneHook() internal virtual returns (address hook) {
        hook = Clones.clone(_hookImplementation());
    }

    function _hookImplementation() internal virtual returns (address hook) {
        hook = address(new SiloHookV1());
    }

    function core_deploySiloFactory(address feeReceiver) internal {
        console2.log("/core_deploySiloFactory/");
        address daoFeeReceiver = feeReceiver == address(0) ? address(0) : feeReceiver;

        siloFactory = ISiloFactory(address(new SiloFactory(daoFeeReceiver)));
    }

    function core_deployInterestRateConfigFactory() internal {
        console2.log("/core_deployInterestRateConfigFactory/");
        interestRateModelV2ConfigFactory = IInterestRateModelV2Factory(address(new InterestRateModelV2Factory()));
    }

    function core_deployInterestRateModel() internal {
        // set preset IRM configs
        presetIRMConfigs.push(
            IInterestRateModelV2.Config({
                uopt: 500000000000000000,
                ucrit: 900000000000000000,
                ulow: 300000000000000000,
                ki: 146805,
                kcrit: 317097919838,
                klow: 105699306613,
                klin: 4439370878,
                beta: 69444444444444,
                ri: 0,
                Tcrit: 0
            })
        );

        // Deploy interestRateModel
        (, interestRateModelV2) = interestRateModelV2ConfigFactory.create(presetIRMConfigs[0], "");
    }

    function core_deploySiloDeployer() internal {
        console2.log("/core_deploySiloDeployer/");
        address dkinkIRMConfigFactory = address(new DynamicKinkModelFactory(new DynamicKinkModel()));
        siloImpl = address(new Silo(siloFactory));
        shareProtectedCollateralTokenImpl = address(new ShareProtectedCollateralToken());
        shareDebtTokenImpl = address(new ShareDebtToken());

        siloDeployer = ISiloDeployer(
            address(
                new SiloDeployer(
                    interestRateModelV2ConfigFactory,
                    IDynamicKinkModelFactory(dkinkIRMConfigFactory),
                    siloFactory,
                    siloImpl,
                    shareProtectedCollateralTokenImpl,
                    shareDebtTokenImpl
                )
            )
        );
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                            HELPERS                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _deploySiloConfig(
        ISiloConfig.InitData memory _siloInitData,
        address _siloImpl,
        address _shareProtectedCollateralTokenImpl,
        address _shareDebtTokenImpl
    ) internal returns (ISiloConfig siloConfig_) {
        console2.log("/_deploySiloConfig/");
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

        siloConfig_ = ISiloConfig(address(new SiloConfig(nextSiloId, configData0, configData1)));
    }

    function _initData(address mock0, address mock1) internal virtual {
        // The FULL data relies on addresses set in _setupBasicData()
        siloData["FULL"] = ISiloConfig.InitData({
            deployer: address(this),
            daoFee: 0.15e18,
            deployerFee: 0.1e18,
            token0: address(_asset0),
            solvencyOracle0: oracle0,
            maxLtvOracle0: oracle0,
            interestRateModel0: address(interestRateModelV2),
            maxLtv0: 0.75e18,
            lt0: 0.85e18,
            liquidationTargetLtv0: 0.85e18 * 0.9e18 / 1e18,
            liquidationFee0: 0.05e18,
            flashloanFee0: 0.01e18,
            callBeforeQuote0: true,
            hookReceiver: address(liquidationModule),
            token1: address(_asset1),
            solvencyOracle1: oracle1,
            maxLtvOracle1: oracle1,
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
        mocks.maxLtvOracle0 = address(0);
        mocks.maxLtvOracle1 = address(0);
        mocks.callBeforeQuote0 = false;
        mocks.callBeforeQuote1 = false;

        siloData["MOCK"] = mocks;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          ACTOR SETUP                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Deploy protocol actors and initialize their balances
    function _setUpActors() internal virtual {
        console2.log("/_setUpActors/");
        // Initialize the three actors of the fuzzers
        address[] memory addresses = new address[](3);
        addresses[0] = USER1;
        addresses[1] = USER2;
        addresses[2] = USER3;

        // Initialize the tokens array
        address[] memory tokens = new address[](2);
        tokens[0] = address(_asset0);
        tokens[1] = address(_asset1);

        address[] memory contracts = new address[](3);
        contracts[0] = address(_vault0);
        contracts[1] = address(_vault1);
        contracts[2] = address(liquidationModule);

        for (uint256 i; i < NUMBER_OF_ACTORS; i++) {
            // Deploy actor proxies and approve system contracts
            address _actor = _setUpActor(addresses[i], tokens, contracts);

            // Mint initial balances to actors
            for (uint256 j = 0; j < tokens.length; j++) {
                TestERC20 _token = TestERC20(tokens[j]);
                _token.mint(_actor, INITIAL_BALANCE);
            }

            actorAddresses.push(_actor);
        }
    }

    /// @notice Deploy an actor proxy contract for a user address
    /// @param userAddress Address of the user
    /// @param tokens Array of token addresses
    /// @param contracts Array of contract addresses to aprove tokens to
    /// @return actorAddress Address of the deployed actor
    function _setUpActor(address userAddress, address[] memory tokens, address[] memory contracts)
        internal
        virtual
        returns (address actorAddress)
    {
        bool success;
        Actor _actor = new Actor(tokens, contracts);
        actors[userAddress] = _actor;
        (success,) = address(_actor).call{value: INITIAL_ETH_BALANCE}("");
        assert(success);
        actorAddress = address(_actor);
    }
}
