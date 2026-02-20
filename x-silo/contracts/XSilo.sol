// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC4626, IERC4626, ERC20, IERC20} from "openzeppelin5/token/ERC20/extensions/ERC4626.sol";
import {Math} from "openzeppelin5/utils/math/Math.sol";

import {TokenHelper} from "silo-core/contracts/lib/TokenHelper.sol";

import {XSiloManagement, INotificationReceiver} from "./modules/XSiloManagement.sol";
import {XRedeemPolicy} from "./modules/XRedeemPolicy.sol";
import {IStream} from "./modules/Stream.sol";

contract XSilo is ERC4626, XSiloManagement, XRedeemPolicy {
    error ZeroShares();
    error ZeroAssets();
    error SelfTransferNotAllowed();
    error ZeroTransfer();

    constructor(address _initialOwner, address _asset, address _stream)
        XSiloManagement(_initialOwner, _stream)
        ERC4626(IERC20(_asset))
        ERC20(string.concat("x", TokenHelper.symbol(_asset)), string.concat("x", TokenHelper.symbol(_asset)))
    {
    }

    /// @inheritdoc IERC4626
    function deposit(uint256 _assets, address _receiver) public virtual override nonReentrant returns (uint256 shares) {
        shares = super.deposit(_assets, _receiver);
    }

    /// @inheritdoc IERC4626
    function mint(uint256 _shares, address _receiver) public virtual override nonReentrant returns (uint256 assets) {
        assets = super.mint(_shares, _receiver);
    }

    /// @inheritdoc IERC4626
    /// @notice `withdraw` uses a duration of 0 to calculate amount of Silo to withdraw. Duration 0 represents
    /// the worst-case scenario for asset withdrawals. To obtain a better deal, please use the custom method
    /// `redeemSilo` with different duration.
    function withdraw(uint256 _assets, address _receiver, address _owner)
        public
        virtual
        override
        nonReentrant
        returns (uint256 shares)
    {
        shares = super.withdraw(_assets, _receiver, _owner);
    }

    /// @inheritdoc IERC4626
    /// @notice `redeem` uses a duration of 0 to calculate amount of Silo to redeem. Duration 0 represents
    /// the worst-case scenario for asset withdrawals. To obtain a better deal, please use the custom method
    /// `redeemSilo` with different duration.
    function redeem(uint256 _shares, address _receiver, address _owner)
        public
        virtual
        override
        nonReentrant
        returns (uint256 assets)
    {
        assets = super.redeem(_shares, _receiver, _owner);
    }

    /// @inheritdoc ERC20
    function transfer(address _to, uint256 _value) public virtual override(ERC20, IERC20) nonReentrant returns (bool) {
        return super.transfer(_to, _value);
    }

    /// @inheritdoc ERC20
    function transferFrom(address _from, address _to, uint256 _value)
        public
        virtual
        override(ERC20, IERC20)
        nonReentrant
        returns (bool)
    {
        return super.transferFrom(_from, _to, _value);
    }

    /// @inheritdoc IERC4626
    function totalAssets() public view virtual override returns (uint256 total) {
        if (totalSupply() == 0) {
            // when xSilo is empty and everyone withdrew but there are still SILO assets left
            // then, reset totalAssets to 0 so the Silo that remains goes to first depositor
            return 0;
        }

        total = super.totalAssets();

        IStream stream_ = stream;
        if (address(stream_) != address(0)) total += stream_.pendingRewards();

        total -= pendingLockedSilo;
    }

    /// @inheritdoc IERC4626
    /// @notice `maxWithdraw` uses a duration of 0 to calculate the result, which represents the worst-case scenario
    /// for asset withdrawals. To obtain a better deal, please use the custom method `getAmountByVestingDuration` with
    /// different duration.
    function maxWithdraw(address _owner) public view virtual override returns (uint256 assets) {
        uint256 xSiloAfterVesting = getXAmountByVestingDuration(balanceOf(_owner), 0);
        assets = _convertToAssets(xSiloAfterVesting, Math.Rounding.Floor);
    }

    /// @inheritdoc IERC4626
    /// @notice `maxRedeem` returns user balance based on best case scenario (max vesting), however when user
    /// do `redeem`, `shares` that are actually used for redeeming process are calculated based on vesting with
    /// duration == 0, which represents the worst-case scenario for asset redeeming.
    /// Therefore only part of that shares will be converted back to Silo.
    /// To obtain a better deal, please use the custom method `redeemSilo` with different duration.
    function maxRedeem(address _owner) public view virtual override returns (uint256 shares) {
        shares = super.maxRedeem(_owner);
    }

    /// @inheritdoc IERC4626
    /// @notice `previewWithdraw` uses a duration of 0 to calculate the result, which represents the worst-case scenario
    /// for asset withdrawals. To obtain a better deal, please use the custom method `getAmountByVestingDuration` with
    /// different duration.
    function previewWithdraw(uint256 _assets) public view virtual override returns (uint256 shares) {
        uint256 _xSiloAfterVesting = _convertToShares(_assets, Math.Rounding.Ceil);
        shares = getAmountInByVestingDuration(_xSiloAfterVesting, 0);
    }

    /// @inheritdoc IERC4626
    /// @notice `previewRedeem` uses a duration of 0 to calculate the result, which represents the worst-case scenario
    /// for asset redeem. To obtain a better deal, please use the custom method `getAmountByVestingDuration` with
    /// different duration.
    function previewRedeem(uint256 _shares) public view virtual override returns (uint256 assets) {
        uint256 xSiloAfterVesting = getXAmountByVestingDuration(_shares, 0);
        assets = _convertToAssets(xSiloAfterVesting, Math.Rounding.Floor);
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(address _caller, address _receiver, uint256 _assets, uint256 _shares) internal virtual override {
        require(_shares != 0, ZeroShares());
        require(_assets != 0, ZeroAssets());

        super._deposit(_caller, _receiver, _assets, _shares);
    }

    function _withdraw(
        address _caller,
        address _receiver,
        address _owner,
        uint256 _assetsToTransfer,
        uint256 _sharesToBurn
    ) internal virtual override(ERC4626, XRedeemPolicy) {
        require(_sharesToBurn != 0, ZeroShares());
        require(_assetsToTransfer != 0, ZeroAssets());

        ERC4626._withdraw(_caller, _receiver, _owner, _assetsToTransfer, _sharesToBurn);
    }

    function _transferShares(address _from, address _to, uint256 _shares) internal virtual override {
        return ERC20._transfer(_from, _to, _shares);
    }

    function _mintShares(address _account, uint256 _shares) internal virtual override {
        return ERC20._mint(_account, _shares);
    }

    function _getSiloToken() internal view virtual override returns (address tokenAddress) {
        tokenAddress = asset();
    }

    function _convertToAssets(uint256 _shares, Math.Rounding _rounding)
        internal
        view
        virtual
        override(ERC4626, XRedeemPolicy)
        returns (uint256)
    {
        return ERC4626._convertToAssets(_shares, _rounding);
    }

    function _convertToShares(uint256 _assets, Math.Rounding _rounding)
        internal
        view
        virtual
        override(ERC4626, XRedeemPolicy)
        returns (uint256)
    {
        return ERC4626._convertToShares(_assets, _rounding);
    }

    function _update(address _from, address _to, uint256 _value) internal virtual override {
        require(_from != _to, SelfTransferNotAllowed());
        require(_value != 0, ZeroTransfer());

        IStream stream_ = stream;
        if (address(stream_) != address(0)) stream_.claimRewards();

        super._update(_from, _to, _value);

        INotificationReceiver receiver = notificationReceiver;

        if (address(receiver) == address(0)) return;

        receiver.afterTokenTransfer({
            _sender: _from,
            _senderBalance: balanceOf(_from),
            _recipient: _to,
            _recipientBalance: balanceOf(_to),
            _totalSupply: totalSupply(),
            _amount: _value
        });
    }
}
