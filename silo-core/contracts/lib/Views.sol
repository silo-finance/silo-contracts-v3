// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ISiloConfig} from "../interfaces/ISiloConfig.sol";
import {ISilo} from "../interfaces/ISilo.sol";
import {ISiloOracle} from "../interfaces/ISiloOracle.sol";
import {IShareToken} from "../interfaces/IShareToken.sol";
import {ISiloFactory} from "../interfaces/ISiloFactory.sol";

import {SiloERC4626Lib} from "./SiloERC4626Lib.sol";
import {SiloSolvencyLib} from "./SiloSolvencyLib.sol";
import {SiloLendingLib} from "./SiloLendingLib.sol";
import {SiloStdLib} from "./SiloStdLib.sol";
import {SiloMathLib} from "./SiloMathLib.sol";
import {Rounding} from "./Rounding.sol";
import {ShareTokenLib} from "./ShareTokenLib.sol";
import {SiloStorageLib} from "./SiloStorageLib.sol";

// solhint-disable ordering

library Views {
    bytes32 internal constant _FLASHLOAN_CALLBACK = keccak256("ERC3156FlashBorrower.onFlashLoan");
    uint256 internal constant _100_PERCENT = 1e18;

    function isSolvent(address _borrower) external view returns (bool) {
        (
            ISiloConfig.ConfigData memory collateral,
            ISiloConfig.ConfigData memory debt
        ) = ShareTokenLib.siloConfig().getConfigsForSolvency(_borrower);

        return SiloSolvencyLib.isSolvent(collateral, debt, _borrower, ISilo.AccrueInterestInMemory.Yes);
    }

    /// @notice Returns flash fee amount
    /// @param _token for which fee is calculated
    /// @param _amount for which fee is calculated
    /// @return fee flash fee amount
    function flashFee(address _token, uint256 _amount) external view returns (uint256 fee) {
        fee = SiloStdLib.flashFee(ShareTokenLib.siloConfig(), _token, _amount);
    }

    function maxFlashLoan(address _token) internal view returns (uint256 maxLoan) {
        if (_token != ShareTokenLib.siloConfig().getAssetForSilo(address(this))) return 0;

        ISilo.SiloStorage storage $ = SiloStorageLib.getSiloStorage();
        uint256 protectedAssets = $.totalAssets[ISilo.AssetType.Protected];
        uint256 balance = IERC20(_token).balanceOf(address(this));

        unchecked {
            // we check underflow ourself
            return balance > protectedAssets ? balance - protectedAssets : 0;
        }
    }

    function maxBorrow(address _borrower)
        external
        view
        returns (uint256 maxAssets, uint256 maxShares)
    {
        return SiloLendingLib.maxBorrow(_borrower);
    }

    function maxWithdraw(address _owner, ISilo.CollateralType _collateralType)
        external
        view
        returns (uint256 assets, uint256 shares)
    {
        return SiloERC4626Lib.maxWithdraw(
            _owner,
            _collateralType,
            // 0 for CollateralType.Collateral because it will be calculated internally
            _collateralType == ISilo.CollateralType.Protected
                ? SiloStorageLib.getSiloStorage().totalAssets[ISilo.AssetType.Protected]
                : 0
        );
    }

    function maxRepay(address _borrower) external view returns (uint256 assets) {
        ISiloConfig.ConfigData memory configData = ShareTokenLib.getConfig();
        uint256 shares = IShareToken(configData.debtShareToken).balanceOf(_borrower);

        (uint256 totalSiloAssets, uint256 totalShares) =
            SiloStdLib.getTotalAssetsAndTotalSharesWithInterest(configData, ISilo.AssetType.Debt);

        return SiloMathLib.convertToAssets(
            shares, totalSiloAssets, totalShares, Rounding.MAX_REPAY_TO_ASSETS, ISilo.AssetType.Debt
        );
    }

    function getSiloStorage()
        internal
        view
        returns (
            uint192 daoAndDeployerRevenue,
            uint64 interestRateTimestamp,
            uint256 protectedAssets,
            uint256 collateralAssets,
            uint256 debtAssets
        )
    {
        ISilo.SiloStorage storage $ = SiloStorageLib.getSiloStorage();

        daoAndDeployerRevenue = $.daoAndDeployerRevenue;
        interestRateTimestamp = $.interestRateTimestamp;
        protectedAssets = $.totalAssets[ISilo.AssetType.Protected];
        collateralAssets = $.totalAssets[ISilo.AssetType.Collateral];
        debtAssets = $.totalAssets[ISilo.AssetType.Debt];
    }

    function getFractionsStorage() internal view returns (ISilo.Fractions memory fractions) {
        fractions = SiloStorageLib.getSiloStorage().fractions;
    }

    function utilizationData() internal view returns (ISilo.UtilizationData memory) {
        ISilo.SiloStorage storage $ = SiloStorageLib.getSiloStorage();

        return ISilo.UtilizationData({
            collateralAssets: $.totalAssets[ISilo.AssetType.Collateral],
            debtAssets: $.totalAssets[ISilo.AssetType.Debt],
            interestRateTimestamp: $.interestRateTimestamp
        });
    }

    function getDebtAssets() internal view returns (uint256 totalDebtAssets) {
        ISiloConfig.ConfigData memory thisSiloConfig = ShareTokenLib.getConfig();

        totalDebtAssets = SiloStdLib.getTotalDebtAssetsWithInterest(
            thisSiloConfig.silo, thisSiloConfig.interestRateModel
        );
    }

    function getCollateralAndProtectedAssets()
        internal
        view
        returns (uint256 totalCollateralAssets, uint256 totalProtectedAssets)
    {
        ISilo.SiloStorage storage $ = SiloStorageLib.getSiloStorage();

        totalCollateralAssets = $.totalAssets[ISilo.AssetType.Collateral];
        totalProtectedAssets = $.totalAssets[ISilo.AssetType.Protected];
    }

    function getCollateralAndDebtAssets()
        internal
        view
        returns (uint256 totalCollateralAssets, uint256 totalDebtAssets)
    {
        ISilo.SiloStorage storage $ = SiloStorageLib.getSiloStorage();

        totalCollateralAssets = $.totalAssets[ISilo.AssetType.Collateral];
        totalDebtAssets = $.totalAssets[ISilo.AssetType.Debt];
    }

    function copySiloConfig(
        ISiloConfig.InitData memory _initData,
        ISiloFactory.Range memory _daoFeeRange,
        uint256 _maxDeployerFee,
        uint256 _maxFlashloanFee,
        uint256 _maxLiquidationFee
    )
        internal
        view
        returns (ISiloConfig.ConfigData memory configData0, ISiloConfig.ConfigData memory configData1)
    {
        validateSiloInitData(_initData, _daoFeeRange, _maxDeployerFee, _maxFlashloanFee, _maxLiquidationFee);

        configData0.hookReceiver = _initData.hookReceiver;
        configData0.token = _initData.token0;
        configData0.solvencyOracle = _initData.solvencyOracle0;
        // If maxLtv oracle is not set, fallback to solvency oracle
        configData0.maxLtvOracle = _initData.maxLtvOracle0 == address(0)
            ? _initData.solvencyOracle0
            : _initData.maxLtvOracle0;
        configData0.interestRateModel = _initData.interestRateModel0;
        configData0.maxLtv = _initData.maxLtv0;
        configData0.lt = _initData.lt0;
        configData0.liquidationTargetLtv = _initData.liquidationTargetLtv0;
        configData0.deployerFee = _initData.deployerFee;
        configData0.daoFee = _initData.daoFee;
        configData0.liquidationFee = _initData.liquidationFee0;
        configData0.flashloanFee = _initData.flashloanFee0;
        configData0.callBeforeQuote = _initData.callBeforeQuote0;

        configData1.hookReceiver = _initData.hookReceiver;
        configData1.token = _initData.token1;
        configData1.solvencyOracle = _initData.solvencyOracle1;
        // If maxLtv oracle is not set, fallback to solvency oracle
        configData1.maxLtvOracle = _initData.maxLtvOracle1 == address(0)
            ? _initData.solvencyOracle1
            : _initData.maxLtvOracle1;
        configData1.interestRateModel = _initData.interestRateModel1;
        configData1.maxLtv = _initData.maxLtv1;
        configData1.lt = _initData.lt1;
        configData1.liquidationTargetLtv = _initData.liquidationTargetLtv1;
        configData1.deployerFee = _initData.deployerFee;
        configData1.daoFee = _initData.daoFee;
        configData1.liquidationFee = _initData.liquidationFee1;
        configData1.flashloanFee = _initData.flashloanFee1;
        configData1.callBeforeQuote = _initData.callBeforeQuote1;
    }

    // solhint-disable-next-line code-complexity, function-max-lines
    function validateSiloInitData(
        ISiloConfig.InitData memory _initData,
        ISiloFactory.Range memory _daoFeeRange,
        uint256 _maxDeployerFee,
        uint256 _maxFlashloanFee,
        uint256 _maxLiquidationFee
    ) internal view returns (bool) {
        require(_initData.hookReceiver != address(0), ISiloFactory.MissingHookReceiver());

        require(_initData.token0 != address(0), ISiloFactory.EmptyToken0());
        require(_initData.token1 != address(0), ISiloFactory.EmptyToken1());

        require(_initData.token0 != _initData.token1, ISiloFactory.SameAsset());
        require(_initData.maxLtv0 != 0 || _initData.maxLtv1 != 0, ISiloFactory.InvalidMaxLtv());
        require(_initData.maxLtv0 <= _initData.lt0, ISiloFactory.InvalidMaxLtv());
        require(_initData.maxLtv1 <= _initData.lt1, ISiloFactory.InvalidMaxLtv());
        require(_initData.liquidationFee0 <= _maxLiquidationFee, ISiloFactory.MaxLiquidationFeeExceeded());
        require(_initData.liquidationFee1 <= _maxLiquidationFee, ISiloFactory.MaxLiquidationFeeExceeded());
        require(_initData.lt0 + _initData.liquidationFee0 <= _100_PERCENT, ISiloFactory.InvalidLt());
        require(_initData.lt1 + _initData.liquidationFee1 <= _100_PERCENT, ISiloFactory.InvalidLt());

        require(
            _initData.maxLtvOracle0 == address(0) || _initData.solvencyOracle0 != address(0),
            ISiloFactory.OracleMisconfiguration()
        );

        require(
            !_initData.callBeforeQuote0 || _initData.solvencyOracle0 != address(0),
            ISiloFactory.InvalidCallBeforeQuote()
        );

        require(
            _initData.maxLtvOracle1 == address(0) || _initData.solvencyOracle1 != address(0),
            ISiloFactory.OracleMisconfiguration()
        );

        require(
            !_initData.callBeforeQuote1 || _initData.solvencyOracle1 != address(0),
            ISiloFactory.InvalidCallBeforeQuote()
        );

        verifyQuoteTokens(_initData);

        require(_initData.deployerFee == 0 || _initData.deployer != address(0), ISiloFactory.InvalidDeployer());
        require(_initData.deployerFee <= _maxDeployerFee, ISiloFactory.MaxDeployerFeeExceeded());
        require(_daoFeeRange.min <= _initData.daoFee, ISiloFactory.DaoMinRangeExceeded());
        require(_initData.daoFee <= _daoFeeRange.max, ISiloFactory.DaoMaxRangeExceeded());
        require(_initData.flashloanFee0 <= _maxFlashloanFee, ISiloFactory.MaxFlashloanFeeExceeded());
        require(_initData.flashloanFee1 <= _maxFlashloanFee, ISiloFactory.MaxFlashloanFeeExceeded());
        require(_initData.liquidationTargetLtv0 <= _initData.lt0, ISiloFactory.LiquidationTargetLtvTooHigh());
        require(_initData.liquidationTargetLtv1 <= _initData.lt1, ISiloFactory.LiquidationTargetLtvTooHigh());

        require(
            _initData.interestRateModel0 != address(0) && _initData.interestRateModel1 != address(0),
            ISiloFactory.InvalidIrm()
        );

        return true;
    }

    function verifyQuoteTokens(ISiloConfig.InitData memory _initData) internal view {
        address expectedQuoteToken;

        expectedQuoteToken = verifyQuoteToken(expectedQuoteToken, _initData.solvencyOracle0);
        expectedQuoteToken = verifyQuoteToken(expectedQuoteToken, _initData.maxLtvOracle0);
        expectedQuoteToken = verifyQuoteToken(expectedQuoteToken, _initData.solvencyOracle1);
        expectedQuoteToken = verifyQuoteToken(expectedQuoteToken, _initData.maxLtvOracle1);
    }

    function verifyQuoteToken(address _expectedQuoteToken, address _oracle)
        internal
        view
        returns (address quoteToken)
    {
        if (_oracle == address(0)) return _expectedQuoteToken;

        quoteToken = ISiloOracle(_oracle).quoteToken();

        if (_expectedQuoteToken == address(0)) return quoteToken;
        require(_expectedQuoteToken == quoteToken, ISiloFactory.InvalidQuoteToken());
    }
}
