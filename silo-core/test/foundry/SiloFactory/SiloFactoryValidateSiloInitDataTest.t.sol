// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISiloFactory} from "silo-core/contracts/SiloFactory.sol";
import {SiloFactoryDeploy} from "silo-core/deploy/SiloFactoryDeploy.s.sol";

import {OracleMock} from "../_mocks/OracleMock.sol";

/*
forge test -vv --mc SiloFactoryValidateSiloInitDataTest
*/
contract SiloFactoryValidateSiloInitDataTest is Test {
    ISiloFactory public siloFactory;

    address internal _timelock = makeAddr("Timelock");
    address internal _feeDistributor = makeAddr("FeeDistributor");

    function setUp() public {
        SiloFactoryDeploy siloFactoryDeploy = new SiloFactoryDeploy();
        siloFactoryDeploy.disableDeploymentsSync();
        siloFactory = siloFactoryDeploy.run();
    }

    /*
    forge test -vv --mt test_validateSiloInitData_pass
    */
    function test_validateSiloInitData_pass() public {
        ISiloConfig.InitData memory initData;

        vm.expectRevert(ISiloFactory.MissingHookReceiver.selector);
        siloFactory.validateSiloInitData(initData);
        initData.hookReceiver = address(2);

        vm.expectRevert(ISiloFactory.EmptyToken0.selector);
        siloFactory.validateSiloInitData(initData);
        initData.token0 = address(1);

        vm.expectRevert(ISiloFactory.EmptyToken1.selector); // even when zeros
        siloFactory.validateSiloInitData(initData);
        initData.token1 = address(1);

        vm.expectRevert(ISiloFactory.SameAsset.selector); // even when zeros
        siloFactory.validateSiloInitData(initData);

        initData.token1 = address(2);

        vm.expectRevert(ISiloFactory.InvalidMaxLtv.selector);
        siloFactory.validateSiloInitData(initData);

        initData.maxLtv0 = 0.75e18;
        initData.maxLtv1 = 0.65e18;

        vm.expectRevert(ISiloFactory.InvalidMaxLtv.selector);
        siloFactory.validateSiloInitData(initData);

        initData.lt0 = 8.5e18;
        initData.lt1 = 7.5e18;

        vm.expectRevert(ISiloFactory.InvalidLt.selector);
        siloFactory.validateSiloInitData(initData);

        initData.lt0 = 0.95e18;
        initData.liquidationFee0 = 0.1e18;

        vm.expectRevert(ISiloFactory.InvalidLt.selector);
        siloFactory.validateSiloInitData(initData);

        initData.lt0 = 0.9e18;
        initData.liquidationFee0 = 0.1e18;
        initData.lt1 = 0.99e18;
        initData.liquidationFee1 = 0.05e18;

        vm.expectRevert(ISiloFactory.InvalidLt.selector);
        siloFactory.validateSiloInitData(initData);

        initData.lt1 = 0.75e18;

        vm.expectRevert(ISiloFactory.DaoMinRangeExceeded.selector);
        siloFactory.validateSiloInitData(initData);

        initData.daoFee = 1.15e18;

        vm.expectRevert(ISiloFactory.DaoMaxRangeExceeded.selector);
        siloFactory.validateSiloInitData(initData);

        initData.daoFee = 0.15e18;

        vm.expectRevert(ISiloFactory.InvalidIrm.selector);
        siloFactory.validateSiloInitData(initData);

        initData.maxLtvOracle0 = address(1);
        vm.expectRevert(ISiloFactory.OracleMisconfiguration.selector);
        siloFactory.validateSiloInitData(initData);

        initData.callBeforeQuote0 = true;
        initData.maxLtvOracle0 = address(0);
        initData.solvencyOracle0 = address(0);
        vm.expectRevert(ISiloFactory.InvalidCallBeforeQuote.selector);
        siloFactory.validateSiloInitData(initData);

        initData.solvencyOracle0 = address(1);
        initData.maxLtvOracle1 = address(1);
        vm.expectRevert(ISiloFactory.OracleMisconfiguration.selector);
        siloFactory.validateSiloInitData(initData);

        initData.callBeforeQuote1 = true;
        initData.maxLtvOracle1 = address(0);
        vm.expectRevert(ISiloFactory.InvalidCallBeforeQuote.selector);
        siloFactory.validateSiloInitData(initData);

        initData.callBeforeQuote0 = false;
        initData.callBeforeQuote1 = false;
        initData.solvencyOracle0 = address(0);
        initData.maxLtvOracle1 = address(0);

        initData.deployerFee = 0.01e18;

        vm.expectRevert(ISiloFactory.InvalidDeployer.selector);
        siloFactory.validateSiloInitData(initData);

        initData.deployer = address(100001);

        vm.expectRevert(ISiloFactory.InvalidIrm.selector);
        siloFactory.validateSiloInitData(initData);

        initData.deployerFee = siloFactory.maxDeployerFee() + 1;

        vm.expectRevert(ISiloFactory.MaxDeployerFeeExceeded.selector);
        siloFactory.validateSiloInitData(initData);

        initData.deployerFee = 0.01e18;

        vm.expectRevert(ISiloFactory.InvalidIrm.selector);
        siloFactory.validateSiloInitData(initData);

        initData.flashloanFee0 = uint64(siloFactory.maxFlashloanFee() + 1);

        vm.expectRevert(ISiloFactory.MaxFlashloanFeeExceeded.selector);
        siloFactory.validateSiloInitData(initData);

        initData.flashloanFee0 = 0.01e18;

        vm.expectRevert(ISiloFactory.InvalidIrm.selector);
        siloFactory.validateSiloInitData(initData);

        initData.flashloanFee1 = uint64(siloFactory.maxFlashloanFee() + 1);

        vm.expectRevert(ISiloFactory.MaxFlashloanFeeExceeded.selector);
        siloFactory.validateSiloInitData(initData);

        initData.flashloanFee1 = 0.01e18;

        vm.expectRevert(ISiloFactory.InvalidIrm.selector);
        siloFactory.validateSiloInitData(initData);

        initData.liquidationFee0 = uint64(siloFactory.maxLiquidationFee() + 1);

        vm.expectRevert(ISiloFactory.MaxLiquidationFeeExceeded.selector);
        siloFactory.validateSiloInitData(initData);

        initData.liquidationFee0 = 0.01e18;
        initData.liquidationFee1 = uint64(siloFactory.maxLiquidationFee() + 1);

        vm.expectRevert(ISiloFactory.MaxLiquidationFeeExceeded.selector);
        siloFactory.validateSiloInitData(initData);

        initData.liquidationFee1 = 0.01e18;

        initData.interestRateModel0 = address(0);

        vm.expectRevert(ISiloFactory.InvalidIrm.selector);
        siloFactory.validateSiloInitData(initData);

        initData.interestRateModel1 = address(100005);

        vm.expectRevert(ISiloFactory.InvalidIrm.selector);
        siloFactory.validateSiloInitData(initData);

        initData.interestRateModel0 = address(100006);
        initData.interestRateModel1 = initData.interestRateModel0;

        assertTrue(siloFactory.validateSiloInitData(initData));
    }

    /*
    forge test -vv --mt test_validateSiloInitData_oracles
    */
    function test_validateSiloInitData_oracles() public {
        ISiloConfig.InitData memory initData;

        initData.hookReceiver = address(2);
        initData.token0 = address(1);
        initData.token1 = address(2);

        initData.maxLtv0 = 0.75e18;
        initData.maxLtv1 = 0.65e18;

        initData.lt0 = 0.85e18;
        initData.lt1 = 0.75e18;

        initData.deployer = address(100001);
        initData.deployerFee = 0.01e18;
        initData.daoFee = 0.05e18;

        initData.flashloanFee0 = 0.01e18;
        initData.flashloanFee1 = 0.01e18;
        initData.liquidationFee0 = 0.01e18;
        initData.liquidationFee1 = 0.01e18;

        initData.interestRateModel0 = address(100006);
        initData.interestRateModel1 = initData.interestRateModel0;

        // verify we have valid config as begin
        assertTrue(siloFactory.validateSiloInitData(initData), "#0");

        OracleMock solvencyOracle0 = new OracleMock(makeAddr("solvencyOracle0"));
        solvencyOracle0.quoteTokenMock(makeAddr("quoteToken"));
        initData.solvencyOracle0 = solvencyOracle0.ADDRESS();
        assertTrue(siloFactory.validateSiloInitData(initData), "#1");

        OracleMock maxLtvOracle0 = new OracleMock(makeAddr("maxLtvOracle0"));
        maxLtvOracle0.quoteTokenMock(address(1));
        initData.maxLtvOracle0 = maxLtvOracle0.ADDRESS();
        vm.expectRevert(ISiloFactory.InvalidQuoteToken.selector);
        siloFactory.validateSiloInitData(initData);

        maxLtvOracle0.quoteTokenMock(makeAddr("quoteToken"));

        OracleMock solvencyOracle1 = new OracleMock(makeAddr("solvencyOracle1"));
        solvencyOracle1.quoteTokenMock(address(1));
        initData.solvencyOracle1 = solvencyOracle1.ADDRESS();
        vm.expectRevert(ISiloFactory.InvalidQuoteToken.selector);
        siloFactory.validateSiloInitData(initData);

        solvencyOracle1.quoteTokenMock(makeAddr("quoteToken"));

        OracleMock maxLtvOracle1 = new OracleMock(makeAddr("maxLtvOracle1"));
        maxLtvOracle1.quoteTokenMock(address(1));
        initData.maxLtvOracle1 = maxLtvOracle1.ADDRESS();
        vm.expectRevert(ISiloFactory.InvalidQuoteToken.selector);
        siloFactory.validateSiloInitData(initData);

        maxLtvOracle1.quoteTokenMock(makeAddr("quoteToken"));
        assertTrue(siloFactory.validateSiloInitData(initData), "#0");
    }
}
