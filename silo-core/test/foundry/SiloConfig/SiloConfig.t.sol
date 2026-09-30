// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ISiloConfig, SiloConfig} from "silo-core/contracts/SiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ICrossReentrancyGuard} from "silo-core/contracts/interfaces/ICrossReentrancyGuard.sol";

// solhint-disable func-name-mixedcase

/*
forge test -vv --mc SiloConfigTest
*/
contract SiloConfigTest is Test {
    address internal _wrongSilo = makeAddr("wrongSilo");
    address internal _silo0Default = makeAddr("silo0");
    address internal _silo1Default = makeAddr("silo1");
    address internal _hookReceiverModuleDefault = makeAddr("hookReceiver");

    ISiloConfig.ConfigData internal _configDataDefault0;
    ISiloConfig.ConfigData internal _configDataDefault1;

    SiloConfig internal _siloConfig;

    function setUp() public {
        _configDataDefault0.silo = _silo0Default;
        _configDataDefault0.token = makeAddr("token0");
        _configDataDefault0.collateralShareToken = _silo0Default;
        _configDataDefault0.protectedShareToken = makeAddr("protectedShareToken0");
        _configDataDefault0.debtShareToken = makeAddr("debtShareToken0");
        _configDataDefault0.hookReceiver = _hookReceiverModuleDefault;

        _configDataDefault1.silo = _silo1Default;
        _configDataDefault1.token = makeAddr("token1");
        _configDataDefault1.collateralShareToken = _silo1Default;
        _configDataDefault1.protectedShareToken = makeAddr("protectedShareToken1");
        _configDataDefault1.debtShareToken = makeAddr("debtShareToken1");
        _configDataDefault1.hookReceiver = _hookReceiverModuleDefault;

        _siloConfig = siloConfigDeploy(1, _configDataDefault0, _configDataDefault1);

        vm.mockCall(
            _silo0Default,
            abi.encodeCall(
                ISilo.accrueInterestForConfig,
                (_configDataDefault0.interestRateModel, _configDataDefault0.daoFee, _configDataDefault0.deployerFee)
            ),
            abi.encode(true)
        );

        vm.mockCall(
            _silo1Default,
            abi.encodeCall(
                ISilo.accrueInterestForConfig,
                (_configDataDefault1.interestRateModel, _configDataDefault1.daoFee, _configDataDefault1.deployerFee)
            ),
            abi.encode(true)
        );
    }

    function siloConfigDeploy(
        uint256 _siloId,
        ISiloConfig.ConfigData memory _configData0,
        ISiloConfig.ConfigData memory _configData1
    ) public returns (SiloConfig siloConfig) {
        vm.assume(_configData0.silo != _wrongSilo);
        vm.assume(_configData1.silo != _wrongSilo);
        vm.assume(_configData0.silo != _configData1.silo);
        vm.assume(_configData0.daoFee < 0.5e18);
        vm.assume(_configData0.deployerFee < 0.5e18);
        vm.assume(_configData0.liquidationTargetLtv <= _configData0.lt);
        vm.assume(_configData1.liquidationTargetLtv <= _configData1.lt);

        // when using assume, it reject too many inputs
        _configData0.hookReceiver = _configData1.hookReceiver;

        _configData1.daoFee = _configData0.daoFee;
        _configData1.deployerFee = _configData0.deployerFee;
        _configData0.collateralShareToken = _configData0.silo;
        _configData1.collateralShareToken = _configData1.silo;

        siloConfig = new SiloConfig(_siloId, _configData0, _configData1);
    }

    /*
    forge test -vv --mt test_daoAndDeployerFeeCap
    */
    function test_daoAndDeployerFeeCap() public {
        ISiloConfig.ConfigData memory _configData0;
        ISiloConfig.ConfigData memory _configData1;

        _configData0.daoFee = 1e18;
        _configData0.deployerFee = 0;

        vm.expectRevert(ISiloConfig.FeeTooHigh.selector);
        new SiloConfig(1, _configData0, _configData1);
    }

    /*
    forge test -vv --mt test_accrueInterestForSilo_WrongSilo
    */
    function test_accrueInterestForSilo_WrongSilo() public {
        address anySilo = makeAddr("anySilo");

        vm.expectRevert(ISiloConfig.WrongSilo.selector);
        _siloConfig.accrueInterestForSilo(anySilo);
    }

    /*
    forge test -vv --mt test_accrueInterestForSilo
    */
    function test_accrueInterestForSilo() public {
        bytes memory data = abi.encodeCall(
            ISilo.accrueInterestForConfig,
            (_configDataDefault0.interestRateModel, _configDataDefault0.daoFee, _configDataDefault0.deployerFee)
        );

        vm.mockCall(_silo0Default, data, abi.encode(true));
        vm.expectCall(_silo0Default, data);

        _siloConfig.accrueInterestForSilo(_silo0Default);

        data = abi.encodeCall(
            ISilo.accrueInterestForConfig,
            (_configDataDefault1.interestRateModel, _configDataDefault1.daoFee, _configDataDefault1.deployerFee)
        );

        vm.mockCall(_silo1Default, data, abi.encode(true));
        vm.expectCall(_silo1Default, data);

        _siloConfig.accrueInterestForSilo(_silo1Default);
    }

    /*
    forge test -vv --mt test_accrueInterestForBothSilos
    */
    function test_accrueInterestForBothSilos() public {
        bytes memory dataSilo0 = abi.encodeCall(
            ISilo.accrueInterestForConfig,
            (_configDataDefault0.interestRateModel, _configDataDefault0.daoFee, _configDataDefault0.deployerFee)
        );

        vm.mockCall(_silo0Default, dataSilo0, abi.encode(true));
        vm.expectCall(_silo0Default, dataSilo0);

        bytes memory dataSilo1 = abi.encodeCall(
            ISilo.accrueInterestForConfig,
            (_configDataDefault1.interestRateModel, _configDataDefault1.daoFee, _configDataDefault1.deployerFee)
        );

        vm.mockCall(_silo1Default, dataSilo1, abi.encode(true));
        vm.expectCall(_silo1Default, dataSilo1);

        _siloConfig.accrueInterestForBothSilos();
    }

    /*
    forge test -vv --mt test_getSilos_fuzz
    */
    function test_getSilos_fuzz(
        uint256 _siloId,
        ISiloConfig.ConfigData memory _configData0,
        ISiloConfig.ConfigData memory _configData1
    ) public {
        SiloConfig siloConfig = siloConfigDeploy(_siloId, _configData0, _configData1);

        (address silo0, address silo1) = siloConfig.getSilos();
        assertEq(silo0, _configData0.silo);
        assertEq(silo1, _configData1.silo);
    }

    /*
    forge test -vv --mt test_getShareTokens_fuzz
    */
    function test_getShareTokens_fuzz(
        uint256 _siloId,
        ISiloConfig.ConfigData memory _configData0,
        ISiloConfig.ConfigData memory _configData1
    ) public {
        vm.assume(_configData0.liquidationTargetLtv <= _configData0.lt);
        vm.assume(_configData1.liquidationTargetLtv <= _configData1.lt);

        SiloConfig siloConfig = siloConfigDeploy(_siloId, _configData0, _configData1);

        vm.expectRevert(ISiloConfig.WrongSilo.selector);
        siloConfig.getShareTokens(_wrongSilo);

        (address protectedShareToken, address collateralShareToken, address debtShareToken) =
            siloConfig.getShareTokens(_configData0.silo);
        assertEq(protectedShareToken, _configData0.protectedShareToken);
        assertEq(collateralShareToken, _configData0.silo);
        assertEq(debtShareToken, _configData0.debtShareToken);

        (protectedShareToken, collateralShareToken, debtShareToken) = siloConfig.getShareTokens(_configData1.silo);
        assertEq(protectedShareToken, _configData1.protectedShareToken);
        assertEq(collateralShareToken, _configData1.silo);
        assertEq(debtShareToken, _configData1.debtShareToken);
    }

    /*
    forge test -vv --mt test_getAssetForSilo_fuzz
    */
    function test_getAssetForSilo_fuzz(
        uint256 _siloId,
        ISiloConfig.ConfigData memory _configData0,
        ISiloConfig.ConfigData memory _configData1
    ) public {
        SiloConfig siloConfig = siloConfigDeploy(_siloId, _configData0, _configData1);

        vm.expectRevert(ISiloConfig.WrongSilo.selector);
        siloConfig.getAssetForSilo(_wrongSilo);

        assertEq(siloConfig.getAssetForSilo(_configData0.silo), _configData0.token);
        assertEq(siloConfig.getAssetForSilo(_configData1.silo), _configData1.token);
    }

    /*
    forge test -vv --mt test_getConfigs_fuzz
    */
    function test_getConfigs_fuzz(
        uint256 _siloId,
        ISiloConfig.ConfigData memory _configData0,
        ISiloConfig.ConfigData memory _configData1
    ) public {
        SiloConfig siloConfig = siloConfigDeploy(_siloId, _configData0, _configData1);

        (address silo0, address silo1) = siloConfig.getSilos();

        ISiloConfig.ConfigData memory c0 = siloConfig.getConfig(silo0);
        ISiloConfig.ConfigData memory c1 = siloConfig.getConfig(silo1);

        assertEq(keccak256(abi.encode(c0)), keccak256(abi.encode(_configData0)));
        assertEq(keccak256(abi.encode(c1)), keccak256(abi.encode(_configData1)));
    }

    /*
    forge test -vv --mt test_getConfigsForWithdraw_WrongSilo
    */
    function test_getConfigsForWithdraw_WrongSilo() public {
        SiloConfig siloConfig = siloConfigDeploy(1, _configDataDefault0, _configDataDefault1);

        address anySilo = makeAddr("anySilo");

        vm.expectRevert(ISiloConfig.WrongSilo.selector);
        siloConfig.getConfigsForWithdraw(anySilo, address(0));
    }

    /*
    forge test -vv --mt test_getConfigsForBorrow_WrongSilo
    */
    function test_getConfigsForBorrow_WrongSilo() public {
        SiloConfig siloConfig = siloConfigDeploy(1, _configDataDefault0, _configDataDefault1);

        address anySilo = makeAddr("anySilo");

        vm.expectRevert(ISiloConfig.WrongSilo.selector);
        siloConfig.getConfigsForBorrow(anySilo);
    }

    /*
    forge test -vv --mt test_getConfig_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 3
    function test_getConfig_fuzz(
        uint256 _siloId,
        ISiloConfig.ConfigData memory _configData0,
        ISiloConfig.ConfigData memory _configData1
    ) public {
        // we always using #0 setup for hookReceiver
        _configData1.hookReceiver = _configData0.hookReceiver;
        _configData0.collateralShareToken = _configData0.silo;
        _configData1.collateralShareToken = _configData1.silo;

        SiloConfig siloConfig = siloConfigDeploy(_siloId, _configData0, _configData1);

        vm.expectRevert(ISiloConfig.WrongSilo.selector);
        siloConfig.getConfig(_wrongSilo);

        ISiloConfig.ConfigData memory c0 = siloConfig.getConfig(_configData0.silo);
        assertEq(keccak256(abi.encode(c0)), keccak256(abi.encode(_configData0)), "expect config for silo0");

        ISiloConfig.ConfigData memory c1 = siloConfig.getConfig(_configData1.silo);
        assertEq(keccak256(abi.encode(c1)), keccak256(abi.encode(_configData1)), "expect config for silo1");
    }

    /*
    forge test -vv --mt test_getFeesWithAsset_fuzz
    */
    function test_getFeesWithAsset_fuzz(
        uint256 _siloId,
        ISiloConfig.ConfigData memory _configData0,
        ISiloConfig.ConfigData memory _configData1
    ) public {
        SiloConfig siloConfig = siloConfigDeploy(_siloId, _configData0, _configData1);

        vm.expectRevert(ISiloConfig.WrongSilo.selector);
        siloConfig.getFeesWithAsset(_wrongSilo);

        (uint256 daoFee, uint256 deployerFee, uint256 flashloanFee, address asset) =
            siloConfig.getFeesWithAsset(_configData0.silo);

        assertEq(daoFee, _configData0.daoFee);
        assertEq(deployerFee, _configData0.deployerFee);
        assertEq(flashloanFee, _configData0.flashloanFee);
        assertEq(asset, _configData0.token);

        (daoFee, deployerFee, flashloanFee, asset) = siloConfig.getFeesWithAsset(_configData1.silo);

        assertEq(daoFee, _configData1.daoFee);
        assertEq(deployerFee, _configData1.deployerFee);
        assertEq(flashloanFee, _configData1.flashloanFee);
        assertEq(asset, _configData1.token);
    }

    /*
    forge test -vv --mt test_getDebtShareTokenAndAsset_revertOnOnlySilo
    */
    function test_getDebtShareTokenAndAsset_revertOnOnlySilo() public {
        address anySilo = makeAddr("anySilo");

        vm.expectRevert(ISiloConfig.WrongSilo.selector);
        _siloConfig.getDebtShareTokenAndAsset(anySilo);
    }

    /*
    forge test -vv --mt test_getDebtShareTokenAndAsset_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 3
    function test_getDebtShareTokenAndAsset_fuzz(
        uint256 _siloId,
        ISiloConfig.ConfigData memory _configData0,
        ISiloConfig.ConfigData memory _configData1
    ) public {
        SiloConfig siloConfig = siloConfigDeploy(_siloId, _configData0, _configData1);

        address shareToken;
        address asset;

        ISilo.CollateralType collateralType = ISilo.CollateralType.Collateral;

        (shareToken, asset) = siloConfig.getCollateralShareTokenAndAsset(_configData0.silo, collateralType);

        assertEq(shareToken, _configData0.silo);
        assertEq(asset, _configData0.token);

        (shareToken, asset) = siloConfig.getCollateralShareTokenAndAsset(_configData1.silo, collateralType);

        assertEq(shareToken, _configData1.silo);
        assertEq(asset, _configData1.token);

        collateralType = ISilo.CollateralType.Protected;

        (shareToken, asset) = siloConfig.getCollateralShareTokenAndAsset(_configData0.silo, collateralType);

        assertEq(shareToken, _configData0.protectedShareToken);
        assertEq(asset, _configData0.token);

        (shareToken, asset) = siloConfig.getCollateralShareTokenAndAsset(_configData1.silo, collateralType);

        assertEq(shareToken, _configData1.protectedShareToken);
        assertEq(asset, _configData1.token);
    }

    /*
    forge test -vv --mt test_getCollateralShareTokenAndAsset_revertWrongSilo
    */
    function test_getCollateralShareTokenAndAsset_revertWrongSilo() public {
        address anySilo = makeAddr("anySilo");
        ISilo.CollateralType collateralType = ISilo.CollateralType.Collateral;

        vm.expectRevert(ISiloConfig.WrongSilo.selector);
        _siloConfig.getCollateralShareTokenAndAsset(anySilo, collateralType);

        collateralType = ISilo.CollateralType.Protected;

        vm.expectRevert(ISiloConfig.WrongSilo.selector);
        _siloConfig.getCollateralShareTokenAndAsset(anySilo, collateralType);
    }

    /*
    forge test -vv --mt test_getCollateralShareTokenAndAsset_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 3
    function test_getCollateralShareTokenAndAsset_fuzz(
        uint256 _siloId,
        ISiloConfig.ConfigData memory _configData0,
        ISiloConfig.ConfigData memory _configData1
    ) public {
        SiloConfig siloConfig = siloConfigDeploy(_siloId, _configData0, _configData1);

        address debtToken;
        address asset;

        (debtToken, asset) = siloConfig.getDebtShareTokenAndAsset(_configData0.silo);

        assertEq(debtToken, _configData0.debtShareToken);
        assertEq(asset, _configData0.token);

        (debtToken, asset) = siloConfig.getDebtShareTokenAndAsset(_configData1.silo);

        assertEq(debtToken, _configData1.debtShareToken);
    }

    /*
    forge test -vv --mt test_setCollateralSilo_revertOnOnlySilo
    */
    function test_setCollateralSilo_revertOnOnlySilo() public {
        vm.expectRevert(ISiloConfig.OnlySilo.selector);
        _siloConfig.setOtherSiloAsCollateralSilo(makeAddr("borrower"));
    }

    /*
    forge test -vv --mt test_setThisSiloAsCollateralSilo_returnValue
    */
    function test_setThisSiloAsCollateralSilo_deprecated() public {
        address borrower = makeAddr("borrower");

        vm.expectRevert(ISiloConfig.Deprecated.selector);
        _siloConfig.setThisSiloAsCollateralSilo(borrower);
    }

    /*
    forge test -vv --mt test_setOtherSiloAsCollateralSilo
    */
    function test_setOtherSiloAsCollateralSilo() public {
        address borrower = makeAddr("borrower");

        vm.prank(_silo0Default);
        _siloConfig.setOtherSiloAsCollateralSilo(borrower);

        address configuredSilo = _siloConfig.borrowerCollateralSilo(borrower);

        assertEq(address(_silo1Default), configuredSilo);

        vm.prank(_silo1Default);
        _siloConfig.setOtherSiloAsCollateralSilo(borrower);

        configuredSilo = _siloConfig.borrowerCollateralSilo(borrower);

        assertEq(address(_silo0Default), configuredSilo);
    }

    /*
    forge test -vv --mt test_setOtherSiloAsCollateralSilo_MultipleTimes
    */
    function test_setOtherSiloAsCollateralSilo_MultipleTimes() public {
        address borrower = makeAddr("borrower");
        address configuredSilo;

        for (uint256 i; i < 3; i++) {
            vm.prank(_silo0Default);
            _siloConfig.setOtherSiloAsCollateralSilo(borrower);

            configuredSilo = _siloConfig.borrowerCollateralSilo(borrower);

            assertEq(address(_silo1Default), configuredSilo);
        }

        for (uint256 i; i < 3; i++) {
            vm.prank(_silo1Default);
            _siloConfig.setOtherSiloAsCollateralSilo(borrower);

            configuredSilo = _siloConfig.borrowerCollateralSilo(borrower);

            assertEq(address(_silo0Default), configuredSilo);
        }
    }

    /*
    forge test -vv --mt test_borrowerCollateralSilo
    */
    function test_borrowerCollateralSilo() public {
        address borrower = makeAddr("borrower");

        address configuredSilo = _siloConfig.borrowerCollateralSilo(borrower);

        assertEq(address(0), configuredSilo);

        vm.prank(_silo0Default);
        _siloConfig.setOtherSiloAsCollateralSilo(borrower);

        configuredSilo = _siloConfig.borrowerCollateralSilo(borrower);

        assertEq(address(_silo1Default), configuredSilo);
    }

    /*
    forge test -vv --mt test_setCollateralSilo_pass
    */
    function test_openDebt_pass() public {
        address borrower1 = makeAddr("Borrower 1");
        address borrower2 = makeAddr("Borrower 2");

        _mockShareTokensBlances(borrower1, 1, 0);
        _mockShareTokensBlances(borrower2, 1, 0);

        vm.prank(_silo0Default);
        _siloConfig.setOtherSiloAsCollateralSilo(borrower1);

        vm.prank(_silo1Default);
        _siloConfig.setOtherSiloAsCollateralSilo(borrower2);
    }

    /*
    forge test -vv --mt test_getConfigs_zero
    */
    function test_getConfigs_zero() public {
        vm.mockCall(_configDataDefault0.debtShareToken, abi.encodeCall(IERC20.balanceOf, address(0)), abi.encode(0));

        vm.mockCall(_configDataDefault1.debtShareToken, abi.encodeCall(IERC20.balanceOf, address(0)), abi.encode(0));

        (ISiloConfig.ConfigData memory collateralConfig, ISiloConfig.ConfigData memory debtConfig) =
            _siloConfig.getConfigsForSolvency(address(0));

        assertEq(collateralConfig.silo, address(0), "User has no debt - config should be empty");
        assertEq(debtConfig.silo, address(0), "User has no debt - config should be empty");
    }

    /*
    forge test -vv --mt test_openDebt_debtInOtherSilo
    */
    function test_openDebt_debtInOtherSilo() public {
        address borrower = makeAddr("borrower");

        _mockShareTokensBlances(borrower, 0, 1);

        vm.prank(_silo1Default);
        _siloConfig.setOtherSiloAsCollateralSilo(borrower);

        ISiloConfig.ConfigData memory collateralConfig;
        ISiloConfig.ConfigData memory debtConfig;

        (collateralConfig, debtConfig) = _siloConfig.getConfigsForSolvency(borrower);

        assertTrue(debtConfig.silo != address(0), "debt silo is empty");
        assertTrue(debtConfig.silo != collateralConfig.silo, "same asset");
        assertTrue(debtConfig.silo == _silo1Default, "wrong debt silo");

        address otherUser = makeAddr("otherUser");
        _mockShareTokensBlances(otherUser, 0, 0);

        (collateralConfig, debtConfig) = _siloConfig.getConfigsForSolvency(otherUser);

        assertEq(collateralConfig.silo, address(0), "config should be empty");
        assertEq(debtConfig.silo, address(0), "config should be empty");
    }

    /*
    forge test -vv --mt test_onDebtTransfer_clone
    */
    /// forge-config: core_test.fuzz.runs = 10
    function test_onDebtTransfer_clone_fuzz(bool _silo0) public {
        address silo = _silo0 ? _silo0Default : _silo1Default;

        address from = makeAddr("from");
        address to = makeAddr("to");

        uint256 balance0 = _silo0 ? 1 : 0;
        uint256 balance1 = _silo0 ? 0 : 1;

        _mockShareTokensBlances(from, balance0, balance1);

        vm.prank(silo);

        _siloConfig.setOtherSiloAsCollateralSilo(from);

        _mockShareTokensBlances(to, 0, 0);

        ISiloConfig.ConfigData memory collateralConfigFrom;
        ISiloConfig.ConfigData memory debtConfigFrom;

        (collateralConfigFrom, debtConfigFrom) = _siloConfig.getConfigsForSolvency(from);

        vm.prank(_silo0 ? _configDataDefault0.debtShareToken : _configDataDefault1.debtShareToken);
        _siloConfig.onDebtTransfer(from, to);

        _mockShareTokensBlances(from, 0, 0);
        _mockShareTokensBlances(to, balance0, balance1);

        ISiloConfig.ConfigData memory collateralConfigTo;
        ISiloConfig.ConfigData memory debtConfigTo;

        (collateralConfigTo, debtConfigTo) = _siloConfig.getConfigsForSolvency(to);

        assertEq(collateralConfigTo.silo, collateralConfigFrom.silo, "silo should be the same");
        assertEq(debtConfigTo.silo, debtConfigFrom.silo, "debt silo should be the same");
    }

    /*
    forge test -vv --mt test_onDebtTransfer_revertIfNotDebtToken
    */
    function test_onDebtTransfer_revertIfNotDebtToken() public {
        address silo = makeAddr("siloX");
        address from = makeAddr("from");
        address to = makeAddr("to");

        vm.prank(silo);
        vm.expectRevert(ISiloConfig.OnlyDebtShareToken.selector);
        _siloConfig.onDebtTransfer(from, to);

        // verify that it will not work for collateral or protected share tokens
        vm.prank(_configDataDefault0.collateralShareToken);
        vm.expectRevert(ISiloConfig.OnlyDebtShareToken.selector);
        _siloConfig.onDebtTransfer(from, to);

        vm.prank(_configDataDefault0.protectedShareToken);
        vm.expectRevert(ISiloConfig.OnlyDebtShareToken.selector);
        _siloConfig.onDebtTransfer(from, to);

        vm.prank(_configDataDefault1.collateralShareToken);
        vm.expectRevert(ISiloConfig.OnlyDebtShareToken.selector);
        _siloConfig.onDebtTransfer(from, to);

        vm.prank(_configDataDefault1.protectedShareToken);
        vm.expectRevert(ISiloConfig.OnlyDebtShareToken.selector);
        _siloConfig.onDebtTransfer(from, to);
    }

    /*
    forge test -vv --mt test_onDebtTransfer_allowedForDebtShareToken0
    */
    function test_onDebtTransfer_allowedForDebtShareToken0() public {
        address from = makeAddr("from");
        address to = makeAddr("to");

        _mockShareTokensBlances(to, 0, 0);

        vm.prank(_configDataDefault0.debtShareToken);
        _siloConfig.onDebtTransfer(from, to);
    }

    /*
    forge test -vv --mt test_onDebtTransfer_allowedForDebtShareToken1
    */
    function test_onDebtTransfer_allowedForDebtShareToken1() public {
        address from = makeAddr("from");
        address to = makeAddr("to");

        _mockShareTokensBlances(to, 0, 0);

        vm.prank(_configDataDefault1.debtShareToken);
        _siloConfig.onDebtTransfer(from, to);
    }

    /*
    forge test -vv --mt test_onDebtTransfer_DebtExistInOtherSilo
    */
    function test_onDebtTransfer_DebtExistInOtherSilo() public {
        address from = makeAddr("from");
        address to = makeAddr("to");

        _mockShareTokensBlances(from, 1, 0);

        vm.prank(_silo0Default);
        _siloConfig.setOtherSiloAsCollateralSilo(to);

        _mockShareTokensBlances(to, 0, 1);

        vm.prank(_silo1Default);
        _siloConfig.setOtherSiloAsCollateralSilo(from);

        vm.expectRevert(ISiloConfig.DebtExistInOtherSilo.selector);
        vm.prank(_configDataDefault0.debtShareToken);
        _siloConfig.onDebtTransfer(from, to);

        _mockShareTokensBlances(to, 1, 1);
    }

    /*
    forge test -vv --mt test_onDebtTransfer_pass
    */
    function test_onDebtTransfer_pass() public {
        address from = makeAddr("from");
        address to = makeAddr("to");

        _mockShareTokensBlances(from, 0, 0);
        _mockShareTokensBlances(to, 0, 0);

        vm.prank(_silo0Default);
        _siloConfig.setOtherSiloAsCollateralSilo(to);

        _mockShareTokensBlances(from, 1, 0);

        vm.prank(_silo0Default);
        _siloConfig.setOtherSiloAsCollateralSilo(from);

        _mockShareTokensBlances(to, 1, 0);

        vm.prank(_configDataDefault0.debtShareToken);
        _siloConfig.onDebtTransfer(from, to);

        _mockShareTokensBlances(from, 0, 0);
        _mockShareTokensBlances(to, 2, 0);

        ISiloConfig.ConfigData memory collateral;
        ISiloConfig.ConfigData memory debt;

        (collateral, debt) = _siloConfig.getConfigsForSolvency(to);

        assertTrue(debt.silo != address(0), "debtPresent");
        assertTrue(debt.silo != collateral.silo, "sameAsset is not cloned when debt already open");
        assertTrue(debt.silo == _silo0Default, "debt in other silo");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_crossNonReentrantBefore_error_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_crossNonReentrantBefore_error_fuzz(address _callee) public {
        vm.assume(_callee != _silo0Default);
        vm.assume(_callee != _silo1Default);
        vm.assume(_callee != _hookReceiverModuleDefault);
        vm.assume(_callee != _configDataDefault0.collateralShareToken);
        vm.assume(_callee != _configDataDefault0.protectedShareToken);
        vm.assume(_callee != _configDataDefault0.debtShareToken);
        vm.assume(_callee != _configDataDefault1.collateralShareToken);
        vm.assume(_callee != _configDataDefault1.protectedShareToken);
        vm.assume(_callee != _configDataDefault1.debtShareToken);

        // Permissions check error
        vm.expectRevert(ISiloConfig.OnlySiloOrTokenOrHookReceiver.selector);
        _siloConfig.turnOnReentrancyProtection();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_crossNonReentrantBeforePermissions
    */
    function test_crossNonReentrantBeforePermissions() public {
        // Permissions check error
        vm.expectRevert(ISiloConfig.OnlySiloOrTokenOrHookReceiver.selector);
        _siloConfig.turnOnReentrancyProtection();

        // _onlySiloOrTokenOrLiquidation permissions check (calls should not revert)
        _callNonReentrantBeforeAndAfter(_silo0Default);
        _callNonReentrantBeforeAndAfter(_silo1Default);
        _callNonReentrantBeforeAndAfter(_hookReceiverModuleDefault);
        _callNonReentrantBeforeAndAfter(_configDataDefault0.collateralShareToken);
        _callNonReentrantBeforeAndAfter(_configDataDefault0.protectedShareToken);
        _callNonReentrantBeforeAndAfter(_configDataDefault0.debtShareToken);
        _callNonReentrantBeforeAndAfter(_configDataDefault1.collateralShareToken);
        _callNonReentrantBeforeAndAfter(_configDataDefault1.protectedShareToken);
        _callNonReentrantBeforeAndAfter(_configDataDefault1.debtShareToken);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_crossNonReentrantAfter_error_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_crossNonReentrantAfter_error_fuzz(address _callee) public {
        vm.assume(_callee != _silo0Default);
        vm.assume(_callee != _silo1Default);
        vm.assume(_callee != _hookReceiverModuleDefault);
        vm.assume(_callee != _configDataDefault0.collateralShareToken);
        vm.assume(_callee != _configDataDefault0.protectedShareToken);
        vm.assume(_callee != _configDataDefault0.debtShareToken);
        vm.assume(_callee != _configDataDefault1.collateralShareToken);
        vm.assume(_callee != _configDataDefault1.protectedShareToken);
        vm.assume(_callee != _configDataDefault1.debtShareToken);

        // Permissions check error
        vm.prank(_callee);
        vm.expectRevert(ISiloConfig.OnlySiloOrTokenOrHookReceiver.selector);
        _siloConfig.turnOffReentrancyProtection();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_crossNonReentrantAfterPermissions
    */
    function test_crossNonReentrantAfterPermissions() public {
        // _onlySiloOrTokenOrLiquidation permissions check for the crossNonReentrantAfter fn
        // (calls should not revert)
        _callNonReentrantBeforeAndAfterPermissions(_silo0Default);
        _callNonReentrantBeforeAndAfterPermissions(_silo1Default);
        _callNonReentrantBeforeAndAfterPermissions(_hookReceiverModuleDefault);
        _callNonReentrantBeforeAndAfterPermissions(_configDataDefault0.collateralShareToken);
        _callNonReentrantBeforeAndAfterPermissions(_configDataDefault0.protectedShareToken);
        _callNonReentrantBeforeAndAfterPermissions(_configDataDefault0.debtShareToken);
        _callNonReentrantBeforeAndAfterPermissions(_configDataDefault1.collateralShareToken);
        _callNonReentrantBeforeAndAfterPermissions(_configDataDefault1.protectedShareToken);
        _callNonReentrantBeforeAndAfterPermissions(_configDataDefault1.debtShareToken);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_hasDebtInOtherSilo
    */
    function test_hasDebtInOtherSilo() public {
        address user = makeAddr("user");

        // Create a debt in the silo1
        _mockShareTokensBlances(user, 0, 1);

        bool hasDebt = _siloConfig.hasDebtInOtherSilo(address(_silo0Default), user);
        assertTrue(hasDebt, "user has debt in other silo");

        hasDebt = _siloConfig.hasDebtInOtherSilo(address(_silo1Default), user);
        assertFalse(hasDebt, "user has no debt in other silo");

        // Create a debt in the silo0
        _mockShareTokensBlances(user, 1, 0);

        hasDebt = _siloConfig.hasDebtInOtherSilo(address(_silo0Default), user);
        assertFalse(hasDebt, "user has no debt in other silo");

        hasDebt = _siloConfig.hasDebtInOtherSilo(address(_silo1Default), user);
        assertTrue(hasDebt, "user has debt in other silo");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_hasDebtInOtherSilo_wrongSilo
    */
    function test_hasDebtInOtherSilo_wrongSilo() public {
        address user = makeAddr("user");
        address wrongSilo = makeAddr("wrongSilo");

        vm.expectRevert(ISiloConfig.WrongSilo.selector);
        _siloConfig.hasDebtInOtherSilo(wrongSilo, user);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_getDebtSilo
    */
    function test_getDebtSilo() public {
        address user = makeAddr("user");

        // Create a debt in the silo0
        _mockShareTokensBlances(user, 1, 0);

        address debtSilo = _siloConfig.getDebtSilo(user);
        assertEq(debtSilo, address(_silo0Default), "debt silo should be silo0");

        // Create a debt in the silo1
        _mockShareTokensBlances(user, 0, 1);

        debtSilo = _siloConfig.getDebtSilo(user);
        assertEq(debtSilo, address(_silo1Default), "debt silo should be silo1");

        // Debt in two silo should not be possible.
        // Create a debt in two silos only for testing
        _mockShareTokensBlances(user, 1, 1);

        vm.expectRevert(ISiloConfig.DebtExistInOtherSilo.selector);
        _siloConfig.getDebtSilo(user);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_getDebtSilo_notDebt
    */
    function test_getDebtSilo_notDebt() public {
        address user = makeAddr("user");

        // no debt
        _mockShareTokensBlances(user, 0, 0);

        address debtSilo = _siloConfig.getDebtSilo(user);
        assertEq(debtSilo, address(0), "user has no debt");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_hasDebtInOtherSilo_noDebt
    */
    function test_hasDebtInOtherSilo_noDebt() public {
        address user = makeAddr("user");

        // no debt
        _mockShareTokensBlances(user, 0, 0);

        bool hasDebt = _siloConfig.hasDebtInOtherSilo(address(_silo0Default), user);
        assertFalse(hasDebt, "user has no debt in other silo");

        hasDebt = _siloConfig.hasDebtInOtherSilo(address(_silo1Default), user);
        assertFalse(hasDebt, "user has no debt in other silo");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_siloID_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 3
    function test_siloID_fuzz(
        uint256 _siloId,
        ISiloConfig.ConfigData memory _configData0,
        ISiloConfig.ConfigData memory _configData1
    ) public {
        SiloConfig siloConfig = siloConfigDeploy(_siloId, _configData0, _configData1);
        assertEq(siloConfig.SILO_ID(), _siloId);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_turnOnReentrancyProtection_revertCrossReentrantCall
    */
    function test_turnOnReentrancyProtection_revertCrossReentrantCall() public {
        vm.prank(_silo0Default);
        _siloConfig.turnOnReentrancyProtection();

        vm.prank(_silo0Default);
        vm.expectRevert(ICrossReentrancyGuard.CrossReentrantCall.selector);
        _siloConfig.turnOnReentrancyProtection();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_turnOffReentrancyProtection_revertCrossReentrancyNotActive
    */
    function test_turnOffReentrancyProtection_revertCrossReentrancyNotActive() public {
        vm.prank(_silo0Default);
        vm.expectRevert(ICrossReentrancyGuard.CrossReentrancyNotActive.selector);
        _siloConfig.turnOffReentrancyProtection();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_siloConfig_reentrancyGuardEntered
    */
    function test_siloConfig_reentrancyGuardEntered() public {
        assertFalse(_siloConfig.reentrancyGuardEntered(), "reentrancyGuardEntered should return false");

        vm.prank(_silo0Default);
        _siloConfig.turnOnReentrancyProtection();
        assertTrue(_siloConfig.reentrancyGuardEntered(), "reentrancyGuardEntered should return true");

        vm.prank(_silo0Default);
        _siloConfig.turnOffReentrancyProtection();
        assertFalse(_siloConfig.reentrancyGuardEntered(), "reentrancyGuardEntered should return false");
    }

    function _callNonReentrantBeforeAndAfter(address _callee) internal {
        vm.prank(_callee);
        _siloConfig.turnOnReentrancyProtection();
        vm.prank(_callee);
        _siloConfig.turnOffReentrancyProtection();
    }

    function _callNonReentrantBeforeAndAfterPermissions(address _callee) internal {
        vm.prank(_silo0Default);
        _siloConfig.turnOnReentrancyProtection();
        vm.prank(_callee);
        _siloConfig.turnOffReentrancyProtection();
    }

    function _mockWrongSiloAccrueInterest() internal {
        bytes memory data = abi.encodeCall(
            ISilo.accrueInterestForConfig,
            (_configDataDefault0.interestRateModel, _configDataDefault0.daoFee, _configDataDefault0.deployerFee)
        );

        vm.mockCall(_wrongSilo, data, abi.encode(true));
        vm.expectCall(_wrongSilo, data);
    }

    function _mockShareTokensBlances(address _user, uint256 _balance0, uint256 _balance1) internal {
        vm.mockCall(
            _configDataDefault0.debtShareToken, abi.encodeCall(IERC20.balanceOf, _user), abi.encode(_balance0)
        );

        vm.mockCall(
            _configDataDefault1.debtShareToken, abi.encodeCall(IERC20.balanceOf, _user), abi.encode(_balance1)
        );
    }
}
