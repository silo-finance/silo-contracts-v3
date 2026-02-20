// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.28;

// solhint-disable ordering

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";
import {Address} from "openzeppelin5/utils/Address.sol";
import {Math} from "openzeppelin5/utils/math/Math.sol";

import {ISiloConfig} from "../interfaces/ISiloConfig.sol";
import {ISilo} from "../interfaces/ISilo.sol";
import {IShareToken} from "../interfaces/IShareToken.sol";
import {IERC3156FlashBorrower} from "../interfaces/IERC3156FlashBorrower.sol";
import {IHookReceiver} from "../interfaces/IHookReceiver.sol";

import {SiloERC4626Lib} from "./SiloERC4626Lib.sol";
import {SiloSolvencyLib} from "./SiloSolvencyLib.sol";
import {SiloLendingLib} from "./SiloLendingLib.sol";
import {SiloStdLib} from "./SiloStdLib.sol";
import {Hook} from "./Hook.sol";
import {CallBeforeQuoteLib} from "./CallBeforeQuoteLib.sol";
import {NonReentrantLib} from "./NonReentrantLib.sol";
import {ShareTokenLib} from "./ShareTokenLib.sol";
import {SiloStorageLib} from "./SiloStorageLib.sol";
import {Views} from "./Views.sol";
import {Rounding} from "./Rounding.sol";

