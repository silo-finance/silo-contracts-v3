// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// solhint-disable ordering

import {ISilo} from "../interfaces/ISilo.sol";
import {IShareToken} from "../interfaces/IShareToken.sol";

import {ISiloConfig} from "../interfaces/ISiloConfig.sol";
import {IInterestRateModel} from "../interfaces/IInterestRateModel.sol";
import {IPartialLiquidation} from "../interfaces/IPartialLiquidation.sol";
import {ISiloOracle} from "../interfaces/ISiloOracle.sol";
import {IVersioned} from "../interfaces/IVersioned.sol";

import {SiloSolvencyLib} from "./SiloSolvencyLib.sol";
import {SiloMathLib} from "./SiloMathLib.sol";

library SiloLensLib {
    uint256 internal constant _PRECISION_DECIMALS = 1e18;

    function getVersion(address _contract) internal view returns (string memory version) {
        if (_contract.code.length == 0) return "Not a contract";

        try IVersioned(_contract).VERSION() returns (string memory v) {
            return v;
        } catch {
            // handle error gracefully
            return "legacy";
        }
    }

    function getRawLiquidity(ISilo _silo) internal view returns (uint256 liquidity) {
        return SiloMathLib.liquidity(
            _silo.getTotalAssetsStorage(ISilo.AssetType.Collateral),
            _silo.getTotalAssetsStorage(ISilo.AssetType.Debt)
        );
    }

    function getMaxLtv(ISilo _silo) internal view returns (uint256 maxLtv) {
        maxLtv = _silo.config().getConfig(address(_silo)).maxLtv;
    }

    function getLt(ISilo _silo) internal view returns (uint256 lt) {
        lt = _silo.config().getConfig(address(_silo)).lt;
    }

    function getInterestRateModel(ISilo _silo) internal view returns (address irm) {
        irm = _silo.config().getConfig(address(_silo)).interestRateModel;
    }

    function getBorrowAPR(ISilo _silo) internal view returns (uint256 borrowAPR) {
        IInterestRateModel model = IInterestRateModel(_silo.config().getConfig((address(_silo))).interestRateModel);
        borrowAPR = model.getCurrentInterestRate(address(_silo), block.timestamp);
    }

    function getDepositAPR(ISilo _silo) internal view returns (uint256 depositAPR) {
        uint256 collateralAssets = _silo.getCollateralAssets();

        if (collateralAssets == 0) {
            return 0;
        }

        ISiloConfig.ConfigData memory cfg = _silo.config().getConfig((address(_silo)));
        depositAPR = getBorrowAPR(_silo) * _silo.getDebtAssets() / collateralAssets;
        depositAPR = depositAPR * (_PRECISION_DECIMALS - cfg.daoFee - cfg.deployerFee) / _PRECISION_DECIMALS;
    }

    /// @dev calculate profitable liquidation values, in case of bad debt, it will calculate max debt to cover
    /// based on available collateral.
    /// Result returned by this method might not work for case, when full liquidation is required.
    function calculateProfitableLiquidation(ISilo _silo, address _borrower)
        internal
        view
        returns (uint256 collateralToLiquidate, uint256 debtToCover)
    {
        IPartialLiquidation _hook = IPartialLiquidation(IShareToken(address(_silo)).hookReceiver());
        (collateralToLiquidate, debtToCover,) = _hook.maxLiquidation(_borrower);

        if (collateralToLiquidate == 0) return (0, 0);

        (ISiloConfig.ConfigData memory collateralConfig, ISiloConfig.ConfigData memory debtConfig) =
            _silo.config().getConfigsForSolvency(_borrower);

        uint256 collateralValue = collateralConfig.solvencyOracle == address(0)
            ? collateralToLiquidate
            : ISiloOracle(collateralConfig.solvencyOracle).quote(collateralToLiquidate, collateralConfig.token);

        uint256 debtValue = debtConfig.solvencyOracle == address(0)
            ? debtToCover
            : ISiloOracle(debtConfig.solvencyOracle).quote(debtToCover, debtConfig.token);

        uint256 debtValueToCover =
            collateralValue * _PRECISION_DECIMALS / (_PRECISION_DECIMALS + collateralConfig.liquidationFee);

        debtToCover = debtToCover * debtValueToCover / debtValue; // rounding down
    }

    function getLtv(ISilo _silo, address _borrower) internal view returns (uint256 ltv) {
        (
            ISiloConfig.ConfigData memory collateralConfig,
            ISiloConfig.ConfigData memory debtConfig
        ) = _silo.config().getConfigsForSolvency(_borrower);

        if (debtConfig.silo != address(0)) {
            ltv = SiloSolvencyLib.getLtv(
                collateralConfig,
                debtConfig,
                _borrower,
                ISilo.OracleType.Solvency,
                ISilo.AccrueInterestInMemory.Yes,
                IShareToken(debtConfig.debtShareToken).balanceOf(_borrower)
            );
        }
    }

    function getUserLt(ISilo _silo, address _borrower) internal view returns (uint256 lt) {
        (
            ISiloConfig.ConfigData memory collateralConfig,
            ISiloConfig.ConfigData memory debtConfig
        ) = _silo.config().getConfigsForSolvency(_borrower);

        if (debtConfig.silo != address(0)) lt = collateralConfig.lt;
    }

    function getLtvAndLt(ISilo _silo, address _borrower) internal view returns (uint256 ltv, uint256 lt) {
        (
            ISiloConfig.ConfigData memory collateralConfig,
            ISiloConfig.ConfigData memory debtConfig
        ) = _silo.config().getConfigsForSolvency(_borrower);

        if (debtConfig.silo != address(0)) {
            ltv = SiloSolvencyLib.getLtv(
                collateralConfig,
                debtConfig,
                _borrower,
                ISilo.OracleType.Solvency,
                ISilo.AccrueInterestInMemory.Yes,
                IShareToken(debtConfig.debtShareToken).balanceOf(_borrower)
            );

            lt = collateralConfig.lt;
        }
    }

    function hasPosition(ISiloConfig _siloConfig, address _borrower) internal view returns (bool has) {
        (address silo0, address silo1) = _siloConfig.getSilos();
        ISiloConfig.ConfigData memory cfg0 = _siloConfig.getConfig(silo0);
        ISiloConfig.ConfigData memory cfg1 = _siloConfig.getConfig(silo1);

        if (IShareToken(cfg0.collateralShareToken).balanceOf(_borrower) != 0) return true;
        if (IShareToken(cfg0.protectedShareToken).balanceOf(_borrower) != 0) return true;
        if (IShareToken(cfg1.collateralShareToken).balanceOf(_borrower) != 0) return true;
        if (IShareToken(cfg1.protectedShareToken).balanceOf(_borrower) != 0) return true;

        if (IShareToken(cfg0.debtShareToken).balanceOf(_borrower) != 0) return true;
        if (IShareToken(cfg1.debtShareToken).balanceOf(_borrower) != 0) return true;

        return false;
    }

    function inDebt(ISiloConfig _siloConfig, address _borrower) internal view returns (bool has) {
        (, ISiloConfig.ConfigData memory debtConfig) = _siloConfig.getConfigsForSolvency(_borrower);

        has = debtConfig.debtShareToken != address(0)
            && IShareToken(debtConfig.debtShareToken).balanceOf(_borrower) != 0;
    }

    function collateralBalanceOfUnderlying(ISilo _silo, address _borrower)
        internal
        view
        returns (uint256 borrowerCollateral)
    {
        (
            address protectedShareToken, address collateralShareToken,
        ) = _silo.config().getShareTokens(address(_silo));

        uint256 protectedShareBalance = IShareToken(protectedShareToken).balanceOf(_borrower);
        uint256 collateralShareBalance = IShareToken(collateralShareToken).balanceOf(_borrower);

        if (protectedShareBalance != 0) {
            borrowerCollateral = _silo.previewRedeem(protectedShareBalance, ISilo.CollateralType.Protected);
        }

        if (collateralShareBalance != 0) {
            borrowerCollateral += _silo.previewRedeem(collateralShareBalance, ISilo.CollateralType.Collateral);
        }
    }

    function totalBorrowShare(ISilo _silo) internal view returns (uint256) {
        (,, address debtShareToken) = _silo.config().getShareTokens(address(_silo));
        return IShareToken(debtShareToken).totalSupply();
    }

    function borrowShare(ISilo _silo, address _borrower) external view returns (uint256) {
        (,, address debtShareToken) = _silo.config().getShareTokens(address(_silo));
        return IShareToken(debtShareToken).balanceOf(_borrower);
    }

    function calculateValues(ISiloConfig _siloConfig, address _borrower)
        internal
        view
        returns (uint256 sumOfBorrowerCollateralValue, uint256 totalBorrowerDebtValue)
    {
        (
            ISiloConfig.ConfigData memory collateralConfig,
            ISiloConfig.ConfigData memory debtConfig
        ) = _siloConfig.getConfigsForSolvency(_borrower);

        // if no debt collateralConfig and debtConfig are empty
        if (collateralConfig.token == address(0)) return (0, 0);

        SiloSolvencyLib.LtvData memory ltvData = SiloSolvencyLib.getAssetsDataForLtvCalculations(
            collateralConfig,
            debtConfig,
            _borrower,
            ISilo.OracleType.Solvency,
            ISilo.AccrueInterestInMemory.Yes,
            IShareToken(debtConfig.debtShareToken).balanceOf(_borrower)
        );

        (
            sumOfBorrowerCollateralValue, totalBorrowerDebtValue,
        ) = SiloSolvencyLib.calculateLtv(ltvData, collateralConfig.token, debtConfig.token);
    }
}
