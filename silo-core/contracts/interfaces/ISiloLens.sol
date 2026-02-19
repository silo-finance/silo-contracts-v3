// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {ISiloConfig} from "./ISiloConfig.sol";
import {ISilo} from "./ISilo.sol";
import {IInterestRateModel} from "./IInterestRateModel.sol";
import {IPartialLiquidation} from "./IPartialLiquidation.sol";

interface ISiloLens {
    struct Borrower {
        ISilo silo;
        address wallet;
    }

    struct BorrowerHealth {
        uint256 lt;
        uint256 ltv;
    }

    struct APR {
        uint256 depositAPR;
        uint256 borrowAPR;
    }

    error InvalidAsset();

    /// @notice Retrieves the version of the contract
    /// @param _contract Address of the contract
    /// @return version The version of the contract in format "SiloLens 3.17.0",
    /// "legacy" if not implement IVersioned, "Not a contract" if not a contract.
    function getVersion(address _contract) external view returns (string memory version);

    /// @notice Retrieves the versions of the contracts
    /// @param _contracts Addresses of the contracts
    /// @return versions The versions of the contracts in format "SiloLens 3.17.0",
    /// "legacy" if not implement IVersioned, "Not a contract" if not a contract.
    function getVersions(address[] calldata _contracts) external view returns (string[] memory versions);

    /// @dev calculates solvency
    /// @notice this is backwards compatible method, you can use `_silo.isSolvent(_borrower)` directly.
    /// @param _silo Silo address from which to read data
    /// @param _borrower wallet address
    /// @return true if solvent, false otherwise
    function isSolvent(ISilo _silo, address _borrower) external view returns (bool);

    /// @dev Amount of token that is available for borrowing.
    /// @notice this is backwards compatible method, you can use `_silo.getLiquidity()`
    /// @param _silo Silo address from which to read data
    /// @return Silo liquidity
    function liquidity(ISilo _silo) external view returns (uint256);

    /// @return liquidity based on contract state (without interest, fees)
    function getRawLiquidity(ISilo _silo) external view returns (uint256 liquidity);

    /// @notice Retrieves the maximum loan-to-value (LTV) ratio
    /// @param _silo Address of the silo
    /// @return maxLtv The maximum LTV ratio configured for the silo in 18 decimals points
    function getMaxLtv(ISilo _silo) external view returns (uint256 maxLtv);

    /// @notice Retrieves the LT value
    /// @param _silo Address of the silo
    /// @return lt The LT value in 18 decimals points
    function getLt(ISilo _silo) external view returns (uint256 lt);

    /// @notice Retrieves the LT for a specific borrower
    /// @param _silo Address of the silo
    /// @param _borrower Address of the borrower
    /// @return userLT The LT for the borrower in 18 decimals points, returns 0 if no debt
    function getUserLT(ISilo _silo, address _borrower) external view returns (uint256 userLT);

    /// @notice Retrieves the LT for a specific borrowers
    /// @param _borrowers list of borrowers with corresponding silo addresses
    /// @return usersLTs The LTs for the borrowers in 18 decimals points, returns 0 for users with no debt
    function getUsersLT(Borrower[] calldata _borrowers) external view returns (uint256[] memory usersLTs);

    /// @notice Retrieves the LT and LTV for a specific borrowers
    /// @param _borrowers list of borrowers with corresponding silo addresses
    /// @return healths The LTs and LTVs for the borrowers in 18 decimals points, returns 0 for users with no debt
    function getUsersHealth(Borrower[] calldata _borrowers) external view returns (BorrowerHealth[] memory healths);

    /// @notice Retrieves the loan-to-value (LTV) for a specific borrower
    /// @param _silo Address of the silo
    /// @param _borrower Address of the borrower
    /// @return userLTV The LTV for the borrower in 18 decimals points
    function getUserLTV(ISilo _silo, address _borrower) external view returns (uint256 userLTV);

    /// @notice Retrieves the loan-to-value (LTV) for a specific borrower
    /// @param _silo Address of the silo
    /// @param _borrower Address of the borrower
    /// @return ltv The LTV for the borrower in 18 decimals points
    function getLtv(ISilo _silo, address _borrower) external view returns (uint256 ltv);

    /// @notice Check if user has position (collateral, protected or debt)
    /// in any asset in a market (both silos are checked)
    /// @param _siloConfig Market address (silo config address)
    /// @param _borrower wallet address for which to read data
    /// @return TRUE if user has position in any asset
    function hasPosition(ISiloConfig _siloConfig, address _borrower) external view returns (bool);