library Actions {
    using Address for address;
    using SafeERC20 for IERC20;
    using Hook for uint256;
    using Hook for uint24;
    using CallBeforeQuoteLib for ISiloConfig.ConfigData;

    bytes32 internal constant _FLASHLOAN_CALLBACK = keccak256("ERC3156FlashBorrower.onFlashLoan");

    error FeeOverflow();
    error FlashLoanNotPossible();

    /// @notice Initialize Silo
    /// @param _siloConfig Address of ISiloConfig with full configuration for this Silo
    /// @return hookReceiver Address of the hook receiver for the silo
    function initialize(ISiloConfig _siloConfig) external returns (address hookReceiver) {
        IShareToken.ShareTokenStorage storage _sharedStorage = ShareTokenLib.getShareTokenStorage();

        require(address(_sharedStorage.siloConfig) == address(0), ISilo.SiloInitialized());

        ISiloConfig.ConfigData memory configData = _siloConfig.getConfig(address(this));

        _sharedStorage.siloConfig = _siloConfig;

        return configData.hookReceiver;
    }

    /// @notice Implements IERC4626.deposit for protected (non-borrowable) and borrowable collateral
    /// @dev Reverts for debt asset type
    /// @param _assets Amount of assets to deposit (0 if `_shares` specified)
    /// @param _shares shares expected for the deposit  (0 if `_assets` specified)
    /// @param _receiver Address to receive the deposit shares
    /// @param _collateralType Type of collateral (Protected or Collateral)
    /// @return assets Amount of assets deposited
    /// @return shares Amount of shares minted due to deposit
    function deposit(
        uint256 _assets,
        uint256 _shares,
        address _receiver,
        ISilo.CollateralType _collateralType
    )
        external
        returns (uint256 assets, uint256 shares)
    {
        _hookCallBeforeDeposit(_collateralType, _assets, _shares, _receiver);

        ISiloConfig siloConfig = ShareTokenLib.siloConfig();

        siloConfig.turnOnReentrancyProtection();
        siloConfig.accrueInterestForSilo(address(this));

        (
            address shareToken, address asset
        ) = siloConfig.getCollateralShareTokenAndAsset(address(this), _collateralType);

        (assets, shares) = SiloERC4626Lib.deposit({
            _token: asset,
            _depositor: msg.sender,
            _assets: _assets,
            _shares: _shares,
            _receiver: _receiver,
            _collateralShareToken: IShareToken(shareToken),
            _collateralType: _collateralType
        });

        siloConfig.turnOffReentrancyProtection();

        _hookCallAfterDeposit(_collateralType, _assets, _shares, _receiver, assets, shares);
    }

    /// @notice Implements IERC4626.withdraw for protected (non-borrowable) and borrowable collateral
    /// @dev Reverts for debt asset type
    /// @param _args Contains withdrawal parameters:
    /// - `assets`: Amount of assets to withdraw (0 if `_shares` specified)
    /// - `shares`: Amount of shares burnt for the withdrawal (0 if `_assets` specified)
    /// - `receiver`: Address to receive withdrawn assets
    /// - `owner`: Owner of the assets being withdrawn
    /// - `spender`: Caller executing the withdrawal
    /// - `collateralType`: Specifies whether withdrawal is protected or borrowable collateral
    /// @return assets Amount of assets withdrawn
    /// @return shares Amount of shares burnt during withdrawal
    function withdraw(ISilo.WithdrawArgs calldata _args)
        external
        returns (uint256 assets, uint256 shares)
    {
        _hookCallBeforeWithdraw(_args);

        ISiloConfig siloConfig = ShareTokenLib.siloConfig();

        siloConfig.turnOnReentrancyProtection();
        siloConfig.accrueInterestForBothSilos();

        ISiloConfig.DepositConfig memory depositConfig;
        ISiloConfig.ConfigData memory collateralConfig;
        ISiloConfig.ConfigData memory debtConfig;

        (depositConfig, collateralConfig, debtConfig) = siloConfig.getConfigsForWithdraw(address(this), _args.owner);

        (assets, shares) = SiloERC4626Lib.withdraw(
            depositConfig.token,
            _args.collateralType == ISilo.CollateralType.Collateral
                ? depositConfig.collateralShareToken
                : depositConfig.protectedShareToken,
            _args
        );

        if (depositConfig.silo == collateralConfig.silo) {
            // If deposit is collateral, then check the solvency.
            _checkSolvencyWithoutAccruingInterest(collateralConfig, debtConfig, _args.owner);
        }

        siloConfig.turnOffReentrancyProtection();

        _hookCallAfterWithdraw(_args, assets, shares);
    }

    /// @notice Allows an address to borrow a specified amount of assets
    /// @param _args Contains the borrowing parameters:
    /// - `assets`: Number of assets the borrower intends to borrow (0 if `_shares` specified)
    /// - `shares`: Number of shares corresponding to the assets being borrowed (0 if `_assets` specified)
    /// - `receiver`: Address receiving the borrowed assets
    /// - `borrower`: Address of the borrower
    /// @return assets Amount of assets borrowed
    /// @return shares Amount of shares minted for the borrowed assets
    /// @return collateralTypeChanged TRUE if action changed collateral type
    function borrow(ISilo.BorrowArgs memory _args)
        external
        returns (uint256 assets, uint256 shares, bool collateralTypeChanged)
    {
        _hookCallBeforeBorrow(_args, Hook.BORROW);

        ISiloConfig siloConfig = ShareTokenLib.siloConfig();

        require(!siloConfig.hasDebtInOtherSilo(address(this), _args.borrower), ISilo.BorrowNotPossible());

        siloConfig.turnOnReentrancyProtection();
        siloConfig.accrueInterestForBothSilos();
        collateralTypeChanged = siloConfig.setOtherSiloAsCollateralSilo(_args.borrower);

        ISiloConfig.ConfigData memory collateralConfig;
        ISiloConfig.ConfigData memory debtConfig;

        (collateralConfig, debtConfig) = siloConfig.getConfigsForBorrow({_debtSilo: address(this)});

        (assets, shares) = SiloLendingLib.borrow(
            debtConfig.debtShareToken,
            debtConfig.token,
            msg.sender,
            _args
        );

        _checkLTVWithoutAccruingInterest(collateralConfig, debtConfig, _args.borrower);

        siloConfig.turnOffReentrancyProtection();

        _hookCallAfterBorrow(_args, Hook.BORROW, assets, shares);
    }

    /// @notice Repays a given asset amount and returns the equivalent number of shares
    /// @param _assets Amount of assets to be repaid
    /// @param _borrower Address of the borrower whose debt is being repaid
    /// @param _repayer Address of the repayer who repay debt
    /// @return assets number of assets that had been repay
    /// @return shares number of shares that had been repay
    // solhint-disable-next-line function-max-lines
    function repay(
        uint256 _assets,
        uint256 _shares,
        address _borrower,
        address _repayer
    )
        external
        returns (uint256 assets, uint256 shares)
    {
        IShareToken.ShareTokenStorage storage _shareStorage = ShareTokenLib.getShareTokenStorage();

        if (_shareStorage.hookSetup.hooksBefore.matchAction(Hook.REPAY)) {
            bytes memory data = abi.encodePacked(_assets, _shares, _borrower, _repayer);
            IHookReceiver(_shareStorage.hookSetup.hookReceiver).beforeAction(address(this), Hook.REPAY, data);
        }

        ISiloConfig siloConfig = _shareStorage.siloConfig;

        siloConfig.turnOnReentrancyProtection();
        siloConfig.accrueInterestForSilo(address(this));

        (address debtShareToken, address debtAsset) = siloConfig.getDebtShareTokenAndAsset(address(this));

        (assets, shares) = SiloLendingLib.repay(
            IShareToken(debtShareToken), debtAsset, _assets, _shares, _borrower, _repayer
        );

        siloConfig.turnOffReentrancyProtection();

        if (_shareStorage.hookSetup.hooksAfter.matchAction(Hook.REPAY)) {
            bytes memory data = abi.encodePacked(_assets, _shares, _borrower, _repayer, assets, shares);
            IHookReceiver(_shareStorage.hookSetup.hookReceiver).afterAction(address(this), Hook.REPAY, data);
        }
    }
    /// @notice Transitions assets between collateral (borrowable) and protected (non-borrowable) states
    /// @dev This method allows assets to switch states without leaving the protocol
    /// @param _args Contains the transition parameters:
    /// - `shares`: Amount of shares to transition
    /// - `owner`: Owner of the assets being transitioned
    /// - `transitionFrom`: Specifies whether transitioning from collateral or protected
    /// @return assets Amount of assets transitioned
    /// @return toShares Equivalent shares gained from the transition
    // solhint-disable-next-line function-max-lines
    function transitionCollateral(ISilo.TransitionCollateralArgs memory _args)
        external
        returns (uint256 assets, uint256 toShares)
    {
        _hookCallBeforeTransitionCollateral(_args);

        ISiloConfig siloConfig = ShareTokenLib.siloConfig();

        siloConfig.turnOnReentrancyProtection();
        siloConfig.accrueInterestForBothSilos();

        (
            ISiloConfig.DepositConfig memory depositConfig,
            ISiloConfig.ConfigData memory collateralConfig,
            ISiloConfig.ConfigData memory debtConfig
        ) = siloConfig.getConfigsForWithdraw(address(this), _args.owner);

        uint256 shares;

        // transition collateral withdraw
        address shareTokenFrom = _args.transitionFrom == ISilo.CollateralType.Collateral
            ? depositConfig.collateralShareToken
            : depositConfig.protectedShareToken;

        (assets, shares) = SiloERC4626Lib.withdraw({
            _asset: address(0), // empty token because we don't want to transfer
            _shareToken: shareTokenFrom,
            _args: ISilo.WithdrawArgs({
                assets: 0,
                shares: _args.shares,
                owner: _args.owner,
                receiver: _args.owner,
                spender: msg.sender,
                collateralType: _args.transitionFrom
            })
        });

        // transition collateral deposit
        (ISilo.CollateralType depositType, address shareTokenTo) =
            _args.transitionFrom == ISilo.CollateralType.Collateral
                ? (ISilo.CollateralType.Protected, depositConfig.protectedShareToken)
                : (ISilo.CollateralType.Collateral, depositConfig.collateralShareToken);

        (assets, toShares) = SiloERC4626Lib.deposit({
            _token: address(0), // empty token because we don't want to transfer
            _depositor: msg.sender,
            _assets: assets,
            _shares: 0,
            _receiver: _args.owner,
            _collateralShareToken: IShareToken(shareTokenTo),
            _collateralType: depositType
        });

        // If deposit is collateral, then check the solvency.
        if (depositConfig.silo == collateralConfig.silo) {
            _checkSolvencyWithoutAccruingInterest(collateralConfig, debtConfig, _args.owner);
        }

        siloConfig.turnOffReentrancyProtection();

        _hookCallAfterTransitionCollateral(_args, toShares, assets);
    }

    /// @notice Executes a flash loan, sending the requested amount to the receiver and expecting it back with a fee
    /// @param _receiver The entity that will receive the flash loan and is expected to return it with a fee
    /// @param _token The token that is being borrowed in the flash loan
    /// @param _amount The amount of tokens to be borrowed
    /// @param _data Additional data to be passed to the flash loan receiver
    /// @return success A boolean indicating if the flash loan was successful
    function flashLoan(
        IERC3156FlashBorrower _receiver,
        address _token,
        uint256 _amount,
        bytes calldata _data
    )
        external
        returns (bool success)
    {
        require(_amount != 0, ISilo.ZeroAmount());

        IShareToken.ShareTokenStorage storage _shareStorage = ShareTokenLib.getShareTokenStorage();

        if (_shareStorage.hookSetup.hooksBefore.matchAction(Hook.FLASH_LOAN)) {
            bytes memory data = abi.encodePacked(_receiver, _token, _amount);
            IHookReceiver(_shareStorage.hookSetup.hookReceiver).beforeAction(address(this), Hook.FLASH_LOAN, data);
        }

        // flashFee will revert for wrong token
        uint256 fee = SiloStdLib.flashFee(_shareStorage.siloConfig, _token, _amount);

        require(fee <= type(uint192).max, FeeOverflow());
        // this check also verify if token is correct
        require(_amount <= Views.maxFlashLoan(_token), FlashLoanNotPossible());

        // cast safe, because we checked `fee > type(uint192).max`
        // forge-lint: disable-next-line(unsafe-typecast)
        SiloStorageLib.getSiloStorage().daoAndDeployerRevenue += uint192(fee);

        IERC20(_token).safeTransfer(address(_receiver), _amount);

        require(
            _receiver.onFlashLoan(msg.sender, _token, _amount, fee, _data) == _FLASHLOAN_CALLBACK,
            ISilo.FlashloanFailed()
        );

        IERC20(_token).safeTransferFrom(address(_receiver), address(this), _amount + fee);

        if (_shareStorage.hookSetup.hooksAfter.matchAction(Hook.FLASH_LOAN)) {
            bytes memory data = abi.encodePacked(_receiver, _token, _amount, fee);
            IHookReceiver(_shareStorage.hookSetup.hookReceiver).afterAction(address(this), Hook.FLASH_LOAN, data);
        }

        success = true;
    }

    /// @notice Withdraws accumulated fees and distributes them proportionally to the DAO and deployer
    /// @dev This function takes into account scenarios where either the DAO or deployer may not be set, distributing
    /// accordingly
    /// @param _silo Silo address
    // solhint-disable-next-line function-max-lines
    function withdrawFees(ISilo _silo)
        external
        returns (uint256 daoRevenue, uint256 deployerRevenue, bool redirectedDeployerFees)
    {
        ISiloConfig siloConfig = ShareTokenLib.siloConfig();
        siloConfig.turnOnReentrancyProtection();

        ISilo.SiloStorage storage $ = SiloStorageLib.getSiloStorage();

        uint256 earnedFees = $.daoAndDeployerRevenue;
        require(earnedFees != 0, ISilo.EarnedZero());

        (
            address daoFeeReceiver,
            address deployerFeeReceiver,
            uint256 daoFee,
            uint256 deployerFee,
            address asset
        ) = SiloStdLib.getFeesAndFeeReceiversWithAsset(_silo);

        uint256 availableLiquidity;
        uint256 siloBalance = IERC20(asset).balanceOf(address(this));

        uint256 protectedAssets = $.totalAssets[ISilo.AssetType.Protected];

        // we will never underflow because `_protectedAssets` is always less/equal `siloBalance`
        unchecked { availableLiquidity = protectedAssets > siloBalance ? 0 : siloBalance - protectedAssets; }

        require(availableLiquidity != 0, ISilo.NoLiquidity());

        if (earnedFees > availableLiquidity) earnedFees = availableLiquidity;

        // we will never underflow because earnedFees max value is `daoAndDeployerRevenue`
        // forge-lint: disable-next-line(unsafe-typecast)
        unchecked { $.daoAndDeployerRevenue -= uint192(earnedFees); }

        daoRevenue = earnedFees;

        if (deployerFeeReceiver != address(0)) {
            // split fees proportionally
            unchecked {
                // fees are % in decimal point so safe to uncheck
                // we prioritizing DAO fee that's why Rounding.Ceil (UP)
                daoRevenue = Math.mulDiv(daoRevenue, daoFee, daoFee + deployerFee, Rounding.DAO_REVENUE);
                // `daoRevenue` is chunk of `earnedFees`, so safe to uncheck
                deployerRevenue = earnedFees - daoRevenue;
            }

            // trying to transfer to deployer (it might fail)
            // if transfer to deployer fails, send their portion to the DAO instead
            redirectedDeployerFees = !_safeTransferInternal(IERC20(asset), deployerFeeReceiver, deployerRevenue);
        }

        IERC20(asset).safeTransfer(daoFeeReceiver, redirectedDeployerFees ? earnedFees : daoRevenue);

        siloConfig.turnOffReentrancyProtection();
    }

    /// @notice Update hooks configuration for Silo
    /// @dev This function must be called after the hooks configuration is changed in the hook receiver
    function updateHooks() external returns (uint24 hooksBefore, uint24 hooksAfter) {
        ISiloConfig siloConfig = ShareTokenLib.siloConfig();

        NonReentrantLib.nonReentrant(siloConfig);

        ISiloConfig.ConfigData memory cfg = siloConfig.getConfig(address(this));

        if (cfg.hookReceiver == address(0)) return (0, 0);

        (hooksBefore, hooksAfter) = IHookReceiver(cfg.hookReceiver).hookReceiverConfig(address(this));

        IShareToken(cfg.collateralShareToken).synchronizeHooks(hooksBefore, hooksAfter);
        IShareToken(cfg.protectedShareToken).synchronizeHooks(hooksBefore, hooksAfter);
        IShareToken(cfg.debtShareToken).synchronizeHooks(hooksBefore, hooksAfter);
    }

    /// @notice Method for HookReceiver only to call on behalf of Silo
    /// @param _target address of the contract to call
    /// @param _value amount of ETH to send
    /// @param _callType type of the call (Call or Delegatecall)
    /// @param _input calldata for the call
    function callOnBehalfOfSilo(address _target, uint256 _value, ISilo.CallType _callType, bytes calldata _input)
        internal
        returns (bool success, bytes memory result)
    {
        require(
            msg.sender == address(ShareTokenLib.getShareTokenStorage().hookSetup.hookReceiver),
            ISilo.OnlyHookReceiver()
        );

        // Silo will not send back any ether leftovers after the call.
        // The hook receiver should request the ether if needed in a separate call.
        if (_callType == ISilo.CallType.Delegatecall) {
            (success, result) = _target.delegatecall(_input); // solhint-disable-line avoid-low-level-calls
        } else {
            (success, result) = _target.call{value: _value}(_input); // solhint-disable-line avoid-low-level-calls
        }
    }

    // this method expect interest to be already accrued
    function _checkSolvencyWithoutAccruingInterest(
        ISiloConfig.ConfigData memory _collateralConfig,
        ISiloConfig.ConfigData memory _debtConfig,
        address _user
    ) private {
        if (_debtConfig.silo != _collateralConfig.silo) {
            _collateralConfig.callSolvencyOracleBeforeQuote();
            _debtConfig.callSolvencyOracleBeforeQuote();
        }

        bool userIsSolvent = SiloSolvencyLib.isSolvent(
            _collateralConfig, _debtConfig, _user, ISilo.AccrueInterestInMemory.No
        );

        require(userIsSolvent, ISilo.NotSolvent());
    }

    // this method expect interest to be already accrued
    function _checkLTVWithoutAccruingInterest(
        ISiloConfig.ConfigData memory _collateralConfig,
        ISiloConfig.ConfigData memory _debtConfig,
        address _borrower
    ) private {
        if (_collateralConfig.silo != _debtConfig.silo) {
            _collateralConfig.callMaxLtvOracleBeforeQuote();
            _debtConfig.callMaxLtvOracleBeforeQuote();
        }

        bool borrowerIsBelowMaxLtv = SiloSolvencyLib.isBelowMaxLtv(
            _collateralConfig, _debtConfig, _borrower, ISilo.AccrueInterestInMemory.No
        );

        require(borrowerIsBelowMaxLtv, ISilo.AboveMaxLtv());
    }

    function _hookCallBeforeWithdraw(
        ISilo.WithdrawArgs calldata _args
    ) private {
        IShareToken.ShareTokenStorage storage _shareStorage = ShareTokenLib.getShareTokenStorage();

        uint256 action = Hook.withdrawAction(_args.collateralType);

        if (!_shareStorage.hookSetup.hooksBefore.matchAction(action)) return;

        bytes memory data =
            abi.encodePacked(_args.assets, _args.shares, _args.receiver, _args.owner, _args.spender);

        IHookReceiver(_shareStorage.hookSetup.hookReceiver).beforeAction(address(this), action, data);
    }

    function _hookCallAfterWithdraw(
        ISilo.WithdrawArgs calldata _args,
        uint256 assets,
        uint256 shares
    ) private {
        IShareToken.ShareTokenStorage storage _shareStorage = ShareTokenLib.getShareTokenStorage();

        uint256 action = Hook.withdrawAction(_args.collateralType);

        if (!_shareStorage.hookSetup.hooksAfter.matchAction(action)) return;

        bytes memory data =
            abi.encodePacked(_args.assets, _args.shares, _args.receiver, _args.owner, _args.spender, assets, shares);

        IHookReceiver(_shareStorage.hookSetup.hookReceiver).afterAction(address(this), action, data);
    }

    function _hookCallBeforeBorrow(ISilo.BorrowArgs memory _args, uint256 action) private {
        IShareToken.ShareTokenStorage storage _shareStorage = ShareTokenLib.getShareTokenStorage();

        if (!_shareStorage.hookSetup.hooksBefore.matchAction(action)) return;

        bytes memory data = abi.encodePacked(
            _args.assets,
            _args.shares,
            _args.receiver,
            _args.borrower,
            msg.sender // spender
        );

        IHookReceiver(_shareStorage.hookSetup.hookReceiver).beforeAction(address(this), action, data);
    }

    function _hookCallAfterBorrow(
        ISilo.BorrowArgs memory _args,
        uint256 action,
        uint256 assets,
        uint256 shares
    ) private {
        IShareToken.ShareTokenStorage storage _shareStorage = ShareTokenLib.getShareTokenStorage();

        if (!_shareStorage.hookSetup.hooksAfter.matchAction(action)) return;

        bytes memory data = abi.encodePacked(
            _args.assets,
            _args.shares,
            _args.receiver,
            _args.borrower,
            msg.sender, // spender
            assets,
            shares
        );

        IHookReceiver(_shareStorage.hookSetup.hookReceiver).afterAction(address(this), action, data);
    }

    function _hookCallBeforeTransitionCollateral(ISilo.TransitionCollateralArgs memory _args) private {
        IShareToken.ShareTokenStorage storage _shareStorage = ShareTokenLib.getShareTokenStorage();
        
        uint256 action = Hook.transitionCollateralAction(_args.transitionFrom);

        if (!_shareStorage.hookSetup.hooksBefore.matchAction(action)) return;

        bytes memory data = abi.encodePacked(_args.shares, _args.owner);

        IHookReceiver(_shareStorage.hookSetup.hookReceiver).beforeAction(address(this), action, data);
    }

    function _hookCallAfterTransitionCollateral(
        ISilo.TransitionCollateralArgs memory _args,
        uint256 _shares,
        uint256 _assets
    ) private {
        IShareToken.ShareTokenStorage storage _shareStorage = ShareTokenLib.getShareTokenStorage();
        uint256 action = Hook.transitionCollateralAction(_args.transitionFrom);

        if (!_shareStorage.hookSetup.hooksAfter.matchAction(action)) return;

        bytes memory data = abi.encodePacked(_shares, _args.owner, _assets);

        IHookReceiver(_shareStorage.hookSetup.hookReceiver).afterAction(address(this), action, data);
    }

    function _hookCallBeforeDeposit(
        ISilo.CollateralType _collateralType,
        uint256 _assets,
        uint256 _shares,
        address _receiver
    ) private {
        IShareToken.ShareTokenStorage storage _shareStorage = ShareTokenLib.getShareTokenStorage();
        uint256 action = Hook.depositAction(_collateralType);

        if (!_shareStorage.hookSetup.hooksBefore.matchAction(action)) return;

        bytes memory data = abi.encodePacked(_assets, _shares, _receiver);

        IHookReceiver(_shareStorage.hookSetup.hookReceiver).beforeAction(address(this), action, data);
    }

    function _hookCallAfterDeposit(
        ISilo.CollateralType _collateralType,
        uint256 _assets,
        uint256 _shares,
        address _receiver,
        uint256 _exactAssets,
        uint256 _exactShare
    ) private {
        IShareToken.ShareTokenStorage storage _shareStorage = ShareTokenLib.getShareTokenStorage();
        uint256 action = Hook.depositAction(_collateralType);

        if (!_shareStorage.hookSetup.hooksAfter.matchAction(action)) return;

        bytes memory data = abi.encodePacked(_assets, _shares, _receiver, _exactAssets, _exactShare);

        IHookReceiver(_shareStorage.hookSetup.hookReceiver).afterAction(address(this), action, data);
    }

    /**
     * @dev Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    function _safeTransferInternal(IERC20 _token, address _to, uint256 _value) internal returns (bool result) {
        bytes memory data = abi.encodeCall(_token.transfer, (_to, _value));
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = address(_token).call(data);
        if (!success) return false;

        result = returndata.length == 0 || abi.decode(returndata, (bool));
    }
}
