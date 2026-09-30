// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {Strings} from "openzeppelin5/utils/Strings.sol";

import {SiloSolvencyLib} from "silo-core/contracts/lib/SiloSolvencyLib.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";
import {Views} from "silo-core/contracts/lib/Views.sol";

import {GetAssetsDataForLtvCalculationsTestData} from
    "silo-core/test/foundry/data-readers/GetAssetsDataForLtvCalculationsTestData.sol";
import {TokenMock} from "silo-core/test/foundry/_mocks/TokenMock.sol";
import {OracleMock} from "silo-core/test/foundry/_mocks/OracleMock.sol";
import {SiloMock} from "silo-core/test/foundry/_mocks/SiloMock.sol";
import {InterestRateModelMock} from "silo-core/test/foundry/_mocks/InterestRateModelMock.sol";

// forge test -vv --ffi --mc GetAssetsDataForLtvCalculationsTest
contract GetAssetsDataForLtvCalculationsTest is Test {
    GetAssetsDataForLtvCalculationsTestData dataReader;

    address public protectedShareToken = makeAddr("ProtectedShareToken");
    address public collateralShareToken = makeAddr("CollateralShareToken");
    address public debtShareToken = makeAddr("DebtShareToken");
    address public borrowerAddr = makeAddr("Borrower");
    address public silo0 = makeAddr("Silo_0");
    address public silo1 = makeAddr("Silo_1");

    InterestRateModelMock interestRateModelMock = new InterestRateModelMock();

    function setUp() public {
        dataReader = new GetAssetsDataForLtvCalculationsTestData();
    }

    function getData(GetAssetsDataForLtvCalculationsTestData.ScenarioData memory scenario)
        public
        returns (
            ISiloConfig.ConfigData memory collateralConfig,
            ISiloConfig.ConfigData memory debtConfig,
            address borrower,
            ISilo.OracleType oracleType,
            ISilo.AccrueInterestInMemory accrueInMemory,
            uint256 cachedShareDebtBalance
        )
    {
        {
            // stack too deep
            ISiloConfig.InitData memory initData;

            initData.deployer = makeAddr("deployer");
            initData.hookReceiver = makeAddr("hookReceiver");
            initData.token0 = makeAddr("token0");
            initData.token1 = makeAddr("token1");
            initData.maxLtv0 = 1;
            initData.maxLtv1 = 1;
            initData.lt0 = 1;
            initData.lt1 = 1;
            initData.daoFee = 0.1e18;

            // forge-lint: disable-next-line(unsafe-typecast)
            if (address(uint160(scenario.input.debtConfig.maxLtvOracle)) != address(0)) {
                // forge-lint: disable-next-line(calls-loop, unsafe-typecast)
                OracleMock om = new OracleMock(address(uint160(scenario.input.debtConfig.maxLtvOracle)));
                // forge-lint: disable-next-line(calls-loop)
                om.quoteTokenMock(makeAddr("quoteToken"));
            }

            // forge-lint: disable-next-line(unsafe-typecast)
            if (address(uint160(scenario.input.debtConfig.solvencyOracle)) != address(0)) {
                // forge-lint: disable-next-line(calls-loop, unsafe-typecast)
                OracleMock om = new OracleMock(address(uint160(scenario.input.debtConfig.solvencyOracle)));
                // forge-lint: disable-next-line(calls-loop)
                om.quoteTokenMock(makeAddr("quoteToken"));
            }

            // forge-lint: disable-next-line(unsafe-typecast)
            if (address(uint160(scenario.input.collateralConfig.maxLtvOracle)) != address(0)) {
                // forge-lint: disable-next-line(calls-loop, unsafe-typecast)
                OracleMock om = new OracleMock(address(uint160(scenario.input.collateralConfig.maxLtvOracle)));
                // forge-lint: disable-next-line(calls-loop)
                om.quoteTokenMock(makeAddr("quoteToken"));
            }

            // forge-lint: disable-next-line(unsafe-typecast)
            if (address(uint160(scenario.input.collateralConfig.solvencyOracle)) != address(0)) {
                // forge-lint: disable-next-line(calls-loop, unsafe-typecast)
                OracleMock om = new OracleMock(address(uint160(scenario.input.collateralConfig.solvencyOracle)));
                // forge-lint: disable-next-line(calls-loop)
                om.quoteTokenMock(makeAddr("quoteToken"));
            }

            // forge-lint: disable-next-line(unsafe-typecast)
            initData.maxLtvOracle0 = address(uint160(scenario.input.collateralConfig.maxLtvOracle));
            // forge-lint: disable-next-line(unsafe-typecast)
            initData.solvencyOracle0 = address(uint160(scenario.input.collateralConfig.solvencyOracle));
            // forge-lint: disable-next-line(calls-loop)
            initData.interestRateModel0 = interestRateModelMock.ADDRESS();
            initData.deployerFee = scenario.input.collateralConfig.deployerFee;

            // forge-lint: disable-next-line(unsafe-typecast)
            initData.maxLtvOracle1 = address(uint160(scenario.input.debtConfig.maxLtvOracle));
            // forge-lint: disable-next-line(unsafe-typecast)
            initData.solvencyOracle1 = address(uint160(scenario.input.debtConfig.solvencyOracle));
            // forge-lint: disable-next-line(calls-loop)
            initData.interestRateModel1 = interestRateModelMock.ADDRESS();

            (collateralConfig, debtConfig) = Views.copySiloConfig({
                _initData: initData,
                _daoFeeRange: ISiloFactory.Range(0.05e18, 0.5e18),
                _maxDeployerFee: 0.15e18,
                _maxFlashloanFee: 0.15e18,
                _maxLiquidationFee: 0.3e18
            });
        }

        collateralConfig.protectedShareToken = protectedShareToken;
        collateralConfig.collateralShareToken = collateralShareToken;
        collateralConfig.daoFee = scenario.input.collateralConfig.daoFee;
        collateralConfig.silo = silo0;
        collateralConfig.token = makeAddr("collateral.token");

        debtConfig.debtShareToken = debtShareToken;
        debtConfig.silo = silo1;
        debtConfig.token = makeAddr("debt.token");

        accrueInMemory =
            scenario.input.accrueInMemory ? ISilo.AccrueInterestInMemory.Yes : ISilo.AccrueInterestInMemory.No;

        borrower = borrowerAddr;

        oracleType = keccak256(bytes(scenario.input.oracleType)) == keccak256(bytes("solvency"))
            ? ISilo.OracleType.Solvency
            : ISilo.OracleType.MaxLtv;

        // forge-lint: disable-next-line(calls-loop)
        TokenMock protectedShareTokenMock = new TokenMock(protectedShareToken);

        // forge-lint: disable-next-item(calls-loop)
        protectedShareTokenMock.balanceOfAndTotalSupplyMock(
            borrowerAddr,
            scenario.input.collateralConfig.protectedShareBalanceOf,
            scenario.input.collateralConfig.protectedShareTotalSupply
        );

        // forge-lint: disable-next-line(calls-loop)
        TokenMock collateralShareTokenMock = new TokenMock(collateralShareToken);

        // forge-lint: disable-next-item(calls-loop)
        collateralShareTokenMock.balanceOfAndTotalSupplyMock(
            borrowerAddr,
            scenario.input.collateralConfig.collateralShareBalanceOf,
            scenario.input.collateralConfig.collateralShareTotalSupply
        );

        if (scenario.input.accrueInMemory) {
            // forge-lint: disable-next-item(calls-loop)
            interestRateModelMock.getCompoundInterestRateMock(
                silo0, block.timestamp, scenario.input.collateralConfig.compoundInterestRate
            );
        }

        // forge-lint: disable-next-line(calls-loop)
        TokenMock debtShareTokenMock = new TokenMock(debtShareToken);

        if (scenario.input.debtConfig.cachedBalance) {
            cachedShareDebtBalance = scenario.input.debtConfig.debtShareBalanceOf;
            // forge-lint: disable-next-line(calls-loop)
            debtShareTokenMock.totalSupplyMock(scenario.input.debtConfig.debtShareTotalSupply);
        } else {
            // forge-lint: disable-next-item(calls-loop)
            debtShareTokenMock.balanceOfAndTotalSupplyMock(
                borrowerAddr,
                scenario.input.debtConfig.debtShareBalanceOf,
                scenario.input.debtConfig.debtShareTotalSupply
            );
        }

        // forge-lint: disable-next-line(calls-loop)
        SiloMock siloMock0 = new SiloMock(silo0);

        if (scenario.input.accrueInMemory) {
            // forge-lint: disable-next-item(calls-loop)
            siloMock0.getCollateralAndDebtAssetsMock(
                scenario.input.collateralConfig.totalCollateralAssets,
                scenario.input.collateralConfig.totalDebtAssets
            );
        }

        // forge-lint: disable-next-item(calls-loop)
        siloMock0.getCollateralAndProtectedAssetsMock(
            scenario.input.collateralConfig.totalCollateralAssets,
            scenario.input.collateralConfig.totalProtectedAssets
        );

        // forge-lint: disable-next-line(calls-loop)
        SiloMock siloMock1 = new SiloMock(silo1);
        // forge-lint: disable-next-line(calls-loop)
        siloMock1.totalMock(ISilo.AssetType.Debt, scenario.input.debtConfig.totalDebtAssets);

        if (scenario.input.accrueInMemory) {
            // forge-lint: disable-next-item(calls-loop)
            interestRateModelMock.getCompoundInterestRateMock(
                silo1, block.timestamp, scenario.input.debtConfig.compoundInterestRate
            );
        }
    }

    /*
    forge test -vv --ffi --mt test_getAssetsDataForLtvCalculations_scenarios
    */
    function test_getAssetsDataForLtvCalculations_scenarios() public {
        GetAssetsDataForLtvCalculationsTestData.ScenarioData[] memory scenarios = dataReader.getScenarios();

        for (uint256 index = 0; index < scenarios.length; index++) {
            (
                ISiloConfig.ConfigData memory collateralConfig,
                ISiloConfig.ConfigData memory debtConfig,
                address borrower,
                ISilo.OracleType oracleType,
                ISilo.AccrueInterestInMemory accrueInMemory,
                uint256 cachedShareDebtBalance
            ) = getData(scenarios[index]);

            SiloSolvencyLib.LtvData memory ltvData = SiloSolvencyLib.getAssetsDataForLtvCalculations(
                collateralConfig, debtConfig, borrower, oracleType, accrueInMemory, cachedShareDebtBalance
            );

            assertEq(
                address(ltvData.collateralOracle),
                // forge-lint: disable-next-line(unsafe-typecast)
                address(uint160(scenarios[index].expected.collateralOracle)),
                string.concat(Strings.toString(scenarios[index].id), " collateralOracle")
            );
            assertEq(
                address(ltvData.debtOracle),
                // forge-lint: disable-next-line(unsafe-typecast)
                address(uint160(scenarios[index].expected.debtOracle)),
                string.concat(Strings.toString(scenarios[index].id), " debtOracle")
            );
            assertEq(
                ltvData.borrowerProtectedAssets,
                scenarios[index].expected.borrowerProtectedAssets,
                string.concat(Strings.toString(scenarios[index].id), " borrowerProtectedAssets")
            );
            assertEq(
                ltvData.borrowerCollateralAssets,
                scenarios[index].expected.borrowerCollateralAssets,
                string.concat(Strings.toString(scenarios[index].id), " borrowerCollateralAssets")
            );
            assertEq(
                ltvData.borrowerDebtAssets,
                scenarios[index].expected.borrowerDebtAssets,
                string.concat(Strings.toString(scenarios[index].id), " borrowerDebtAssets")
            );
        }
    }
}