    /// @notice Check if user is in debt
    /// @param _siloConfig Market address (silo config address)
    /// @param _borrower wallet address for which to read data
    /// @return TRUE if user borrowed any amount of any asset, otherwise FALSE
    function inDebt(ISiloConfig _siloConfig, address _borrower) external view returns (bool);

    /// @dev calculate profitable liquidation values, in case of bad debt, it will calculate max debt to cover
    /// based on available collateral. 
    /// Result returned by this method might not work for case, when full liquidation is required.
    function calculateProfitableLiquidation(ISilo _silo, address _borrower) 
        external
        view
        returns (uint256 collateralToLiquidate, uint256 debtToCover);

    /// @notice Retrieves the fee details in 18 decimals points and the addresses of the DAO and deployer fee receivers
    /// @param _silo Address of the silo
    /// @return daoFeeReceiver The address of the DAO fee receiver
    /// @return deployerFeeReceiver The address of the deployer fee receiver
    /// @return daoFee The total fee for the DAO in 18 decimals points
    /// @return deployerFee The total fee for the deployer in 18 decimals points
    function getFeesAndFeeReceivers(ISilo _silo)
        external
        view
        returns (address daoFeeReceiver, address deployerFeeReceiver, uint256 daoFee, uint256 deployerFee);

    /// @notice Get underlying balance of all deposits of silo asset of given user including "protected"
    /// deposits, with interest
    /// @param _silo Address of the silo
    /// @param _borrower wallet address for which to read data
    /// @return balance of underlying tokens for the given `_borrower`
    function collateralBalanceOfUnderlying(ISilo _silo, address _borrower)
        external
        view
        returns (uint256);

    /// @notice Get amount of debt of underlying token for given user
    /// @param _silo Silo address from which to read data
    /// @param _borrower wallet address for which to read data
    /// @return balance of underlying token owed
    function debtBalanceOfUnderlying(ISilo _silo, address _borrower) external view returns (uint256);

    /// @param _silo silo where borrower has debt
    /// @param _hook hook for silo with debt
    /// @param _borrower borrower address
    /// @return collateralToLiquidate underestimated amount of collateral liquidator will get
    /// @return debtToRepay debt amount needed to be repay to get `collateralToLiquidate`
    /// @return sTokenRequired TRUE, when liquidation with underlying asset is not possible because of not enough
    /// liquidity
    /// @return fullLiquidation TRUE if position has to be fully liquidated
    function maxLiquidation(ISilo _silo, IPartialLiquidation _hook, address _borrower)
        external
        view
        returns (uint256 collateralToLiquidate, uint256 debtToRepay, bool sTokenRequired, bool fullLiquidation);

    /// @notice Get amount of underlying asset that has been deposited to Silo
    /// @dev It reads directly from storage so interest generated between last update and now is not
    /// taken for account
    /// @param _silo Silo address from which to read data
    /// @return totalDeposits amount of all deposits made for given asset
    function totalDeposits(ISilo _silo) external view returns (uint256 totalDeposits);

    /// @notice returns total deposits with interest dynamically calculated at current block timestamp
    /// @return total deposits amount with interest
    function totalDepositsWithInterest(ISilo _silo) external view returns (uint256);

    /// @notice returns total borrow amount with interest dynamically calculated at current block timestamp
    /// @return _totalBorrowAmount total deposits amount with interest
    function totalBorrowAmountWithInterest(ISilo _silo)
        external
        view
        returns (uint256 _totalBorrowAmount);

    /// @notice Get amount of protected asset token that has been deposited to Silo
    /// @param _silo Silo address from which to read data
    /// @return amount of all "protected" deposits
    function collateralOnlyDeposits(ISilo _silo) external view returns (uint256);

    /// @notice Calculates current deposit (with interest) for user
    /// without protected deposits
    /// @param _silo Silo address from which to read data
    /// @param _borrower account for which calculation are done
    /// @return borrowerDeposits amount of asset _borrower posses
    function getDepositAmount(ISilo _silo, address _borrower)
        external
        view
        returns (uint256 borrowerDeposits);

    /// @notice Get amount of asset that has been borrowed
    /// @dev It reads directly from storage so interest generated between last update and now is not
    /// taken for account
    /// @param _silo Silo address from which to read data
    /// @return amount of asset that has been borrowed
    function totalBorrowAmount(ISilo _silo) external view returns (uint256);

