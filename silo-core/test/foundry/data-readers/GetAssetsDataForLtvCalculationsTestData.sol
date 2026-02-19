// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

contract GetAssetsDataForLtvCalculationsTestData is Test {
    // must be in alphabetic order
    struct DebtConfigInput {
        bool cachedBalance;
        uint256 compoundInterestRate;
        uint256 debtShareBalanceOf;
        uint256 debtShareTotalSupply;
        uint256 maxLtvOracle;
        uint256 solvencyOracle;
        uint256 totalDebtAssets;
    }

    struct CollateralConfigInput {
        uint256 collateralShareBalanceOf;
        uint256 collateralShareTotalSupply;
        uint256 compoundInterestRate;
        uint256 daoFee;
        uint256 deployerFee;
        uint256 maxLtvOracle;
        uint256 protectedShareBalanceOf;
        uint256 protectedShareTotalSupply;
        uint256 solvencyOracle;
        uint256 totalCollateralAssets;
        uint256 totalDebtAssets;
        uint256 totalProtectedAssets;
    }

    struct Input {
        bool accrueInMemory;
        CollateralConfigInput collateralConfig;
        DebtConfigInput debtConfig;
        string oracleType;
    }

    struct Expected {
        uint256 borrowerCollateralAssets;
        uint256 borrowerDebtAssets;
        uint256 borrowerProtectedAssets;
        uint256 collateralOracle;
        uint256 debtOracle;
    }

    struct ScenarioData {
        Expected expected;
        uint256 id;
        Input input;
    }

    function _readInput(string memory input) internal view returns (string memory) {
        string memory inputDir = string.concat(vm.projectRoot(), "/silo-core/test/foundry/data/");
        string memory file = string.concat(input, ".json");
        return vm.readFile(string.concat(inputDir, file));
    }

    function _readDataFromJson() internal view returns (ScenarioData[] memory) {
        return abi.decode(
            vm.parseJson(_readInput("GetAssetsDataForLtvCalculationsScenarios"), string(abi.encodePacked("."))),
            (ScenarioData[])
        );
    }

    function getScenarios() public view returns (ScenarioData[] memory scenarios) {
        scenarios = _readDataFromJson();
    }

    function print(ScenarioData memory scenario) public {
        // Print ScenarioData
        emit log_named_uint("id", scenario.id);

        // Print Input struct within ScenarioData
        emit log_named_string("accrueInMemory", scenario.input.accrueInMemory ? "Yes" : "No");
        emit log_named_string("oracleType", scenario.input.oracleType);

        // Print DebtConfig struct within Input
        emit log_named_uint("compoundInterestRate_debt", scenario.input.debtConfig.compoundInterestRate);
        emit log_named_uint("debtShareBalanceOf", scenario.input.debtConfig.debtShareBalanceOf);
        emit log_named_uint("debtShareTotalSupply", scenario.input.debtConfig.debtShareTotalSupply);
        emit log_named_uint("maxLtvOracle_debt", scenario.input.debtConfig.maxLtvOracle);
        emit log_named_uint("solvencyOracle_debt", scenario.input.debtConfig.solvencyOracle);
        emit log_named_uint("totalDebtAssets_debt", scenario.input.debtConfig.totalDebtAssets);
        emit log_named_string("cachedBalance", scenario.input.debtConfig.cachedBalance ? "true" : "false");

        // Print CollateralConfig struct within Input
        emit log_named_uint("collateralShareBalanceOf", scenario.input.collateralConfig.collateralShareBalanceOf);
        emit log_named_uint(
            "collateralShareTotalSupply", scenario.input.collateralConfig.collateralShareTotalSupply
        );
        emit log_named_uint("compoundInterestRate_collateral", scenario.input.collateralConfig.compoundInterestRate);
        emit log_named_uint("daoFee", scenario.input.collateralConfig.daoFee);
        emit log_named_uint("deployerFee", scenario.input.collateralConfig.deployerFee);
        emit log_named_uint("maxLtvOracle_collateral", scenario.input.collateralConfig.maxLtvOracle);
        emit log_named_uint("solvencyOracle_collateral", scenario.input.collateralConfig.solvencyOracle);
        emit log_named_uint("protectedShareBalanceOf", scenario.input.collateralConfig.protectedShareBalanceOf);
        emit log_named_uint("protectedShareTotalSupply", scenario.input.collateralConfig.protectedShareTotalSupply);
        emit log_named_uint("totalCollateralAssets", scenario.input.collateralConfig.totalCollateralAssets);
        emit log_named_uint("totalDebtAssets_collateral", scenario.input.collateralConfig.totalDebtAssets);
        emit log_named_uint("totalProtectedAssets", scenario.input.collateralConfig.totalProtectedAssets);

        // Print Expected struct within ScenarioData
        emit log_named_uint("borrowerCollateralAssets", scenario.expected.borrowerCollateralAssets);
        emit log_named_uint("borrowerDebtAssets", scenario.expected.borrowerDebtAssets);
        emit log_named_uint("borrowerProtectedAssets", scenario.expected.borrowerProtectedAssets);
        emit log_named_uint("collateralOracle", scenario.expected.collateralOracle);
        emit log_named_uint("debtOracle", scenario.expected.debtOracle);
    }
}
