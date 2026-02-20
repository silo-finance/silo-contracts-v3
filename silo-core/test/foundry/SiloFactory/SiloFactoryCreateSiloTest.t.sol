// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";
import {IERC721Errors} from "openzeppelin5/interfaces/draft-IERC6093.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IInterestRateModelV2} from "silo-core/contracts/interfaces/IInterestRateModelV2.sol";
import {IInterestRateModelV2Config} from "silo-core/contracts/interfaces/IInterestRateModelV2Config.sol";
import {InterestRateModelV2} from "silo-core/contracts/interestRateModel/InterestRateModelV2.sol";
import {ICrossReentrancyGuard} from "silo-core/contracts/interfaces/ICrossReentrancyGuard.sol";
import {IHookReceiver} from "silo-core/contracts/interfaces/IHookReceiver.sol";

import {CloneDeterministic} from "silo-core/contracts/lib/CloneDeterministic.sol";
import {ISiloFactory} from "silo-core/contracts/SiloFactory.sol";
import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";
import {SiloConfigData} from "silo-core/deploy/input-readers/SiloConfigData.sol";
import {InterestRateModelConfigData} from "silo-core/deploy/input-readers/InterestRateModelConfigData.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";
import {Silo} from "silo-core/contracts/Silo.sol";
import {ShareProtectedCollateralToken} from "silo-core/contracts/utils/ShareProtectedCollateralToken.sol";
import {ShareDebtToken} from "silo-core/contracts/utils/ShareDebtToken.sol";

import {SiloLittleHelper} from "silo-core/test/foundry/_common/SiloLittleHelper.sol";