    /// @notice Get totalSupply of debt token
    /// @dev Debt token represents a share in total debt of given asset
    /// @param _silo Silo address from which to read data
    /// @return totalSupply of debt token
    function totalBorrowShare(ISilo _silo) external view returns (uint256);

    /// @notice Calculates current borrow amount for user with interest
    /// @param _silo Silo address from which to read data
    /// @param _borrower account for which calculation are done
    /// @return total amount of asset user needs to repay at provided timestamp
    function getBorrowAmount(ISilo _silo, address _borrower)
        external
        view
        returns (uint256);

    /// @notice Get debt token balance of a user
    /// @dev Debt token represents a share in total debt of given asset.
    /// This method calls balanceOf(_borrower) on that token.
    /// @param _silo Silo address from which to read data
    /// @param _borrower wallet address for which to read data
    /// @return balance of debt token of given user
    function borrowShare(ISilo _silo, address _borrower) external view returns (uint256);

    /// @notice Get amount of fees earned by protocol to date
    /// @dev It reads directly from storage so interest generated between last update and now is not
    /// taken for account. In SiloLens v1 this was total (ever growing) amount, in this one is since last withdraw.
    /// @param _silo Silo address from which to read data
    /// @return amount of fees earned by protocol to date since last withdraw
    function protocolFees(ISilo _silo) external view returns (uint256);

    /// @notice Calculate value of collateral asset for user
    /// @dev It dynamically adds interest earned. Takes for account protected deposits as well.
    /// In v1 result is always in 18 decimals, here it depends on oracle setup.
    /// @param _siloConfig Market address (silo config address)
    /// @param _borrower account for which calculation are done
    /// @return value of collateral denominated in quote token, decimal depends on oracle setup.
    function calculateCollateralValue(ISiloConfig _siloConfig, address _borrower) external view returns (uint256);

    /// @notice Calculate value of borrowed asset by user
    /// @dev It dynamically adds interest earned to borrowed amount
    /// In v1 result is always in 18 decimals, here it depends on oracle setup.
    /// @param _siloConfig Market address (silo config address)
    /// @param _borrower account for which calculation are done
    /// @return value of debt denominated in quote token, decimal depends on oracle setup.
    function calculateBorrowValue(ISiloConfig _siloConfig, address _borrower) external view returns (uint256);

    /// @notice Calculates fraction between borrowed amount and the current liquidity of tokens for given asset
    /// denominated in percentage
    /// @dev [v1 NOT compatible] Utilization is calculated current values in storage so it does not take for account
    /// earned interest and ever-increasing total borrow amount. It assumes `Model.DP()` = 100%.
    /// @param _silo Silo address from which to read data
    /// @return utilization value
    function getUtilization(ISilo _silo) external view returns (uint256);

    /// @notice Retrieves the interest rate model
    /// @param _silo Address of the silo
    /// @return irm InterestRateModel contract address
    function getInterestRateModel(ISilo _silo) external view returns (address irm);

    /// @notice Calculates current borrow interest rate
    /// @param _silo Address of the silo
    /// @return borrowAPR The interest rate value in 18 decimals points. 10**18 is equal to 100% per year
    function getBorrowAPR(ISilo _silo) external view returns (uint256 borrowAPR);

    /// @notice Calculates current deposit interest rate.
    /// @param _silo Address of the silo
    /// @return depositAPR The interest rate value in 18 decimals points. 10**18 is equal to 100% per year.
    function getDepositAPR(ISilo _silo) external view returns (uint256 depositAPR);

    /// @notice Calculates current deposit and borrow interest rates (bulk method).
    /// @param _silos Addresses of the silos
    /// @return aprs The interest rate values in 18 decimals points. 10**18 is equal to 100% per year.
    function getAPRs(ISilo[] calldata _silos) external view returns (APR[] memory aprs);

    /// @dev gets interest rates model object
    /// @param _silo Silo address from which to read data
    /// @return IInterestRateModel interest rates model object
    function getModel(ISilo _silo) external view returns (IInterestRateModel);

    /// @notice Get names of all programs in Silo incentives controller
    /// @param _siloIncentivesController Address of the Silo incentives controller
    /// @return programsNames Names of all programs in Silo incentives controller
    function getSiloIncentivesControllerProgramsNames(
        address _siloIncentivesController
    ) external view returns (string[] memory programsNames);

    /// @notice Returns oracle addresses for silo
    function getOracleAddresses(ISilo _silo) external view returns (address solvencyOracle, address maxLtvOracle);
}
