// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title PostconditionsSpec
/// @notice Postcoditions specification for the protocol
/// @dev Contains pseudo code and description for the postcondition properties in the protocol
abstract contract PostconditionsSpec {
    /*/////////////////////////////////////////////////////////////////////////////////////////////
    //                                      PROPERTY TYPES                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// - POSTCONDITIONS:
    ///   - Properties that should hold true after an action is executed.
    ///   - Implemented in the /hooks and /handlers folders.

    ///   - There are two types of POSTCONDITIONS:

    ///     - GLOBAL POSTCONDITIONS (GPOST): 
    ///       - Properties that should always hold true after any action is executed.
    ///       - Checked in the `_checkPostConditions` function within the HookAggregator contract.

    ///     - HANDLER-SPECIFIC POSTCONDITIONS (HSPOST): 
    ///       - Properties that should hold true after a specific action is executed in a specific context.
    ///       - Implemented within each handler function, under the HANDLER-SPECIFIC POSTCONDITIONS section.

    /////////////////////////////////////////////////////////////////////////////////////////////*/

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          BASE                                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice related to silo property UT_Silo_accrueInterest
    string constant BASE_GPOST_A =
        "BASE_GPOST_A: accrueInterest can only be executed on deposit, mint, withdraw, redeem, liquidationCall, accrueInterest, leverage, repay, repayShares.";

    /// @notice related to silo property ST_Silo_interestRateTimestamp_totalBorrowAmount_dependency
    string constant BASE_GPOST_B =
        "BASE_GPOST_B: interestRateTimestampBefore != 0 and changed and Silo.totalAssets[ISilo.AssetType.Debt] != 0 => Silo.totalAssets[ISilo.AssetType.Debt] increased";

    /// @notice related to silo property ST_Silo_interestRateTimestamp_totalBorrowAmount_dependency
    string constant BASE_GPOST_C =
        "BASE_GPOST_C: _siloData.interestRateTimestamp != 0 and changed and Silo.totalAssets[ISilo.AssetType.Debt] != 0 and dao and deployerFee set => _siloData.daoAndDeployerFees increased.";

    string constant BASE_GPOST_D = "BASE_GPOST_D: Set of functions that won't operate when user is not solvent";

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       SILO MARKET                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    string constant SILO_HSPOST_A =
        "SILO_HSPOST_A: accrueInterest() should never decrease total collateral and total debt";

    string constant SILO_HSPOST_B =
        "SILO_HSPOST_B: impossible to mint 0 shares or burn 0 shares or transfer 0 assets inside any function in Silo";

    string constant SILO_GPOST_C =
        "SILO_GPOST_C: withdraw()/redeem()/borrow()/borrowShares() should always call accrueInterest() on both Silos"; // TODO

    string constant SILO_HSPOST_D = "SILO_GPOST_D: withdrawFees() always reverts in a second call in the same block";

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          LENDING                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice related to silo property HLP_integrity_deposit_collateral_no_interest
    string constant LENDING_HSPOST_A =
        "LENDING_HSPOST_A: after deposit, silo.totalAssets[ISilo.AssetType.Collateral] increases by amount deposited";

    /// @notice related to silo property HLP_integrity_deposit_collateral_no_interest
    string constant LENDING_HSPOST_B = "LENDING_HSPOST_B: after mint, silo.totalSupply increases by amount minted";

    /// @notice related to silo property RA_Silo_withdraw_all_shares
    string constant LENDING_HSPOST_C =
        "LENDING_HSPOST_C: A user can withdraw all with max shares amount and not be able to withdraw more."; // TODO

    /// @notice related to silo property RA_silo_transition_collateral_liquidity
    string constant LENDING_HSPOST_D =
        "LENDING_HSPOST_D: User can transition only available liquidity to protected collateral.";

    /// @notice related to silo property RA_silo_borrow_withdraw_getLiquidity
    string constant LENDING_GPOST_E =
        "LENDING_GPOST_E: User is always able to borrow/withdraw amount returned by 'getLiquidity' fn."; // TODO

    string constant LENDING_GPOST_F =
        "LENDING_GPOST_F: A user should always be able to withdraw all if there is no outstanding debt"; // TODO

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          BORROWING                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice related to silo property HLP_integrity_borrow_debt_no_interest
    string constant BORROWING_HSPOST_A =
        "BORROWING_HSPOST_A: after borrow, silo.totalAssets[ISilo.AssetType.Debt] increases by amount borrowed";

    /// @notice related to silo property RA_Silo_repay_all_shares,
    string constant BORROWING_HSPOST_B =
        "BORROWING_HSPOST_B: A user has no debt after being repaid with max shares amount";

    /// @notice related to silo properties RA_silo_solvent_after_borrow & RA_silo_solvent_after_repaying
    string constant BORROWING_GPOST_C = "BORROWING_GPOST_C: No action except liquidations can leave a user unhealthy.";

    string constant BORROWING_HSPOST_D = "BORROWING_HSPOST_D: a user can always repay debt in full (+-1wei)";

    string constant BORROWING_HSPOST_E = "BORROWING_HSPOST_E: Not solvent users can not borrow"; // Included in BASE_GPOST_D

    string constant BORROWING_HSPOST_F = "BORROWING_HSPOST_F: User borrowing maxBorrow should never revert";

    string constant BORROWING_HSPOST_G = "BORROWING_HSPOST_G: User cant't over repay";

    string constant BORROWING_HSPOST_H = "BORROWING_HSPOST_H: Repay should decrease the debt";

    string constant BORROWING_HSPOST_I = "BORROWING_HSPOST_I: User liability should always decrease after repayment"; // TODO

    string constant BORROWING_HSPOST_J = "BORROWING_HSPOST_J: TransitionCollateral should not increase users assets";

    string constant BORROWING_HSPOST_K =
        "BORROWING_HSPOST_K: TransitionCollateral should not decrease user assets by more than 1-2 wei";

    string constant BORROWING_HSPOST_L =
        "BORROWING_HSPOST_L: If user is solvent transitionCollateral() for _transitionFrom == CollateralType.Protected should never revert";

    string constant BORROWING_HSPOST_M = "BORROWING_HSPOST_M: borrow should increase debtAssets by exactly _assets";

    string constant BORROWING_HSPOST_O = "BORROWING_HSPOST_O: borrow should decrease Silo balance by exactly _assets";

    string constant BORROWING_HSPOST_P =
        "BORROWING_HSPOST_P: User should always have ltv below maxLTV after successful call to borrow()"; // TODO

    string constant BORROWING_HSPOST_Q =
        "BORROWING_HSPOST_Q: borrowShares should always increase debt shares of the borrower";

    string constant BORROWING_HSPOST_R =
        "BORROWING_HSPOST_R: borrowShares should always increase balance of the receiver";

    string constant BORROWING_HSPOST_S =
        "BORROWING_HSPOST_S: For users that can repay, calling repay() with maxRepay() result should never revert";

    string constant BORROWING_HSPOST_T =
        "BORROWING_HSPOST_T: After a successful flashloan the balance of the Silo should have increased by the premium fee";

    string constant BORROWING_HSPOST_U1 =
        "BORROWING_HSPOST_U1: A flashloan succeeds if theres enough balance (amount + fee) transferred back to the protocol";

    string constant BORROWING_HSPOST_U2 =
        "BORROWING_HSPOST_U2: A flashloan fails if theres not enough balance (amount + fee) transferred back to the protocol";

    string constant BORROWING_HSPOST_U3 =
        "BORROWING_HSPOST_U: The protocol should invoke the flash loan receiver, passing the actor as the initiator";

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          LIQUIDATION                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice related to silo property HLP_silo_anyone_can_liquidate_insolvent
    string constant LIQUIDATION_GPOST_A = "LIQUIDATION_GPOST_A: Anyone can liquidate insolvent user"; // TODO
}
