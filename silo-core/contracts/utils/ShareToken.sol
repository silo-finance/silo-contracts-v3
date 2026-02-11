// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20Permit} from "openzeppelin5/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20PermitUpgradeable} from "openzeppelin5-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20Upgradeable} from "openzeppelin5-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Metadata, IERC20} from "openzeppelin5/token/ERC20/ERC20.sol";

import {IHookReceiver} from "../interfaces/IHookReceiver.sol";
import {IShareToken, ISilo} from "../interfaces/IShareToken.sol";
import {ISiloConfig} from "../SiloConfig.sol";
import {Hook} from "../lib/Hook.sol";
import {CallBeforeQuoteLib} from "../lib/CallBeforeQuoteLib.sol";
import {NonReentrantLib} from "../lib/NonReentrantLib.sol";
import {ShareTokenLib} from "../lib/ShareTokenLib.sol";
import {SiloMathLib} from "../lib/SiloMathLib.sol";
import {IVersioned} from "../interfaces/IVersioned.sol";


/// @title ShareToken
/// @notice Implements common interface for Silo tokens representing debt or collateral.
/// @dev Docs borrowed from https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v4.9.3
///
/// Implementation of the ERC4626 "Tokenized Vault Standard" as defined in
/// https://eips.ethereum.org/EIPS/eip-4626[EIP-4626].
///
/// This extension allows the minting and burning of "shares" (represented using the ERC20 inheritance) in exchange for
/// underlying "assets" through standardized {deposit}, {mint}, {redeem} and {burn} workflows. This contract extends
/// the ERC20 standard. Any additional extensions included along it would affect the "shares" token represented by this
/// contract and not the "assets" token which is an independent contract.
///
/// [CAUTION]
/// ====
/// In empty (or nearly empty) ERC-4626 vaults, deposits are at high risk of being stolen through frontrunning
/// with a "donation" to the vault that inflates the price of a share. This is variously known as a donation or
/// inflation attack and is essentially a problem of slippage. Vault deployers can protect against this attack by
/// making an initial deposit of a non-trivial amount of the asset, such that price manipulation becomes infeasible.
/// Withdrawals may similarly be affected by slippage. Users can protect against this attack as well as unexpected
/// slippage in general by verifying the amount received is as expected, using a wrapper that performs these checks
/// such as https://github.com/fei-protocol/ERC4626#erc4626router-and-base[ERC4626Router].
///
/// Since v4.9, this implementation uses virtual assets and shares to mitigate that risk. The `_decimalsOffset()`
/// corresponds to an offset in the decimal representation between the underlying asset's decimals and the vault
/// decimals. This offset also determines the rate of virtual shares to virtual assets in the vault, which itself
/// determines the initial exchange rate. While not fully preventing the attack, analysis shows that the default offset
/// (0) makes it non-profitable, as a result of the value being captured by the virtual shares (out of the attacker's
/// donation) matching the attacker's expected gains. With a larger offset, the attack becomes orders of magnitude more
/// expensive than it is profitable. More details about the underlying math can be found
/// xref:erc4626.adoc#inflation-attack[here].
///
/// The drawback of this approach is that the virtual shares do capture (a very small) part of the value being accrued
/// to the vault. Also, if the vault experiences losses, the users try to exit the vault, the virtual shares and assets
/// will cause the first user to exit to experience reduced losses in detriment to the last users that will experience
/// bigger losses. Developers willing to revert back to the pre-v4.9 behavior just need to override the
/// `_convertToShares` and `_convertToAssets` functions.
///
/// To learn more, check out our xref:ROOT:erc4626.adoc[ERC-4626 guide].
/// ====
///
/// _Available since v4.7._
/// @custom:security-contact security@silo.finance
abstract contract ShareToken is ERC20PermitUpgradeable, IShareToken, IVersioned {
    using Hook for uint24;
    using CallBeforeQuoteLib for ISiloConfig.ConfigData;

    string private constant _NAME = "SiloShareTokenEIP712Name";

    modifier onlySilo() {
        require(msg.sender == address(_getSilo()), OnlySilo());

        _;
    }

    modifier onlyHookReceiver() {
        require(
            msg.sender == address(ShareTokenLib.getShareTokenStorage().hookSetup.hookReceiver),
            ISilo.OnlyHookReceiver()
        );

        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IShareToken
    function synchronizeHooks(uint24 _hooksBefore, uint24 _hooksAfter) external virtual onlySilo {
        IShareToken.ShareTokenStorage storage $ = ShareTokenLib.getShareTokenStorage();

        $.hookSetup.hooksBefore = _hooksBefore;
        $.hookSetup.hooksAfter = _hooksAfter;
    }

    /// @inheritdoc IShareToken
    function forwardTransferFromNoChecks(address _from, address _to, uint256 _amount)
        external
        virtual
        onlyHookReceiver
    {
        IShareToken.ShareTokenStorage storage $ = ShareTokenLib.getShareTokenStorage();

        $.transferWithChecks = false;
        _transfer(_from, _to, _amount);
        $.transferWithChecks = true;
    }

    /// @inheritdoc IShareToken
    function decimalsOffset() external view virtual returns (uint256) {
        return SiloMathLib._DECIMALS_OFFSET;
    }

    function silo() external view virtual returns (ISilo) {
        return _getSilo();
    }

    function siloConfig() external view virtual returns (ISiloConfig) {
        return _getSiloConfig();
    }

    function hookSetup() external view virtual returns (HookSetup memory) {
        return ShareTokenLib.getShareTokenStorage().hookSetup;
    }

    function hookReceiver() external view virtual returns (address) {
        return ShareTokenLib.getShareTokenStorage().hookSetup.hookReceiver;
    }

    /// @inheritdoc ERC20Upgradeable
    function transferFrom(address _from, address _to, uint256 _amount)
        public
        virtual
        override(ERC20Upgradeable, IERC20)
        returns (bool result)
    {
        ISiloConfig siloConfigCached = _crossNonReentrantBefore();

        result = ERC20Upgradeable.transferFrom(_from, _to, _amount);

        siloConfigCached.turnOffReentrancyProtection();
    }

    /// @inheritdoc ERC20Upgradeable
    function transfer(address _to, uint256 _amount)
        public
        virtual
        override(ERC20Upgradeable, IERC20)
        returns (bool result)
    {
        ISiloConfig siloConfigCached = _crossNonReentrantBefore();

        result = ERC20Upgradeable.transfer(_to, _amount);

        siloConfigCached.turnOffReentrancyProtection();
    }

    function approve(address spender, uint256 value)
        public
        virtual
        override(ERC20Upgradeable, IERC20)
        returns (bool result)
    {
        NonReentrantLib.nonReentrant(_getSiloConfig());

        result = ERC20Upgradeable.approve(spender, value);
    }

    /// @inheritdoc IERC20Permit
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override {
        NonReentrantLib.nonReentrant(_getSiloConfig());

        ERC20PermitUpgradeable.permit(owner, spender, value, deadline, v, r, s);
    }

    /* solhint-disable */
    /// @notice Decimals are the same as underlaying asset. Decimal offset is not accounted for in decimals.
    /// @dev This does not imply a 1:1 ratio between shares and assets.
    ///
    /// Silo:
    ///     decimals(): same as underlying asset
    ///     offset: 3
    ///     minted shares per 1 wei of asset deposited: 1000
    /// ProtectedShareToken:
    ///     decimals(): same as underlying asset
    ///     offset: 3
    ///     minted shares per 1 wei of asset deposited: 1000
    /// DebtShareToken:
    ///     decimals(): same as underlying asset
    ///     offset: 0
    ///     minted shares per 1 wei of asset borrowed: 1
    ///
    /// Learn more about the offset here:
    /// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/a7d38c7a3321e3832ca84f7ba1125dff9a91361e/contracts/token/ERC20/extensions/ERC4626.sol#L31
    ///
    /// The share-to-asset ratio may change over time due to interest accrual. As assets grow with interest
    /// but the number of shares remains constant, the ratio will adjust dynamically.
    ///
    /// To determine the current conversion rate, use the vault’s `convertToShares(1 asset)` method.
    function decimals() public view virtual override(ERC20Upgradeable, IERC20Metadata) returns (uint8) {
        return ShareTokenLib.decimals();
    }
    /* solhint-enable */

    /// @dev Name convention:
    ///      NAME - asset name
    ///      SILO_ID - unique silo id
    ///
    ///      Protected deposit: "Silo Finance Non-borrowable NAME Deposit, SiloId: SILO_ID"
    ///      Borrowable deposit: "Silo Finance Borrowable NAME Deposit, SiloId: SILO_ID"
    ///      Debt: "Silo Finance NAME Debt, SiloId: SILO_ID"
    function name()
        public
        view
        virtual
        override(ERC20Upgradeable, IERC20Metadata)
        returns (string memory)
    {
        return ShareTokenLib.name();
    }

    /// @dev Symbol convention:
    ///      SYMBOL - asset symbol
    ///      SILO_ID - unique silo id
    ///
    ///      Protected deposit: "nbSYMBOL-SILO_ID"
    ///      Borrowable deposit: "bSYMBOL-SILO_ID"
    ///      Debt: "dSYMBOL-SILO_ID"
    function symbol()
        public
        view
        virtual
        override(ERC20Upgradeable, IERC20Metadata)
        returns (string memory)
    {
        return ShareTokenLib.symbol();
    }

    function balanceOfAndTotalSupply(address _account) public view virtual returns (uint256, uint256) {
        return (balanceOf(_account), totalSupply());
    }

    /// @dev Share token initialization
    function _shareTokenInitialize(
        ISilo _silo,
        address _hookReceiver,
        uint24 _tokenType
    )
        internal
        virtual
        initializer
    {
        __ERC20Permit_init(_NAME);

        ShareTokenLib.__ShareToken_init(_silo, _hookReceiver, _tokenType);
    }

    /// @inheritdoc ERC20Upgradeable
    function _update(address from, address to, uint256 value) internal virtual override {
        require(value != 0, ZeroTransfer());

        _beforeTokenTransfer(from, to, value);

        ERC20Upgradeable._update(from, to, value);

        _afterTokenTransfer(from, to, value);
    }

    /// @dev By default, we do not have any hooks before token transfer. However,
    /// derived contracts can override this function if they need to execute any logic before token transfer.
    function _beforeTokenTransfer(address _sender, address _recipient, uint256 _amount) internal virtual {}

    /// @dev Call an afterTokenTransfer hook if registered
    function _afterTokenTransfer(address _sender, address _recipient, uint256 _amount) internal virtual {
        IShareToken.ShareTokenStorage storage $ = ShareTokenLib.getShareTokenStorage();
        HookSetup memory setup = $.hookSetup;

        uint256 action = Hook.shareTokenTransfer(setup.tokenType);

        if (!setup.hooksAfter.matchAction(action)) return;

        // report mint, burn or transfer
        // even if it is possible to leave silo in a middle of mint/burn, where we can have invalid state
        // you can not enter any function because of cross reentrancy check
        // invalid mid-state can be eg: in a middle of transitionCollateral, after burn but before mint
        IHookReceiver(setup.hookReceiver).afterAction(
            address($.silo),
            action,
            abi.encodePacked(_sender, _recipient, _amount, balanceOf(_sender), balanceOf(_recipient), totalSupply())
        );
    }

    function _crossNonReentrantBefore()
        internal
        virtual
        returns (ISiloConfig siloConfigCached)
    {
        siloConfigCached = _getSiloConfig();
        siloConfigCached.turnOnReentrancyProtection();
    }

    function _getSiloConfig() internal view virtual returns (ISiloConfig) {
        return ShareTokenLib.getShareTokenStorage().siloConfig;
    }
    
    function _getSilo() internal view virtual returns (ISilo) {
        return ShareTokenLib.getShareTokenStorage().silo;
    }
}
