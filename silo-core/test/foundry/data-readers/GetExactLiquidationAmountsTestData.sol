// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";

contract GetExactLiquidationAmountsTestData {
    uint256 constant SHARES_OFFSET = SiloMathLib._DECIMALS_OFFSET_POW;

    struct Input {
        address user;
        uint256 maxDebtToCover;
        uint256 liquidationFee;
    }

    struct Mocks {
        uint256 protectedUserSharesBalanceOf;
        uint256 protectedSharesTotalSupply;
        uint256 siloTotalProtectedAssets;
        uint256 collateralUserSharesBalanceOf;
        uint256 collateralSharesTotalSupply;
        uint256 siloTotalCollateralAssets;
        uint256 debtUserSharesBalanceOf;
        uint256 debtSharesTotalSupply;
        uint256 siloTotalDebtAssets;
    }

    struct Output {
        uint256 fromCollateral;
        uint256 fromProtected;
        uint256 repayDebtAssets;
    }

    struct GelaData {
        string name;
        Input input;
        Mocks mocks;
        Output output;
    }

    function getData() external pure returns (GelaData[] memory data) {
        data = new GelaData[](8);
        uint256 i;

        data[i].name = "all zeros => zero output";
        data[i].input.user = address(1);
        data[i].input.maxDebtToCover = 1e18;

        i++;
        data[i].name = "expect zero output if user has no debt";
        data[i].input.user = address(1);
        data[i].input.maxDebtToCover = 1e18;

        data[i].mocks.protectedUserSharesBalanceOf = 1e18 * SHARES_OFFSET;
        data[i].mocks.protectedSharesTotalSupply = 10e18 * SHARES_OFFSET;
        data[i].mocks.siloTotalProtectedAssets = 10e18;

        data[i].mocks.collateralUserSharesBalanceOf = 1e18 * SHARES_OFFSET;
        data[i].mocks.collateralSharesTotalSupply = 10e18 * SHARES_OFFSET;
        data[i].mocks.siloTotalCollateralAssets = 10e18;

        data[i].mocks.debtUserSharesBalanceOf = 1e18 * SHARES_OFFSET;
        data[i].mocks.debtSharesTotalSupply = 10e18 * SHARES_OFFSET;
        data[i].mocks.siloTotalDebtAssets = 10e18;

        i++;
        data[i].name = "expect zero when user solvent, protected collateral";
        data[i].input.user = address(1);
        data[i].input.maxDebtToCover = 0.5e18;

        data[i].mocks.protectedUserSharesBalanceOf = 1e18 * SHARES_OFFSET;
        data[i].mocks.protectedSharesTotalSupply = 10e18 * SHARES_OFFSET;
        data[i].mocks.siloTotalProtectedAssets = 10e18;

        data[i].mocks.debtUserSharesBalanceOf = 0.79e18 * SHARES_OFFSET;
        data[i].mocks.debtSharesTotalSupply = 10e18 * SHARES_OFFSET;
        data[i].mocks.siloTotalDebtAssets = 10e18;

        i++;
        data[i] = _clone(data[i - 1]);
        data[i].name = "expect zero when user solvent, protected + collateral";

        data[i].mocks.collateralUserSharesBalanceOf = 1e18 * SHARES_OFFSET;
        data[i].mocks.collateralSharesTotalSupply = 10e18 * SHARES_OFFSET;
        data[i].mocks.siloTotalCollateralAssets = 10e18;

        data[i].mocks.debtUserSharesBalanceOf = 1.59e18 * SHARES_OFFSET;
    }

    function _clone(GelaData memory _src) private pure returns (GelaData memory dst) {
        dst.input.user = address(1);
        dst.input.maxDebtToCover = _src.input.maxDebtToCover;
        dst.input.liquidationFee = _src.input.liquidationFee;

        dst.mocks.protectedUserSharesBalanceOf = _src.mocks.protectedUserSharesBalanceOf;
        dst.mocks.protectedSharesTotalSupply = _src.mocks.protectedSharesTotalSupply;
        dst.mocks.siloTotalProtectedAssets = _src.mocks.siloTotalProtectedAssets;

        dst.mocks.collateralUserSharesBalanceOf = _src.mocks.collateralUserSharesBalanceOf;
        dst.mocks.collateralSharesTotalSupply = _src.mocks.collateralSharesTotalSupply;
        dst.mocks.siloTotalCollateralAssets = _src.mocks.siloTotalCollateralAssets;

        dst.mocks.debtUserSharesBalanceOf = _src.mocks.debtUserSharesBalanceOf;
        dst.mocks.debtSharesTotalSupply = _src.mocks.debtSharesTotalSupply;
        dst.mocks.siloTotalDebtAssets = _src.mocks.siloTotalDebtAssets;
    }
}
