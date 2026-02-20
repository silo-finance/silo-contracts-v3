// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

// solhint-disable ordering

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {IERC20Permit} from "openzeppelin5/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";

import {ISilo} from "../interfaces/ISilo.sol";
import {ILeverageUsingSiloFlashloan} from "../interfaces/ILeverageUsingSiloFlashloan.sol";
import {IERC3156FlashBorrower} from "../interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "../interfaces/IERC3156FlashLender.sol";
import {IWrappedNativeToken} from "../interfaces/IWrappedNativeToken.sol";

import {RescueModule} from "./modules/RescueModule.sol";
import {LeverageTxState} from "./modules/LeverageTxState.sol";

/*
    @title Contract with leverage logic
    @notice What does leverage means?

    You are using a Silo lending protocol that allows you to supply collateral and borrow against it.

    Collateral asset: ETH (price = $1,000)
    Debt asset: USDC (stablecoin = $1)

    Step-by-step to reach 2x leverage:

    Start with $1,000 worth of ETH.
    Leverage contract will flashloan $1,000 USDC. Flashloaned USDC will be swapped into 1 ETH.
    Contract will deposit 2 ETH as collateral and borrow 1000 USDC on your behalf against your ETH to repay flashloan.

    Now you hold 2 ETH total exposure

    - 1 ETH from your original deposit
    - 1 ETH bought using flashloan funds

    Your total ETH exposure is $2,000, but your own money is $1,000.

    So, your leverage is: Leverage = Total Exposure / Your Own Capital = 2000 / 1000 = 2.0𝑥

    RISK: If ETH price drops, your position can be liquidated.
*/
abstract contract LeverageUsingSiloFlashloan is
    ILeverageUsingSiloFlashloan,
    IERC3156FlashBorrower,
    RescueModule,
    LeverageTxState
{
    using SafeERC20 for IERC20;

    IWrappedNativeToken public immutable NATIVE_TOKEN;

    bytes32 internal constant _FLASHLOAN_CALLBACK = keccak256("ERC3156FlashBorrower.onFlashLoan");

    constructor(address _native) {
        require(_native != address(0), EmptyNativeToken());

        NATIVE_TOKEN = IWrappedNativeToken(_native);
    }

    /// @inheritdoc ILeverageUsingSiloFlashloan
    function openLeveragePositionPermit(
        address _msgSender,
        FlashArgs calldata _flashArgs,
        bytes calldata _swapArgs,
        DepositArgs calldata _depositArgs,
        Permit calldata _depositAllowance
    )
        external
        virtual
    {
        _executePermit(_msgSender, _depositAllowance, _depositArgs.silo.asset());

        openLeveragePosition(_msgSender, _flashArgs, _swapArgs, _depositArgs);
    }

    /// @inheritdoc ILeverageUsingSiloFlashloan
    function openLeveragePosition(
        address _msgSender,
        FlashArgs calldata _flashArgs,
        bytes calldata _swapArgs,
        DepositArgs calldata _depositArgs
    )
        public
        payable
        virtual
        onlyRouter
        nonReentrant
        setupTxState(_msgSender, _depositArgs.silo, LeverageAction.Open, _flashArgs.flashloanTarget)
    {
        _txMsgValue = msg.value;

        require(IERC3156FlashLender(_flashArgs.flashloanTarget).flashLoan({
            _receiver: this,
            _token: ISilo(_flashArgs.flashloanTarget).asset(),
            _amount: _flashArgs.amount,
            _data: abi.encode(_swapArgs, _depositArgs)
        }), FlashloanFailed());
    }

    /// @inheritdoc ILeverageUsingSiloFlashloan
    function closeLeveragePositionPermit(
        address _msgSender,
        bytes calldata _swapArgs,
        CloseLeverageArgs calldata _closeArgs,
        Permit calldata _withdrawAllowance
    )
        external
        virtual
    {
        address shareTokenToApprove = address(_closeArgs.siloWithCollateral);
        
        if (_closeArgs.collateralType == ISilo.CollateralType.Protected) {
            (
                shareTokenToApprove,,
            ) = _closeArgs.siloWithCollateral.config().getShareTokens(address(_closeArgs.siloWithCollateral));
        }

        _executePermit(_msgSender, _withdrawAllowance, shareTokenToApprove);

        closeLeveragePosition(_msgSender, _swapArgs, _closeArgs);
    }

    /// @inheritdoc ILeverageUsingSiloFlashloan
    function closeLeveragePosition(
        address _msgSender,
        bytes calldata _swapArgs,
        CloseLeverageArgs calldata _closeArgs
    )
        public
        virtual
        onlyRouter
        nonReentrant
        setupTxState(_msgSender, _closeArgs.siloWithCollateral, LeverageAction.Close, _closeArgs.flashloanTarget)
    {
        require(IERC3156FlashLender(_closeArgs.flashloanTarget).flashLoan({
            _receiver: this,
            _token: ISilo(_closeArgs.flashloanTarget).asset(),
            _amount: _resolveOtherSilo(_closeArgs.siloWithCollateral).maxRepay(_msgSender),
            _data: abi.encode(_swapArgs, _closeArgs)
        }), FlashloanFailed());
    }

    /// @inheritdoc IERC3156FlashBorrower
    function onFlashLoan(
        address /* _initiator */,
        address _borrowToken,
        uint256 _flashloanAmount,
        uint256 _flashloanFee,
        bytes calldata _data
    )
        external
        returns (bytes32)
    {
        // this check prevents call `onFlashLoan` directly
        require(_txFlashloanTarget == msg.sender, InvalidFlashloanLender());

        if (_txAction == LeverageAction.Open) {
            _openLeverage(_flashloanAmount, _flashloanFee, _data);
        } else if (_txAction == LeverageAction.Close) {
            _closeLeverage(_borrowToken, _flashloanAmount, _flashloanFee, _data);
        } else revert UnknownAction();

        // approval for repay flashloan
        IERC20(_borrowToken).forceApprove(_txFlashloanTarget, _flashloanAmount + _flashloanFee);

        // by resetting `_txFlashloanTarget` we basically making this method nonReentrant
        _txFlashloanTarget = address(0);
        return _FLASHLOAN_CALLBACK;
    }

    // solhint-disable-next-line function-max-lines
    function _openLeverage(
        uint256 _flashloanAmount,
        uint256 _flashloanFee,
        bytes calldata _data
    )
        internal
    {
        DepositArgs memory depositArgs;
        uint256 collateralAmountAfterSwap;

        {
            bytes memory swapArgs;

            (swapArgs, depositArgs) = abi.decode(_data, (bytes, DepositArgs));

            // swap all flashloan (debt token) amount into collateral token
            collateralAmountAfterSwap = _fillQuote(swapArgs, _flashloanAmount);
        }

        uint256 totalDeposit = depositArgs.amount + collateralAmountAfterSwap;

        // Fee is taken on totalDeposit = user deposit amount + collateral amount after swap
        uint256 feeForLeverage = ROUTER.calculateLeverageFee(totalDeposit);

        totalDeposit -= feeForLeverage;

        address collateralAsset = depositArgs.silo.asset();

        _deposit({_depositArgs: depositArgs, _totalDeposit: totalDeposit, _asset: collateralAsset});

        {
            ISilo borrowSilo = _resolveOtherSilo(depositArgs.silo);

            // borrow asset wil be used to repay flashloan with fee
            borrowSilo.borrow({
                _assets: _flashloanAmount + _flashloanFee,
                _receiver: address(this),
                _borrower: _txMsgSender
            });
        }

        emit OpenLeverage({
            borrower: _txMsgSender,
            borrowerDeposit: depositArgs.amount,
            swapAmountOut: collateralAmountAfterSwap,
            flashloanAmount: _flashloanAmount,
            totalDeposit: totalDeposit,
            totalBorrow: _flashloanAmount + _flashloanFee,
            leverageFee: feeForLeverage,
            flashloanFee: _flashloanFee
        });

        _payLeverageFee(collateralAsset, feeForLeverage);
    }

    function _deposit(DepositArgs memory _depositArgs, uint256 _totalDeposit, address _asset) internal virtual {
        _transferTokensFromUser(_asset, _depositArgs.amount);

        IERC20(_asset).forceApprove(address(_depositArgs.silo), _totalDeposit);

        _depositArgs.silo.deposit({
            _assets: _totalDeposit,
            _receiver: _txMsgSender,
            _collateralType: _depositArgs.collateralType
        });
    }
    
    function _closeLeverage(
        address _debtToken,
        uint256 _flashloanAmount,
        uint256 _flashloanFee,
        bytes calldata _data
    )
        internal
    {
        (
            bytes memory swapArgs,
            CloseLeverageArgs memory closeArgs
        ) = abi.decode(_data, (bytes, CloseLeverageArgs));

        ISilo siloWithDebt = _resolveOtherSilo(closeArgs.siloWithCollateral);

        IERC20(_debtToken).forceApprove(address(siloWithDebt), _flashloanAmount);

        siloWithDebt.repayShares(_getBorrowerTotalShareDebtBalance(siloWithDebt), _txMsgSender);

        uint256 sharesToRedeem = _getBorrowerTotalShareCollateralBalance(closeArgs);

        // withdraw all collateral
        uint256 withdrawnDeposit = closeArgs.siloWithCollateral.redeem({
            _shares: sharesToRedeem,
            _receiver: address(this),
            _owner: _txMsgSender,
            _collateralType: closeArgs.collateralType
        });

        // swap collateral to debt to repay flashloan
        uint256 availableDebtAssets = _fillQuote(swapArgs, withdrawnDeposit);

        uint256 obligation = _flashloanAmount + _flashloanFee;
        require(availableDebtAssets >= obligation, SwapDidNotCoverObligations());

        uint256 borrowerDebtChange = availableDebtAssets - obligation;

        emit CloseLeverage({
            borrower: _txMsgSender,
            flashloanAmount: _flashloanAmount,
            flashloanFee: _flashloanFee,
            swapAmountOut: availableDebtAssets,
            depositWithdrawn: withdrawnDeposit
        });

        if (borrowerDebtChange != 0) IERC20(_debtToken).safeTransfer(_txMsgSender, borrowerDebtChange);

        IERC20 collateralAsset = IERC20(closeArgs.siloWithCollateral.asset());
        uint256 collateralToTransfer = collateralAsset.balanceOf(address(this));
        if (collateralToTransfer != 0) collateralAsset.safeTransfer(_txMsgSender, collateralToTransfer);
    }

    function _fillQuote(bytes memory _swapArgs, uint256 _maxApprovalAmount)
        internal
        virtual
        returns (uint256 amountOut);

    function _getBorrowerTotalShareDebtBalance(ISilo _siloWithDebt)
        internal
        view
        virtual
        returns (uint256 repayShareBalance)
    {
        (,, address shareDebtToken) = _txSiloConfig.getShareTokens(address(_siloWithDebt));
        repayShareBalance = IERC20(shareDebtToken).balanceOf(_txMsgSender);
    }

    function _getBorrowerTotalShareCollateralBalance(CloseLeverageArgs memory _closeArgs)
        internal
        view
        virtual
        returns (uint256 balanceOf)
    {
        if (_closeArgs.collateralType == ISilo.CollateralType.Collateral) {
            return _closeArgs.siloWithCollateral.balanceOf(_txMsgSender);
        }

        (address protectedShareToken,,) = _txSiloConfig.getShareTokens(address(_closeArgs.siloWithCollateral));

        balanceOf = ISilo(protectedShareToken).balanceOf(_txMsgSender);
    }

    function _resolveOtherSilo(ISilo _thisSilo) internal view returns (ISilo otherSilo) {
        (address silo0, address silo1) = _txSiloConfig.getSilos();
        require(address(_thisSilo) == silo0 || address(_thisSilo) == silo1, InvalidSilo());

        otherSilo = ISilo(silo0 == address(_thisSilo) ? silo1 : silo0);
    }

    function _executePermit(address _msgSender, Permit memory _permit, address _token) internal virtual {
        if (_permit.deadline == 0) return;

        try IERC20Permit(_token).permit({
            owner: _msgSender,
            spender: address(this),
            value: _permit.value,
            deadline: _permit.deadline,
            v: _permit.v,
            r: _permit.r,
            s: _permit.s
        }) {
            // execution successful
        } catch {
            // on fail we still want to try, in case permit was executed by frontrun
        }
    }

    function _transferTokensFromUser(address _asset, uint256 _expectedValue) internal {
        if (_txMsgValue == 0) {
            // transfer collateral tokens from borrower
            IERC20(_asset).safeTransferFrom(_txMsgSender, address(this), _expectedValue);
        } else {
            require(_txMsgValue == _expectedValue, IncorrectNativeTokenAmount());

            NATIVE_TOKEN.deposit{value: _txMsgValue}();
            _txMsgValue = 0;
        }
    }

    function _payLeverageFee(address _token, uint256 _leverageFee) internal virtual {
        if (_leverageFee != 0) IERC20(_token).safeTransfer(ROUTER.revenueReceiver(), _leverageFee);
    }
}
