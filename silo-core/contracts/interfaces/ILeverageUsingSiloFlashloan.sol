// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ISilo} from "./ISilo.sol";
import {IGeneralSwapModule} from "./IGeneralSwapModule.sol";

/// @title LeverageUsingSiloFlashloan Interface
/// @notice Interface for a contract that enables leveraged deposits using flash loans from silo
/// and token swaps with 0x os compatible interface
interface ILeverageUsingSiloFlashloan {
    enum LeverageAction {
        Undefined,
        Open,
        Close
    }

    /// @notice Parameters for a flash loan
    /// @param flashloanTarget The address of the contract providing the flash loan.
    /// For opening position it should be equal to swap amount in.
    /// @param amount The amount of tokens to borrow
    struct FlashArgs {
        address flashloanTarget;
        uint256 amount;
    }

    /// @notice Parameters for deposit after leverage
    /// @param silo Target Silo for depositing
    /// @param amount Raw deposit amount (excluding flashloan)
    /// @param collateralType The type of collateral to use
    struct DepositArgs {
        ISilo silo;
        uint256 amount;
        ISilo.CollateralType collateralType;
    }

    /// @param flashloanTarget The address of the contract providing the flash loan, it must have enough liquidity
    /// to cover borrower debt
    /// @param siloWithCollateral address of silo with collateral, the other silo is expected to have debt
    /// @param collateralType The type of collateral to use
    struct CloseLeverageArgs {
        address flashloanTarget;
        ISilo siloWithCollateral;
        ISilo.CollateralType collateralType;
    }

    /// @dev owner argument in signature should be msg.sender, spender should be leverage contract
    struct Permit {
        uint256 value;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    event OpenLeverage(
        address indexed borrower,
        uint256 borrowerDeposit,
        uint256 swapAmountOut,
        uint256 flashloanAmount,
        uint256 totalDeposit,
        uint256 totalBorrow,
        uint256 leverageFee,
        uint256 flashloanFee
    );

    event CloseLeverage(
        address indexed borrower,
        uint256 flashloanAmount,
        uint256 flashloanFee,
        uint256 swapAmountOut,
        uint256 depositWithdrawn
    );

    error EmptyNativeToken();
    error IncorrectNativeTokenAmount();
    error FlashloanFailed();
    error InvalidFlashloanLender();
    error InvalidInitiator();
    error UnknownAction();
    error SwapDidNotCoverObligations();
    error InvalidSilo();

    /// @notice Performs leverage operation using a flash loan and token swap. Does not support fee on transfer tokens.
    /// It also does not support borrow on same asset.
    /// @dev Reverts if the amount is so high that fee calculation fails
    /// This method requires approval for transfer collateral from borrower to leverage contract and to create
    /// debt position. Approval for collateral can be done using Permit (if asset supports it), for that case please
    /// use `openLeveragePositionPermit`
    /// @param _msgSender The address of the sender (provided by the leverage router)
    /// @param _flashArgs Flash loan configuration
    /// @param _swapArgs Swap call data and settings, that will swap all flashloan amount into collateral
    /// @param _depositArgs Final deposit configuration into a Silo
    function openLeveragePosition(
        address _msgSender,
        FlashArgs calldata _flashArgs,
        bytes calldata _swapArgs,
        DepositArgs calldata _depositArgs
    ) external payable;

    /// @notice Performs leverage operation using a flash loan and token swap. Does not support fee on transfer tokens.
    /// It also does not support borrow on same asset.
    /// @dev Reverts if the amount is so high that fee calculation fails
    /// @param _msgSender The address of the sender (provided by the leverage router)
    /// @param _flashArgs Flash loan configuration
    /// @param _swapArgs Swap call data and settings, that will swap all flashloan amount into collateral
    /// @param _depositArgs Final deposit configuration into a Silo
    /// @param _depositAllowance Permit for leverage contract to transfer collateral from borrower
    function openLeveragePositionPermit(
        address _msgSender,
        FlashArgs calldata _flashArgs,
        bytes calldata _swapArgs,
        DepositArgs calldata _depositArgs,
        Permit calldata _depositAllowance
    ) external;

    /// @notice Closes opened leveraged position.
    /// Does not support fee on transfer tokens. It also does not support borrow on same asset.
    /// @dev This method requires approval for withdraw all collateral (so minimal requires amount for allowance is
    /// borrower balance). Approval can be done using Permit, for that case please use `closeLeveragePositionPermit`
    /// @param _msgSender The address of the sender (provided by the leverage router)
    /// @param _swapArgs Swap call data and settings, it should swap enough collateral to repay flashloan in debt token
    /// @param _closeLeverageArgs configuration for closing position
    function closeLeveragePosition(
        address _msgSender,
        bytes calldata _swapArgs,
        CloseLeverageArgs calldata _closeLeverageArgs
    ) external;

    /// @notice Closes opened leveraged position.
    /// Does not support fee on transfer tokens. It also does not support borrow on same asset.
    /// @dev This method requires approval for withdraw all collateral (so minimal requires amount for allowance is
    /// borrower balance). Approval is done using Permit
    /// @param _msgSender The address of the sender (provided by the leverage router)
    /// @param _swapArgs Swap call data and settings, it should swap enough collateral to repay flashloan in debt token
    /// @param _closeLeverageArgs configuration for closing position
    /// @param _withdrawAllowance Permit for leverage contract to withdraw all borrower collateral or protected tokens
    function closeLeveragePositionPermit(
        address _msgSender,
        bytes calldata _swapArgs,
        CloseLeverageArgs calldata _closeLeverageArgs,
        Permit calldata _withdrawAllowance
    ) external;

    // solhint-disable-next-line func-name-mixedcase
    function SWAP_MODULE() external view returns (IGeneralSwapModule);
}
