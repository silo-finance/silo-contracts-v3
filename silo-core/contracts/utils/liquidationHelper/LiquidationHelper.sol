// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Address} from "openzeppelin5/utils/Address.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";

import {IERC3156FlashBorrower} from "../../interfaces/IERC3156FlashBorrower.sol";
import {ILiquidationHelper} from "../../interfaces/ILiquidationHelper.sol";

import {ISilo} from "../../interfaces/ISilo.sol";
import {IWrappedNativeToken} from "../../interfaces/IWrappedNativeToken.sol";
import {IPartialLiquidation} from "../../interfaces/IPartialLiquidation.sol";
import {ISiloConfig} from "../../interfaces/ISiloConfig.sol";
import {IShareToken} from "../../interfaces/IShareToken.sol";
import {IHookReceiver} from "../../interfaces/IHookReceiver.sol";

import {DexSwap} from "./DexSwap.sol";
import {TokenRescuer} from "../TokenRescuer.sol";
import {IVersioned} from "../../interfaces/IVersioned.sol";
import {AllowMeToLiquidate} from "./common/AllowMeToLiquidate.sol";
import {Whitelist} from "../../hooks/_common/Whitelist.sol";

/// @notice LiquidationHelper IS NOT PART OF THE PROTOCOL.
contract LiquidationHelper is
    ILiquidationHelper,
    IERC3156FlashBorrower,
    DexSwap,
    TokenRescuer,
    AllowMeToLiquidate,
    Whitelist,
    IVersioned
{
    using Address for address payable;
    using SafeERC20 for IERC20;

    // solhint-disable-next-line var-name-mixedcase
    bytes32 internal constant _FLASHLOAN_CALLBACK = keccak256("ERC3156FlashBorrower.onFlashLoan");

    /// @dev token receiver will get all rewards from liquidation, does not matter who will execute tx
    address payable public immutable TOKENS_RECEIVER;

    /// @dev address of wrapped native blockchain token eg. WETH on Ethereum
    address public immutable NATIVE_TOKEN;

    uint256 private transient _withdrawCollateral;
    uint256 private transient _repayDebtAssets;

    /// @dev Set in `executeLiquidation` to the flash-loan provider; cleared at the start of `onFlashLoan`.
    address private transient _expectedFlashLoanProvider;

    error NoDebtToCover();
    error STokenNotSupported();
    error ZeroAddress();
    error UnauthorizedFlashLoanCallback();

    /// @param _nativeToken address of wrapped native blockchain token eg. WETH on Ethereum
    /// @param _exchangeProxy exchange address, where to send swap data on liquidation
    /// @param _tokensReceiver all leftover tokens (debt and collateral) will be send to this address after liquidation
    constructor(
        address _nativeToken,
        address _exchangeProxy,
        address payable _tokensReceiver
    ) DexSwap(_exchangeProxy) {
        require(_nativeToken != address(0), ZeroAddress());
        require(_exchangeProxy != address(0), ZeroAddress());
        require(address(_tokensReceiver) != address(0), ZeroAddress());

        NATIVE_TOKEN = _nativeToken;
        EXCHANGE_PROXY = _exchangeProxy;
        TOKENS_RECEIVER = _tokensReceiver;

        __Whitelist_init(msg.sender);
    }

    receive() external payable {}

    /// @dev open method to rescue tokens, tokens will be transferred to `TOKENS_RECEIVER`
    function rescueTokens(IERC20 _token) external virtual {
        _rescueTokens(TOKENS_RECEIVER, _token);
    }

    /// @inheritdoc ILiquidationHelper
    /// @dev entry point for liquidation
    /// @notice for now we does not support liquidation with sTokens.
    /// On not profitable liquidation we will revert, because we will not be able to repay flashloan with fee
    /// (collateral will not be enough to cover loan + fee)
    function executeLiquidation(
        ISilo _flashLoanFrom,
        address _debtAsset,
        uint256 _maxDebtToCover,
        LiquidationData calldata _liquidation,
        DexSwapInput[] calldata _swapsInputs0x
    ) external virtual onlyAllowed returns (uint256 withdrawCollateral, uint256 repayDebtAssets) {
        require(_maxDebtToCover != 0, NoDebtToCover());

        _expectedFlashLoanProvider = address(_flashLoanFrom);

        _flashLoanFrom.flashLoan({
            _receiver: this,
            _token: _debtAsset,
            _amount: _maxDebtToCover,
            _data: abi.encode(_liquidation, _swapsInputs0x)
        });
        IERC20(_debtAsset).forceApprove({spender: address(_flashLoanFrom), value: 0});

        withdrawCollateral = _withdrawCollateral;
        repayDebtAssets = _repayDebtAssets;
    }

    /// @inheritdoc IERC3156FlashBorrower
    function onFlashLoan(
        address /* _initiator */,
        address _debtAsset,
        uint256 _maxDebtToCover,
        uint256 _fee,
        bytes calldata _data
    )
        external
        virtual
        returns (bytes32)
    {
        require(msg.sender == _expectedFlashLoanProvider, UnauthorizedFlashLoanCallback());
        _expectedFlashLoanProvider = address(0);

        (
            LiquidationData memory _liquidation,
            DexSwapInput[] memory _swapInputs
        ) = abi.decode(_data, (LiquidationData, DexSwapInput[]));

        IERC20(_debtAsset).forceApprove({spender: address(_liquidation.hook), value: _maxDebtToCover});

        (
            address collateralShareToken, address protectedShareToken
        ) = _turnOnLiquidation({_hook: _liquidation.hook, _user: _liquidation.user});

        (
            _withdrawCollateral, _repayDebtAssets
        ) = _liquidation.hook.liquidationCall({
            _collateralAsset: _liquidation.collateralAsset,
            _debtAsset: _debtAsset,
            _user: _liquidation.user,
            _maxDebtToCover: _maxDebtToCover,
            _receiveSToken: false
        });

        _turnOffLiquidation({
            _hook: _liquidation.hook, 
            _collateralShareToken: collateralShareToken, 
            _protectedShareToken: protectedShareToken
        });

        IERC20(_debtAsset).forceApprove({spender: address(_liquidation.hook), value: 0});
        uint256 flashLoanWithFee = _maxDebtToCover + _fee;

        if (_liquidation.collateralAsset == _debtAsset) {
            uint256 balance = IERC20(_liquidation.collateralAsset).balanceOf(address(this));
            require(flashLoanWithFee <= balance, UnableToRepayFlashloan());

            // bad debt is not supported, we will get underflow on bad debt
            _transferToReceiver({
                _asset: _liquidation.collateralAsset,
                _amount: balance - flashLoanWithFee
            });
        } else {
            // swap all collateral for debt
            // most likely there will be dust left in collateral tokens, this dust will be "recovered"
            // once we will liquidate "oposite" position
            _executeSwap(_swapInputs);

            uint256 debtBalance = IERC20(_debtAsset).balanceOf(address(this));

            if (flashLoanWithFee < debtBalance) {
                unchecked {
                    // safe because of `if (flashLoanWithFee < debtBalance)`
                    _transferToReceiver({_asset: _debtAsset, _amount: debtBalance - flashLoanWithFee});
                }
            } else if (flashLoanWithFee != debtBalance) {
                revert UnableToRepayFlashloan();
            }
        }

        IERC20(_debtAsset).forceApprove({spender: msg.sender, value: flashLoanWithFee});
        return _FLASHLOAN_CALLBACK;
    }

    function VERSION() external pure virtual returns (string memory) { // solhint-disable-line func-name-mixedcase
        return "LiquidationHelper 4.25.0";
    }

    function _executeSwap(DexSwapInput[] memory _swapInputs) internal virtual {
        for (uint256 i; i < _swapInputs.length; i++) {
            fillQuote({
                _sellToken: _swapInputs[i].sellToken,
                _spender: _swapInputs[i].allowanceTarget,
                _swapCallData: _swapInputs[i].swapCallData
            });
        }
    }

    function _transferToReceiver(address _asset, uint256 _amount) internal virtual {
        if (_amount == 0) return;

        if (_asset == NATIVE_TOKEN) {
            _transferNative(_amount);
        } else {
            IERC20(_asset).safeTransfer({to: TOKENS_RECEIVER, value: _amount});
        }
    }

    /// @notice We assume that quoteToken is wrapped native token
    function _transferNative(uint256 _amount) internal virtual {
        IWrappedNativeToken(address(NATIVE_TOKEN)).withdraw(_amount);
        TOKENS_RECEIVER.sendValue(_amount);
    }

    function _turnOnLiquidation(IPartialLiquidation _hook, address _user) 
        internal 
        virtual
        returns(address collateralShareToken, address protectedShareToken) 
    {
        (ISiloConfig.ConfigData memory collateralConfig,) =
            IHookReceiver(address(_hook)).siloConfig().getConfigsForSolvency(_user);

        collateralShareToken = collateralConfig.collateralShareToken;
        protectedShareToken = collateralConfig.protectedShareToken;

        _allowMeToLiquidate({
            _hookReceiver: address(_hook),
            _shareToken: IShareToken(collateralConfig.collateralShareToken)
        });

        _allowMeToLiquidate({
            _hookReceiver: address(_hook),
            _shareToken: IShareToken(collateralConfig.protectedShareToken)
        });
    }

    function _turnOffLiquidation(IPartialLiquidation _hook, address _collateralShareToken, address _protectedShareToken) 
        internal 
        virtual
    {
        _disallowLiquidation({
            _hookReceiver: address(_hook),
            _shareToken: IShareToken(_collateralShareToken)
        });

        _disallowLiquidation({
            _hookReceiver: address(_hook),
            _shareToken: IShareToken(_protectedShareToken)
        });
    }
}