/*
forge test -vv --ffi --mc SiloFactoryCreateSiloTest
*/
contract SiloFactoryCreateSiloTest is SiloLittleHelper, IntegrationTest {
    string public constant SILO_TO_DEPLOY = SiloConfigsNames.SILO_LOCAL_NO_ORACLE_SILO;

    ISiloConfig siloConfig;
    SiloConfigData siloData;
    InterestRateModelConfigData modelData;

    event NewSilo(
        address indexed implementation,
        address indexed token0,
        address indexed token1,
        address silo0,
        address silo1,
        address siloConfig
    );

    function setUp() public {
        siloData = new SiloConfigData();
        modelData = new InterestRateModelConfigData();

        siloConfig = _setUpLocalFixture();

        siloFactory = ISiloFactory(getAddress(SiloCoreContracts.SILO_FACTORY));

        assertTrue(siloConfig.getConfig(address(silo0)).maxLtv != 0, "we need borrow to be allowed");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_createSilo
    */
    function test_createSilo() public {
        (, ISiloConfig.InitData memory initData,) = siloData.getConfigData(SILO_TO_DEPLOY);

        uint256 currentSiloId = 3000;
        assertEq(siloFactory.getNextSiloId(), currentSiloId + 1, "getNextSiloId does not match");
        assertTrue(siloFactory.isSilo(address(silo0)), "silo0 should exist in factory");
        assertTrue(siloFactory.isSilo(address(silo1)), "silo1 should exist in factory");

        address configFromFactory = siloFactory.idToSiloConfig(currentSiloId);
        assertEq(configFromFactory, address(siloConfig), "configFromFactory does not match");
        assertEq(configFromFactory, address(silo0.config()));
        assertEq(configFromFactory, address(silo1.config()));

        ISiloConfig.ConfigData memory configData0 = silo0.config().getConfig(address(silo0));
        ISiloConfig.ConfigData memory configData1 = silo0.config().getConfig(address(silo1));

        assertGe(configData0.daoFee, siloFactory.daoFeeRange().min, "configData0.daoFee.min");
        assertLe(configData0.daoFee, siloFactory.daoFeeRange().max, "configData0.daoFee.max");
        assertEq(configData0.deployerFee, initData.deployerFee, "configData0.deployerFee");
        assertEq(configData0.token, address(token0), "configData0.token");
        assertEq(configData1.token, address(token1), "configData0.token");

        assertTrue(configData0.hookReceiver != address(0), "configData0.hookReceiver");
        assertEq(configData0.hookReceiver, configData1.hookReceiver, "hookReceiver");

        assertTrue(configData0.silo != address(0), "configData0.silo");
        assertTrue(configData0.protectedShareToken != address(0), "configData0.protectedShareToken");
        assertTrue(configData0.collateralShareToken != address(0), "configData0.collateralShareToken");
        assertTrue(configData0.debtShareToken != address(0), "configData0.debtShareToken");
        assertEq(configData0.solvencyOracle, initData.solvencyOracle0, "configData0.solvencyOracle");
        assertEq(configData0.maxLtvOracle, initData.maxLtvOracle0, "configData0.maxLtvOracle");
        assertEq(configData0.maxLtv, initData.maxLtv0, "configData0.maxLtv");
        assertEq(configData0.lt, initData.lt0, "configData0.lt");
        assertEq(configData0.liquidationFee, initData.liquidationFee0, "configData0.liquidationFee");
        assertEq(configData0.flashloanFee, initData.flashloanFee0, "configData0.flashloanFee");
        assertEq(configData0.callBeforeQuote, initData.callBeforeQuote0, "configData0.callBeforeQuote");

        assertGe(configData1.daoFee, siloFactory.daoFeeRange().min, "configData1.daoFee.min");
        assertLe(configData1.daoFee, siloFactory.daoFeeRange().max, "configData1.daoFee.max");
        assertEq(configData1.deployerFee, initData.deployerFee, "configData1.deployerFee");
        assertTrue(configData1.silo != address(0), "configData1.silo");
        assertTrue(configData1.protectedShareToken != address(0), "configData1.protectedShareToken");
        assertTrue(configData1.collateralShareToken != address(0), "configData1.collateralShareToken");
        assertTrue(configData1.debtShareToken != address(0), "configData1.debtShareToken");
        assertEq(configData1.solvencyOracle, initData.solvencyOracle1, "configData1.solvencyOracle");
        assertEq(configData1.maxLtvOracle, initData.maxLtvOracle1, "configData1.maxLtvOracle");
        assertEq(configData1.maxLtv, initData.maxLtv1, "configData1.maxLtv");
        assertEq(configData1.lt, initData.lt1, "configData1.lt");
        assertEq(configData1.liquidationFee, initData.liquidationFee1, "configData1.liquidationFee");
        assertEq(configData1.flashloanFee, initData.flashloanFee1, "configData1.flashloanFee");
        assertEq(configData1.callBeforeQuote, initData.callBeforeQuote1, "configData1.callBeforeQuote");

        vm.expectRevert(ISilo.SiloInitialized.selector);
        ISilo(configData0.silo).initialize(siloConfig);

        vm.expectRevert(ISilo.SiloInitialized.selector);
        ISilo(configData1.silo).initialize(siloConfig);

        IInterestRateModelV2Config modelConfigAddr0 = InterestRateModelV2(configData0.interestRateModel).irmConfig();
        IInterestRateModelV2.Config memory irmConfigUsed0 = modelConfigAddr0.getConfig();

        (SiloConfigData.ConfigData memory siloConfigData,,) = siloData.getConfigData(SILO_TO_DEPLOY);
        IInterestRateModelV2.Config memory irmConfigExpected0 =
            modelData.getConfigData(siloConfigData.interestRateModelConfig0);

        assertEq(abi.encode(irmConfigUsed0), abi.encode(irmConfigExpected0));

        IInterestRateModelV2Config modelConfigAddr1 = InterestRateModelV2(configData1.interestRateModel).irmConfig();
        IInterestRateModelV2.Config memory irmConfigUsed1 = modelConfigAddr1.getConfig();

        IInterestRateModelV2.Config memory irmConfigExpected1 =
            modelData.getConfigData(siloConfigData.interestRateModelConfig1);

        assertEq(abi.encode(irmConfigUsed1), abi.encode(irmConfigExpected1));

        assertEq(siloFactory.ownerOf(currentSiloId), initData.deployer);
    }

    /*
    forge test -vv --ffi --mt test_createSilo_zeroes
    */
    function test_createSilo_zeroes() public {
        (, ISiloConfig.InitData memory initData,) = siloData.getConfigData(SILO_TO_DEPLOY);

        address siloImpl = address(new Silo(siloFactory));
        address shareProtectedCollateralTokenImpl = address(new ShareProtectedCollateralToken());
        address shareDebtTokenImpl = address(new ShareDebtToken());
        ISiloConfig config = ISiloConfig(makeAddr("siloConfig"));

        vm.expectRevert(ISiloFactory.ZeroAddress.selector); // silo config empty
        siloFactory.createSilo(
            ISiloConfig(address(0)),
            siloImpl,
            shareProtectedCollateralTokenImpl,
            shareDebtTokenImpl,
            initData.deployer,
            msg.sender
        );

        vm.expectRevert(ISiloFactory.ZeroAddress.selector); // silo impl empty
        siloFactory.createSilo(
            config, address(0), shareProtectedCollateralTokenImpl, shareDebtTokenImpl, initData.deployer, msg.sender
        );

        vm.expectRevert(ISiloFactory.ZeroAddress.selector); // shareProtectedCollateralTokenImpl empty
        siloFactory.createSilo(config, siloImpl, address(0), shareDebtTokenImpl, initData.deployer, msg.sender);

        vm.expectRevert(ISiloFactory.ZeroAddress.selector); // shareDebtTokenImpl empty
        siloFactory.createSilo(
            config, siloImpl, shareProtectedCollateralTokenImpl, address(0), initData.deployer, msg.sender
        );
    }

    /*
    forge test -vv --ffi --mt test_createSilo_invalidReceiver
    */
    function test_createSilo_invalidReceiver() public {
        address siloImpl = address(new Silo(siloFactory));
        address shareProtectedCollateralTokenImpl = address(new ShareProtectedCollateralToken());
        address shareDebtTokenImpl = address(new ShareDebtToken());

        ISiloConfig config = ISiloConfig(makeAddr("siloConfig"));

        _createSiloNewSiloEventMockCalls(siloImpl, shareProtectedCollateralTokenImpl, shareDebtTokenImpl, config);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(this)));
        siloFactory.createSilo(
            config, siloImpl, shareProtectedCollateralTokenImpl, shareDebtTokenImpl, address(this), msg.sender
        );
    }

    /*
    forge test -vv --ffi --mt test_createSilo_NewSiloEvent
    */
    function test_createSilo_NewSiloEvent() public {
        (, ISiloConfig.InitData memory initData,) = siloData.getConfigData(SILO_TO_DEPLOY);

        address siloImpl = address(new Silo(siloFactory));
        address shareProtectedCollateralTokenImpl = makeAddr("shareProtectedCollateralTokenImpl");
        address shareDebtTokenImpl = makeAddr("shareDebtTokenImpl");

        ISiloConfig config = ISiloConfig(makeAddr("siloConfig"));

        (address silo0, address silo1) = _createSiloNewSiloEventMockCalls(
            siloImpl, shareProtectedCollateralTokenImpl, shareDebtTokenImpl, config
        );

        vm.expectEmit(true, true, true, false);

        emit NewSilo(siloImpl, makeAddr("token0"), makeAddr("token1"), silo0, silo1, address(config));

        siloFactory.createSilo(
            config, siloImpl, shareProtectedCollateralTokenImpl, shareDebtTokenImpl, initData.deployer, msg.sender
        );
    }

    function _createSiloNewSiloEventMockCalls(
        address _siloImpl,
        address _shareProtectedCollateralTokenImpl,
        address _shareDebtTokenImpl,
        ISiloConfig _config
    ) internal returns (address silo0, address silo1) {
        uint256 creatorSiloCounter = siloFactory.creatorSiloCounter(msg.sender);

        ISiloConfig.ConfigData memory configData0;
        ISiloConfig.ConfigData memory configData1;
        configData0.hookReceiver = makeAddr("hookReceiver");
        configData1.hookReceiver = makeAddr("hookReceiver");

        silo0 = CloneDeterministic.predictSilo0Addr(_siloImpl, creatorSiloCounter, address(siloFactory), msg.sender);
        silo1 = CloneDeterministic.predictSilo1Addr(_siloImpl, creatorSiloCounter, address(siloFactory), msg.sender);

        vm.label(silo0, "silo0");
        vm.label(silo1, "silo1");

        address protectedShareToken0 = CloneDeterministic.predictShareProtectedCollateralToken0Addr(
            _shareProtectedCollateralTokenImpl, creatorSiloCounter, address(siloFactory), msg.sender
        );

        address protectedShareToken1 = CloneDeterministic.predictShareProtectedCollateralToken1Addr(
            _shareProtectedCollateralTokenImpl, creatorSiloCounter, address(siloFactory), msg.sender
        );

        address debtShareToken0 = CloneDeterministic.predictShareDebtToken0Addr(
            _shareDebtTokenImpl, creatorSiloCounter, address(siloFactory), msg.sender
        );

        address debtShareToken1 = CloneDeterministic.predictShareDebtToken1Addr(
            _shareDebtTokenImpl, creatorSiloCounter, address(siloFactory), msg.sender
        );

        configData0.collateralShareToken = silo0;
        configData0.protectedShareToken = protectedShareToken0;
        configData0.debtShareToken = debtShareToken0;

        configData1.collateralShareToken = silo1;
        configData1.protectedShareToken = protectedShareToken1;
        configData1.debtShareToken = debtShareToken1;

        vm.mockCall(
            address(_config),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, address(silo0)),
            abi.encode(configData0)
        );

        vm.mockCall(
            address(_config),
            abi.encodeWithSelector(ISiloConfig.getConfig.selector, address(silo1)),
            abi.encode(configData1)
        );

        vm.mockCall(
            address(_config),
            abi.encodeWithSelector(ISiloConfig.getAssetForSilo.selector, address(silo0)),
            abi.encode(makeAddr("token0"))
        );

        vm.mockCall(
            address(_config),
            abi.encodeWithSelector(ISiloConfig.getAssetForSilo.selector, address(silo1)),
            abi.encode(makeAddr("token1"))
        );

        vm.mockCall(
            address(_config),
            abi.encodeWithSelector(ISiloConfig.getShareTokens.selector, address(silo0)),
            abi.encode(protectedShareToken0, address(silo0), debtShareToken0)
        );

        vm.mockCall(
            address(_config),
            abi.encodeWithSelector(ISiloConfig.getShareTokens.selector, address(silo1)),
            abi.encode(protectedShareToken1, address(silo1), debtShareToken1)
        );

        vm.mockCall(
            address(_config),
            abi.encodeWithSelector(ICrossReentrancyGuard.reentrancyGuardEntered.selector),
            abi.encode(false)
        );

        vm.mockCall(
            address(_config),
            abi.encodeWithSelector(ISiloConfig.getSilos.selector),
            abi.encode(address(silo0), address(silo1))
        );

        vm.mockCall(
            configData0.hookReceiver,
            abi.encodeWithSelector(IHookReceiver.hookReceiverConfig.selector, address(silo0)),
            abi.encode(0, 0)
        );

        vm.mockCall(
            configData1.hookReceiver,
            abi.encodeWithSelector(IHookReceiver.hookReceiverConfig.selector, address(silo1)),
            abi.encode(0, 0)
        );
    }
}
