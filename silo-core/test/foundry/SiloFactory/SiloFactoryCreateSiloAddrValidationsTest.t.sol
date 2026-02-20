// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ICrossReentrancyGuard} from "silo-core/contracts/interfaces/ICrossReentrancyGuard.sol";
import {IHookReceiver} from "silo-core/contracts/interfaces/IHookReceiver.sol";

import {CloneDeterministic} from "silo-core/contracts/lib/CloneDeterministic.sol";
import {ISiloFactory} from "silo-core/contracts/SiloFactory.sol";
import {Silo} from "silo-core/contracts/Silo.sol";
import {ShareProtectedCollateralToken} from "silo-core/contracts/utils/ShareProtectedCollateralToken.sol";
import {ShareDebtToken} from "silo-core/contracts/utils/ShareDebtToken.sol";
import {SiloFactory} from "silo-core/contracts/SiloFactory.sol";


// solhint-disable func-name-mixedcase

/*
FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc SiloFactoryCreateSiloAddrValidationsTest
*/
contract SiloFactoryCreateSiloAddrValidationsTest is IntegrationTest {
    enum ExpectedRevertPlaces {
        none,
        siloValidation,
        shareTokenSilo0,
        shareTokenSilo1
    }

    ISiloFactory public siloFactory;
    ISiloConfig public siloConfig = ISiloConfig(makeAddr("siloConfig"));

    address public siloImpl;
    address public shareProtectedCollateralTokenImpl;
    address public shareDebtTokenImpl;

    address public silo0;
    address public silo1;
    address public protectedShareToken0;
    address public protectedShareToken1;
    address public debtShareToken0;
    address public debtShareToken1;

    function setUp() public {
        siloFactory = ISiloFactory(address(new SiloFactory(makeAddr("daoFeeReceiver"))));

        siloImpl = address(new Silo(siloFactory));
        shareProtectedCollateralTokenImpl = address(new ShareProtectedCollateralToken());
        shareDebtTokenImpl = address(new ShareDebtToken());

        (silo0, silo1, protectedShareToken0, protectedShareToken1, debtShareToken0, debtShareToken1) = _clone();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_createSilo_success_creatorSiloCounter
    */
    function test_createSiloSuccessCreatorSiloCounter() public {
        _createSiloMockCalls(
            silo0,
            silo1,
            silo0,
            silo1,
            protectedShareToken0,
            protectedShareToken1,
            debtShareToken0,
            debtShareToken1,
            ExpectedRevertPlaces.none
        );

        uint256 creatorSiloCounterBefore = siloFactory.creatorSiloCounter(msg.sender);

        siloFactory.createSilo(
            siloConfig, siloImpl, shareProtectedCollateralTokenImpl, shareDebtTokenImpl, msg.sender, msg.sender
        );

        uint256 creatorSiloCounterAfter = siloFactory.creatorSiloCounter(msg.sender);

        assertEq(creatorSiloCounterAfter, creatorSiloCounterBefore + 1, "creatorSiloCounter should be incremented");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_createSilo_invalidSilo
    */
    function test_createSilo_invalidSilo() public {
        // invalid silo0
        address invalidSilo0 = makeAddr("invalidSilo0");
        vm.label(invalidSilo0, "invalidSilo0");

        _createSiloMockCalls(
            invalidSilo0,
            silo1,
            silo0,
            silo1,
            protectedShareToken0,
            protectedShareToken1,
            debtShareToken0,
            debtShareToken1,
            ExpectedRevertPlaces.siloValidation
        );

        vm.expectRevert(ISiloFactory.ConfigMismatchSilo.selector);

        siloFactory.createSilo(
            siloConfig, siloImpl, shareProtectedCollateralTokenImpl, shareDebtTokenImpl, msg.sender, msg.sender
        );

        // invalid silo1
        address invalidSilo1 = makeAddr("invalidSilo1");
        vm.label(invalidSilo1, "invalidSilo1");

        _createSiloMockCalls(
            silo0,
            invalidSilo1,
            silo0,
            silo1,
            protectedShareToken0,
            protectedShareToken1,
            debtShareToken0,
            debtShareToken1,
            ExpectedRevertPlaces.siloValidation
        );

        vm.expectRevert(ISiloFactory.ConfigMismatchSilo.selector);

        siloFactory.createSilo(
            siloConfig, siloImpl, shareProtectedCollateralTokenImpl, shareDebtTokenImpl, msg.sender, msg.sender
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_createSilo_invalidCollateralShareTokens
    */
    function test_createSilo_invalidCollateralShareTokens() public {
        // invalid collateralShareToken0
        address invalidCollateralShareToken0 = makeAddr("invalidCollateralShareToken0");
        vm.label(invalidCollateralShareToken0, "invalidCollateralShareToken0");

        _createSiloMockCalls(
            silo0,
            silo1,
            invalidCollateralShareToken0,
            silo1,
            protectedShareToken0,
            protectedShareToken1,
            debtShareToken0,
            debtShareToken1,
            ExpectedRevertPlaces.shareTokenSilo0
        );

        vm.expectRevert(ISiloFactory.ConfigMismatchShareCollateralToken.selector);

        siloFactory.createSilo(
            siloConfig, siloImpl, shareProtectedCollateralTokenImpl, shareDebtTokenImpl, msg.sender, msg.sender
        );

        // invalid collateralShareToken1
        address invalidCollateralShareToken1 = makeAddr("invalidCollateralShareToken1");
        vm.label(invalidCollateralShareToken1, "invalidCollateralShareToken1");

        _createSiloMockCalls(
            silo0,
            silo1,
            silo0,
            invalidCollateralShareToken1,
            protectedShareToken0,
            protectedShareToken1,
            debtShareToken0,
            debtShareToken1,
            ExpectedRevertPlaces.shareTokenSilo1
        );

        vm.expectRevert(ISiloFactory.ConfigMismatchShareCollateralToken.selector);

        siloFactory.createSilo(
            siloConfig, siloImpl, shareProtectedCollateralTokenImpl, shareDebtTokenImpl, msg.sender, msg.sender
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_createSilo_invalidDebtShareTokens
    */
    function test_createSilo_invalidDebtShareTokens() public {
        // invalid debtShareToken0
        address invalidDebtShareToken0 = makeAddr("invalidDebtShareToken0");
        vm.label(invalidDebtShareToken0, "invalidDebtShareToken0");

        _createSiloMockCalls(
            silo0,
            silo1,
            silo0,
            silo1,
            protectedShareToken0,
            protectedShareToken1,
            invalidDebtShareToken0,
            debtShareToken1,
            ExpectedRevertPlaces.shareTokenSilo0
        );

        vm.expectRevert(ISiloFactory.ConfigMismatchShareDebtToken.selector);

        siloFactory.createSilo(
            siloConfig, siloImpl, shareProtectedCollateralTokenImpl, shareDebtTokenImpl, msg.sender, msg.sender
        );

        // invalid debtShareToken1
        address invalidDebtShareToken1 = makeAddr("invalidDebtShareToken1");
        vm.label(invalidDebtShareToken1, "invalidDebtShareToken1");

        _createSiloMockCalls(
            silo0,
            silo1,
            silo0,
            silo1,
            protectedShareToken0,
            protectedShareToken1,
            debtShareToken0,
            invalidDebtShareToken1,
            ExpectedRevertPlaces.shareTokenSilo1
        );

        vm.expectRevert(ISiloFactory.ConfigMismatchShareDebtToken.selector);

        siloFactory.createSilo(
            siloConfig, siloImpl, shareProtectedCollateralTokenImpl, shareDebtTokenImpl, msg.sender, msg.sender
        );
    }

    function _clone()
        internal
        returns (
            address createdSilo0,
            address createdSilo1,
            address createdProtectedShareToken0,
            address createdProtectedShareToken1,
            address createdDebtShareToken0,
            address createdDebtShareToken1
        )
    {
        uint256 creatorSiloCounter = siloFactory.creatorSiloCounter(msg.sender);

        createdSilo0 =
            CloneDeterministic.predictSilo0Addr(siloImpl, creatorSiloCounter, address(siloFactory), msg.sender);

        createdSilo1 =
            CloneDeterministic.predictSilo1Addr(siloImpl, creatorSiloCounter, address(siloFactory), msg.sender);

        createdProtectedShareToken0 = CloneDeterministic.predictShareProtectedCollateralToken0Addr(
            shareProtectedCollateralTokenImpl, creatorSiloCounter, address(siloFactory), msg.sender
        );

        createdProtectedShareToken1 = CloneDeterministic.predictShareProtectedCollateralToken1Addr(
            shareProtectedCollateralTokenImpl, creatorSiloCounter, address(siloFactory), msg.sender
        );

        createdDebtShareToken0 = CloneDeterministic.predictShareDebtToken0Addr(
            shareDebtTokenImpl, creatorSiloCounter, address(siloFactory), msg.sender
        );

        createdDebtShareToken1 = CloneDeterministic.predictShareDebtToken1Addr(
            shareDebtTokenImpl, creatorSiloCounter, address(siloFactory), msg.sender
        );

        vm.label(createdSilo0, "silo0");
        vm.label(createdSilo1, "silo1");
        vm.label(createdProtectedShareToken0, "protectedShareToken0");
        vm.label(createdProtectedShareToken1, "protectedShareToken1");
        vm.label(createdDebtShareToken0, "debtShareToken0");
        vm.label(createdDebtShareToken1, "debtShareToken1");
    }

    function _createSiloMockCalls(
        address _silo0,
        address _silo1,
        address _collateralShareToken0,
        address _collateralShareToken1,
        address _protectedShareToken0,
        address _protectedShareToken1,
        address _debtShareToken0,
        address _debtShareToken1,
        ExpectedRevertPlaces _expectedRevertPlace
    ) internal {
        ISiloConfig.ConfigData memory configData0;
        ISiloConfig.ConfigData memory configData1;
        configData0.hookReceiver = makeAddr("hookReceiver");
        configData1.hookReceiver = makeAddr("hookReceiver");

        configData0.collateralShareToken = _collateralShareToken0;
        configData0.protectedShareToken = _protectedShareToken0;
        configData0.debtShareToken = _debtShareToken0;

        configData1.collateralShareToken = _collateralShareToken1;
        configData1.protectedShareToken = _protectedShareToken1;
        configData1.debtShareToken = _debtShareToken1;

        bytes memory data = abi.encodeWithSelector(ISiloConfig.getSilos.selector);
        vm.mockCall(address(siloConfig), data, abi.encode(_silo0, _silo1));
        vm.expectCall(address(siloConfig), data);

        if (_expectedRevertPlace == ExpectedRevertPlaces.siloValidation) return;

        data = abi.encodeWithSelector(ISiloConfig.getShareTokens.selector, _silo0);
        vm.mockCall(
            address(siloConfig), data, abi.encode(_protectedShareToken0, _collateralShareToken0, _debtShareToken0)
        );
        vm.expectCall(address(siloConfig), data);

        if (_expectedRevertPlace == ExpectedRevertPlaces.shareTokenSilo0) return;

        data = abi.encodeWithSelector(ISiloConfig.getShareTokens.selector, _silo1);
        vm.mockCall(
            address(siloConfig), data, abi.encode(_protectedShareToken1, _collateralShareToken1, _debtShareToken1)
        );
        vm.expectCall(address(siloConfig), data);

        if (_expectedRevertPlace == ExpectedRevertPlaces.shareTokenSilo1) return;

        data = abi.encodeWithSelector(ISiloConfig.getConfig.selector, _silo0);
        vm.mockCall(address(siloConfig), data, abi.encode(configData0));
        vm.expectCall(address(siloConfig), data);

        data = abi.encodeWithSelector(ISiloConfig.getConfig.selector, _silo1);
        vm.mockCall(address(siloConfig), data, abi.encode(configData1));
        vm.expectCall(address(siloConfig), data);

        data = abi.encodeWithSelector(ISiloConfig.getAssetForSilo.selector, _silo0);
        vm.mockCall(address(siloConfig), data, abi.encode(makeAddr("token0")));
        vm.expectCall(address(siloConfig), data);

        data = abi.encodeWithSelector(ISiloConfig.getAssetForSilo.selector, _silo1);
        vm.mockCall(address(siloConfig), data, abi.encode(makeAddr("token1")));
        vm.expectCall(address(siloConfig), data);

        data = abi.encodeWithSelector(ICrossReentrancyGuard.reentrancyGuardEntered.selector);
        vm.mockCall(address(siloConfig), data, abi.encode(false));
        vm.expectCall(address(siloConfig), data);

        data = abi.encodeWithSelector(IHookReceiver.hookReceiverConfig.selector, _silo0);
        vm.mockCall(configData0.hookReceiver, data, abi.encode(0, 0));
        vm.expectCall(configData0.hookReceiver, data);

        data = abi.encodeWithSelector(IHookReceiver.hookReceiverConfig.selector, _silo1);
        vm.mockCall(configData1.hookReceiver, data, abi.encode(0, 0));
        vm.expectCall(configData1.hookReceiver, data);
    }
}
