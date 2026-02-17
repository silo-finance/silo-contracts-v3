// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// solhint-disable ordering

import {Strings} from "openzeppelin5/utils/Strings.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {Utils} from "silo-foundry-utils/lib/Utils.sol";

import {ISiloLens, ISilo} from "./interfaces/ISiloLens.sol";
import {IShareToken} from "./interfaces/IShareToken.sol";
import {ISiloConfig} from "./interfaces/ISiloConfig.sol";
import {IPartialLiquidation} from "./interfaces/IPartialLiquidation.sol";
import {IInterestRateModel} from "./interfaces/IInterestRateModel.sol";

import {SiloLensLib} from "./lib/SiloLensLib.sol";
import {SiloStdLib} from "./lib/SiloStdLib.sol";
import {IPartialLiquidation} from "./interfaces/IPartialLiquidation.sol";
import {IDistributionManager} from "silo-core/contracts/incentives/interfaces/IDistributionManager.sol";
import {IVersioned} from "./interfaces/IVersioned.sol";


/// @title SiloLens is a helper contract for integrations and UI
contract SiloLens is ISiloLens, IVersioned {
    uint256 internal constant _PRECISION_DECIMALS = 1e18;

    /// @notice version contains the contract name and release version
    string public constant VERSION = "SiloLens 4.0.0";

    /// @inheritdoc ISiloLens
    function getVersion(address _contract) external view returns (string memory version) {
        version = SiloLensLib.getVersion(_contract);
    }

    function getVersions(address[] calldata _contracts) external view returns (string[] memory versions) {
        versions = new string[](_contracts.length);

        for (uint256 i; i < _contracts.length; i++) {
            versions[i] = SiloLensLib.getVersion(_contracts[i]);
        }
    }

    /// @inheritdoc ISiloLens
    function isSolvent(ISilo _silo, address _borrower) external view returns (bool) {
        return _silo.isSolvent(_borrower);
    }

    /// @inheritdoc ISiloLens
    function liquidity(ISilo _silo) external view returns (uint256) {
        return _silo.getLiquidity();
    }

    /// @inheritdoc ISiloLens
    function getRawLiquidity(ISilo _silo) external view virtual returns (uint256 rawLiquidity) {
        rawLiquidity = SiloLensLib.getRawLiquidity(_silo);
    }

    /// @inheritdoc ISiloLens
    function getMaxLtv(ISilo _silo) external view virtual returns (uint256 maxLtv) {
        return SiloLensLib.getMaxLtv(_silo);
    }

    /// @inheritdoc ISiloLens
    function getLt(ISilo _silo) external view virtual returns (uint256 lt) {
        lt = SiloLensLib.getLt(_silo);
    }

    /// @inheritdoc ISiloLens
    function getUserLT(ISilo _silo, address _borrower) external view returns (uint256 userLT) {
        return SiloLensLib.getUserLt(_silo, _borrower);
    }

    function getUsersLT(Borrower[] calldata _borrowers) external view returns (uint256[] memory usersLTs) {
        usersLTs = new uint256[](_borrowers.length);

        for (uint256 i; i < _borrowers.length; i++) {
            Borrower memory borrower = _borrowers[i];
            usersLTs[i] = SiloLensLib.getUserLt(borrower.silo, borrower.wallet);
        }
    }

    function getUsersHealth(Borrower[] calldata _borrowers) external view returns (BorrowerHealth[] memory healths) {
        healths = new BorrowerHealth[](_borrowers.length);

        for (uint256 i; i < _borrowers.length; i++) {
            Borrower memory borrower = _borrowers[i];
            BorrowerHealth memory health = healths[i];

            (health.ltv, health.lt) = SiloLensLib.getLtvAndLt(borrower.silo, borrower.wallet);
        }
    }

    /// @inheritdoc ISiloLens
    function getUserLTV(ISilo _silo, address _borrower) external view returns (uint256 userLTV) {
        return SiloLensLib.getLtv(_silo, _borrower);
    }

    /// @inheritdoc ISiloLens
    function getLtv(ISilo _silo, address _borrower) external view virtual returns (uint256 ltv) {
        return SiloLensLib.getLtv(_silo, _borrower);
    }

    /// @inheritdoc ISiloLens
    function hasPosition(ISiloConfig _siloConfig, address _borrower) external view virtual returns (bool has) {
        has = SiloLensLib.hasPosition(_siloConfig, _borrower);
    }

    /// @inheritdoc ISiloLens
    function inDebt(ISiloConfig _siloConfig, address _borrower) external view returns (bool hasDebt) {
        hasDebt = SiloLensLib.inDebt(_siloConfig, _borrower);
    }

    /// @inheritdoc ISiloLens
    function calculateProfitableLiquidation(ISilo _silo, address _borrower) 
        external
        view
        returns (uint256 collateralToLiquidate, uint256 debtToCover)
    {
        (collateralToLiquidate, debtToCover) = SiloLensLib.calculateProfitableLiquidation(_silo, _borrower);
    }

    /// @inheritdoc ISiloLens
    function getFeesAndFeeReceivers(ISilo _silo)
        external
        view
        virtual
        returns (address daoFeeReceiver, address deployerFeeReceiver, uint256 daoFee, uint256 deployerFee)
    {
        (daoFeeReceiver, deployerFeeReceiver, daoFee, deployerFee,) = SiloStdLib.getFeesAndFeeReceiversWithAsset(_silo);
    }

    /// @inheritdoc ISiloLens
    function collateralBalanceOfUnderlying(ISilo _silo, address _borrower)
        external
        view
        virtual
        returns (uint256 borrowerCollateral)
    {
        return SiloLensLib.collateralBalanceOfUnderlying(_silo, _borrower);
    }

    /// @inheritdoc ISiloLens
    function debtBalanceOfUnderlying(ISilo _silo, address _borrower) external view virtual returns (uint256) {
        return _silo.maxRepay(_borrower);
    }

    /// @inheritdoc ISiloLens
    function maxLiquidation(ISilo _silo, IPartialLiquidation _hook, address _borrower)
        external
        view
        virtual
        returns (uint256 collateralToLiquidate, uint256 debtToRepay, bool sTokenRequired, bool fullLiquidation)
    {
        (collateralToLiquidate, debtToRepay, sTokenRequired) = _hook.maxLiquidation(_borrower);

        uint256 maxRepay = _silo.maxRepay(_borrower);
        fullLiquidation = maxRepay == debtToRepay;

        if (!sTokenRequired) return (collateralToLiquidate, debtToRepay, sTokenRequired, fullLiquidation);

        ISiloConfig siloConfig = _silo.config();

        (ISiloConfig.ConfigData memory collateralConfig,) = siloConfig.getConfigsForSolvency(_borrower);

        uint256 protectedShares = IERC20(collateralConfig.protectedShareToken).balanceOf(_borrower);

        if (protectedShares == 0) return (collateralToLiquidate, debtToRepay, sTokenRequired, fullLiquidation);

        uint256 protectedAssets = ISilo(collateralConfig.silo).convertToAssets(
            protectedShares,
            ISilo.AssetType.Protected
        );

        if (protectedAssets == 0) return (collateralToLiquidate, debtToRepay, sTokenRequired, fullLiquidation);

        uint256 availableLiquidity = ISilo(collateralConfig.silo).getLiquidity();

        sTokenRequired = availableLiquidity + protectedAssets < collateralToLiquidate;
    }

    /// @inheritdoc ISiloLens
    function totalDeposits(ISilo _silo) external view returns (uint256 totalDepositsAmount) {
        totalDepositsAmount = _silo.getTotalAssetsStorage(ISilo.AssetType.Collateral);
    }

    /// @inheritdoc ISiloLens
    function totalDepositsWithInterest(ISilo _silo) external view returns (uint256 amount) {
        amount = _silo.totalAssets();
    }

    function totalBorrowAmountWithInterest(ISilo _silo) external view returns (uint256 amount) {
        amount = _silo.getDebtAssets();
    }

    /// @inheritdoc ISiloLens
    function collateralOnlyDeposits(ISilo _silo) external view returns (uint256) {
        return _silo.getTotalAssetsStorage(ISilo.AssetType.Protected);
    }

    /// @inheritdoc ISiloLens
    function getDepositAmount(ISilo _silo, address _borrower)
        external
        view
        returns (uint256 borrowerDeposits)
    {
        borrowerDeposits = _silo.previewRedeem(_silo.balanceOf(_borrower));
    }

    /// @inheritdoc ISiloLens
    function totalBorrowAmount(ISilo _silo) external view returns (uint256) {
        return _silo.getTotalAssetsStorage(ISilo.AssetType.Debt);
    }

    /// @inheritdoc ISiloLens
    function totalBorrowShare(ISilo _silo) external view returns (uint256) {
        return SiloLensLib.totalBorrowShare(_silo);
    }

    /// @inheritdoc ISiloLens
    function getBorrowAmount(ISilo _silo, address _borrower)
        external
        view
        returns (uint256 maxRepay)
    {
        maxRepay = _silo.maxRepay(_borrower);
    }

    /// @inheritdoc ISiloLens
    function borrowShare(ISilo _silo, address _borrower) external view returns (uint256) {
        return SiloLensLib.borrowShare(_silo, _borrower);
    }

    /// @inheritdoc ISiloLens
    function protocolFees(ISilo _silo) external view returns (uint256 daoAndDeployerRevenue) {
        (daoAndDeployerRevenue,,,,) = _silo.getSiloStorage();
    }

    /// @inheritdoc ISiloLens
    function calculateCollateralValue(ISiloConfig _siloConfig, address _borrower)
        external
        view
        returns (uint256 collateralValue)
    {
        (collateralValue,) = SiloLensLib.calculateValues(_siloConfig, _borrower);
    }

    /// @inheritdoc ISiloLens
    function calculateBorrowValue(ISiloConfig _siloConfig, address _borrower)
        external
        view
        returns (uint256 borrowValue)
    {
        (, borrowValue) = SiloLensLib.calculateValues(_siloConfig, _borrower);
    }

    /// @inheritdoc ISiloLens
    function getUtilization(ISilo _silo) external view returns (uint256 utilization) {
        ISilo.UtilizationData memory data = _silo.utilizationData();

        if (data.collateralAssets != 0) {
            utilization = data.debtAssets * _PRECISION_DECIMALS / data.collateralAssets;
        }
    }

    /// @inheritdoc ISiloLens
    function getInterestRateModel(ISilo _silo) external view virtual returns (address irm) {
        return SiloLensLib.getInterestRateModel(_silo);
    }

    /// @inheritdoc ISiloLens
    function getBorrowAPR(ISilo _silo) external view virtual returns (uint256 borrowAPR) {
        return SiloLensLib.getBorrowAPR(_silo);
    }

    /// @inheritdoc ISiloLens
    function getDepositAPR(ISilo _silo) external view virtual returns (uint256 depositAPR) {
        return SiloLensLib.getDepositAPR(_silo);
    }

    /// @inheritdoc ISiloLens
    function getAPRs(ISilo[] calldata _silos) external view virtual returns (APR[] memory aprs) {
        aprs = new APR[](_silos.length);

        for (uint256 i; i < _silos.length; i++) {
            ISilo silo = _silos[i];

            aprs[i] = APR({
                borrowAPR: SiloLensLib.getBorrowAPR(silo),
                depositAPR: SiloLensLib.getDepositAPR(silo)
            });
        }
    }

    function getModel(ISilo _silo) public view returns (IInterestRateModel irm) {
        irm = IInterestRateModel(_silo.config().getConfig(address(_silo)).interestRateModel);
    }

    function getSiloIncentivesControllerProgramsNames(
        address _siloIncentivesController
    ) public view returns (string[] memory programsNames) {
        IDistributionManager distributionManager = IDistributionManager(_siloIncentivesController);
        string[] memory originalProgramsNames = distributionManager.getAllProgramsNames();

        programsNames = new string[](originalProgramsNames.length);

        for (uint256 i; i < originalProgramsNames.length; i++) {
            bytes memory originalProgramName = bytes(originalProgramsNames[i]);

            if (_isTokenAddress(originalProgramName)) {
                address token = address(bytes20(originalProgramName));
                programsNames[i] = Strings.toHexString(token);
            } else {
                programsNames[i] = originalProgramsNames[i];
            }
        }
    }

    function getOracleAddresses(ISilo _silo) external view returns (address solvencyOracle, address maxLtvOracle) {
        ISiloConfig.ConfigData memory config = _silo.config().getConfig(address(_silo));

        solvencyOracle = config.solvencyOracle;
        maxLtvOracle = config.maxLtvOracle;
    }

    function _isTokenAddress(bytes memory _name) private view returns (bool isToken) {
        if (_name.length != 20) return false;

        address token = address(bytes20(_name));

        if (Utils.getCodeAt(token).length == 0) return false;

        // Sanity check to be sure that it is a token
        try IERC20(token).balanceOf(address(this)) returns (uint256) {
            isToken = true;
        } catch {}
    }
}
