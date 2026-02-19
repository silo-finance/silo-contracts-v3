// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Silo, ISilo} from "silo-core/contracts/Silo.sol";
import {IERC3156FlashBorrower} from "silo-core/contracts/interfaces/IERC3156FlashBorrower.sol";
import {PartialLiquidation} from "silo-core/contracts/hooks/liquidation/PartialLiquidation.sol";
import {ISiloConfig} from "silo-core/contracts/SiloConfig.sol";
import {TestERC20Token} from "properties/ERC4626/util/TestERC20Token.sol";
import {PropertiesAsserts} from "properties/util/PropertiesHelper.sol";

/// @notice This contract has two purposes:
///  1. Act as a proxy for performing vault deposits/withdraws (since we don't have vm.prank)
///  2. Keep track of how much the account has deposited/withdrawn & raise an error if the account can withdraw/redeem more than it deposited/minted.
/// @dev It's important that other property tests never send tokens/shares to the Actor contract address, or else the accounting will break. This restriction is enforced in restrictAddressToThirdParties()
///      If support is added for "harvesting" a vault during property tests, the accounting logic here needs to be updated to reflect cases where an actor can withdraw more than they deposited.
contract Actor is PropertiesAsserts, IERC3156FlashBorrower {
    bytes32 internal constant _FLASHLOAN_CALLBACK = keccak256("ERC3156FlashBorrower.onFlashLoan");

    TestERC20Token immutable TOKEN0;
    TestERC20Token immutable TOKEN1;
    Silo immutable VAULT0;
    Silo immutable VAULT1;
    PartialLiquidation immutable LIQUIDATION_MODULE;

    mapping(address => uint256) public tokensDepositedCollateral;
    mapping(address => uint256) public tokensDepositedProtected;
    mapping(address => uint256) public tokensBorrowed;
    mapping(address => uint256) public protectedMinted;
    mapping(address => uint256) public collateralMinted;
    mapping(address => uint256) public debtMinted;

    constructor(Silo _vault0, Silo _vault1) {
        VAULT0 = _vault0;
        VAULT1 = _vault1;
        TOKEN0 = TestERC20Token(address(_vault0.asset()));
        TOKEN1 = TestERC20Token(address(_vault1.asset()));
        LIQUIDATION_MODULE = PartialLiquidation(_vault0.config().getConfig(address(_vault0)).hookReceiver);
    }

    function deposit(bool _vaultZero, uint256 _assets) public returns (uint256 shares) {
        Silo vault = _prepareForDeposit(_vaultZero, _assets);

        shares = vault.deposit(_assets, address(this));
        _accountForOpenedPosition(ISilo.CollateralType.Collateral, _vaultZero, _assets, shares);
    }

    function depositAssetType(bool _vaultZero, uint256 _assets, ISilo.CollateralType _assetType)
        external
        returns (uint256 shares)
    {
        Silo vault = _prepareForDeposit(_vaultZero, _assets);

        shares = vault.deposit(_assets, address(this), _assetType);
        _accountForOpenedPosition(_assetType, _vaultZero, _assets, shares);
    }

    function mint(bool _vaultZero, uint256 _shares) external returns (uint256 assets) {
        (Silo vault,) = _prepareForDepositShares(_vaultZero, _shares, ISilo.CollateralType.Collateral);

        assets = vault.mint(_shares, address(this));
        _accountForOpenedPosition(ISilo.CollateralType.Collateral, _vaultZero, assets, _shares);
    }

    function mintAssetType(bool _vaultZero, uint256 _shares, ISilo.CollateralType _assetType)
        external
        returns (uint256 assets)
    {
        (Silo vault,) = _prepareForDepositShares(_vaultZero, _shares, _assetType);

        assets = vault.mint(_shares, address(this), _assetType);
        _accountForOpenedPosition(_assetType, _vaultZero, assets, _shares);
    }

    function withdraw(bool _vaultZero, uint256 _assets) external returns (uint256 shares) {
        Silo vault = _vaultZero ? VAULT0 : VAULT1;
        shares = vault.withdraw(_assets, address(this), address(this));
        _accountForClosedPosition(ISilo.CollateralType.Collateral, _vaultZero, _assets, shares);
    }

    function withdrawAssetType(bool _vaultZero, uint256 _assets, ISilo.CollateralType _assetType)
        external
        returns (uint256 shares)
    {
        Silo vault = _vaultZero ? VAULT0 : VAULT1;
        shares = vault.withdraw(_assets, address(this), address(this), _assetType);
        _accountForClosedPosition(_assetType, _vaultZero, _assets, shares);
    }

    function redeem(bool _vaultZero, uint256 _shares) external returns (uint256 assets) {
        Silo vault = _vaultZero ? VAULT0 : VAULT1;
        assets = vault.redeem(_shares, address(this), address(this));
        _accountForClosedPosition(ISilo.CollateralType.Collateral, _vaultZero, assets, _shares);
    }

    function redeemAssetType(bool _vaultZero, uint256 _shares, ISilo.CollateralType _assetType)
        external
        returns (uint256 assets)
    {
        Silo vault = _vaultZero ? VAULT0 : VAULT1;
        assets = vault.redeem(_shares, address(this), address(this), _assetType);
        _accountForClosedPosition(_assetType, _vaultZero, assets, _shares);
    }

    function borrow(bool _vaultZero, uint256 _assets) external returns (uint256 shares) {
        Silo vault = _vaultZero ? VAULT0 : VAULT1;
        shares = vault.borrow(_assets, address(this), address(this));
        _accountForOpenedDebt(_vaultZero, _assets, shares);
    }

    function borrowShares(bool _vaultZero, uint256 _shares) external returns (uint256 assets) {
        Silo vault = _vaultZero ? VAULT0 : VAULT1;
        assets = vault.borrowShares(_shares, address(this), address(this));
        _accountForOpenedDebt(_vaultZero, assets, _shares);
    }

    function repay(bool _vaultZero, uint256 _assets) external returns (uint256 shares) {
        Silo vault = _vaultZero ? VAULT0 : VAULT1;
        _approveFunds(_vaultZero, _assets, address(vault));
        shares = vault.repay(_assets, address(this));
        _accountForClosedDebt(_vaultZero, _assets, shares);
    }

    function repayShares(bool _vaultZero, uint256 _shares) external returns (uint256 assets) {
        (Silo vault,) = _prepareForRepayShares(_vaultZero, _shares);
        assets = vault.repayShares(_shares, address(this));
        _accountForClosedDebt(_vaultZero, assets, _shares);
    }

    function transitionCollateral(bool _vaultZero, uint256 _shares, ISilo.CollateralType withdrawType)
        external
        returns (uint256 assets)
    {
        Silo vault = _vaultZero ? VAULT0 : VAULT1;
        assets = vault.transitionCollateral(_shares, address(this), withdrawType);
        _accountForClosedPosition(withdrawType, _vaultZero, assets, _shares);
        _accountForOpenedPosition(withdrawType, _vaultZero, assets, _shares);
    }

    function flashLoan(bool _vaultZero, uint256 _amount) public returns (bool success) {
        Silo vault = _vaultZero ? VAULT0 : VAULT1;
        return vault.flashLoan(this, address(_vaultZero ? TOKEN0 : TOKEN1), _amount, "");
    }

    function liquidationCall(address borrower, uint256 debtToCover, bool receiveSToken, ISiloConfig config)
        public
    {
        (ISiloConfig.ConfigData memory collateralConfig, ISiloConfig.ConfigData memory debtConfig) =
            config.getConfigsForSolvency(borrower);

        LIQUIDATION_MODULE.liquidationCall(
            collateralConfig.token, debtConfig.token, borrower, debtToCover, receiveSToken
        );
    }

    function onFlashLoan(
        address _initiator,
        address _token,
        uint256 _amount,
        uint256 _fee,
        bytes calldata // _data
    ) external returns (bytes32) {
        _requireTotalCap(_token == address(TOKEN0), _amount + _fee);

        assert(_initiator == address(this));

        _fund(_token == address(TOKEN0), _amount + _fee);
        TestERC20Token(_token).approve(msg.sender, _amount + _fee);
        return _FLASHLOAN_CALLBACK;
    }

    function _accountForOpenedPosition(
        ISilo.CollateralType _assetType,
        bool _vaultZero,
        uint256 _tokensDeposited,
        uint256 _sharesMinted
    ) internal {
        address vault = _vaultZero ? address(VAULT0) : address(VAULT1);

        if (_assetType == ISilo.CollateralType.Collateral) {
            tokensDepositedCollateral[vault] += _tokensDeposited;
            collateralMinted[vault] += _sharesMinted;
        } else if (_assetType == ISilo.CollateralType.Protected) {
            tokensDepositedProtected[vault] += _tokensDeposited;
            protectedMinted[vault] += _sharesMinted;
        }
    }

    function _accountForOpenedDebt(bool _vaultZero, uint256 _tokensDeposited, uint256 _sharesMinted) internal {
        address vault = _vaultZero ? address(VAULT0) : address(VAULT1);

        tokensBorrowed[vault] += _tokensDeposited;
        debtMinted[vault] += _sharesMinted;
    }

    function _accountForClosedDebt(bool _vaultZero, uint256, /* _tokensReceived */ uint256 /* _sharesBurned */ )
        internal
        pure
    {}

    function _accountForClosedPosition(
        ISilo.CollateralType, /* _assetType */
        bool _vaultZero,
        uint256, /* _tokensReceived */
        uint256 /* _sharesBurned */
    ) internal pure {
        // address vault = _vaultZero ? address(VAULT0) : address(VAULT1);

        // note: The below code can lead to false positives since it does not account for interest.
        // In order to properly check these properties it needs to be modified so the accounting is correct.

        /*         if (_assetType == ISilo.CollateralType.Collateral) {
            assertLte(_sharesBurned, collateralMinted[vault],  "Actor has burned more shares than they ever minted. Implies a rounding or accounting error");
            assertLte(_tokensReceived, tokensDepositedCollateral[vault],  "Actor has withdrawn more tokens than they ever deposited. Implies a rounding or accounting error");
            tokensDepositedCollateral[vault] -= _tokensReceived;
            collateralMinted[vault] -= _sharesBurned;
        } else if (_assetType == ISilo.CollateralType.Protected) {
            assertLte(_sharesBurned, protectedMinted[vault],  "Actor has burned more shares than they ever minted. Implies a rounding or accounting error");
            assertLte(_tokensReceived, tokensDepositedProtected[vault],  "Actor has withdrawn more tokens than they ever deposited. Implies a rounding or accounting error");
            tokensDepositedProtected[vault] -= _tokensReceived;
            protectedMinted[vault] -= _sharesBurned;
        } else {
            assertLte(_sharesBurned, debtMinted[vault],  "Actor has burned more shares than they ever minted. Implies a rounding or accounting error");
            assertLte(_tokensReceived, tokensBorrowed[vault],  "Actor has withdrawn more tokens than they ever deposited. Implies a rounding or accounting error");
            tokensBorrowed[vault] -= _tokensReceived;
            debtMinted[vault] -= _sharesBurned;
        } */
    }

    function _prepareForDeposit(bool _vaultZero, uint256 amount) internal returns (Silo vault) {
        vault = _vaultZero ? VAULT0 : VAULT1;
        _fund(_vaultZero, amount);
        _approveFunds(_vaultZero, amount, address(vault));
    }

    function _prepareForDepositShares(bool _vaultZero, uint256 _shares, ISilo.CollateralType _assetType)
        internal
        returns (Silo vault, uint256 amount)
    {
        vault = _vaultZero ? VAULT0 : VAULT1;
        amount = vault.previewMint(_shares, _assetType);

        _prepareForDeposit(_vaultZero, amount);
    }

    function _prepareForRepayShares(bool _vaultZero, uint256 _shares)
        internal
        returns (Silo vault, uint256 amount)
    {
        vault = _vaultZero ? VAULT0 : VAULT1;
        amount = vault.previewRepayShares(_shares);

        _approveFunds(_vaultZero, amount, address(vault));
    }

    function _prepareForLiquidationRepay(bool _vaultZero, uint256 debtToRepay) internal returns (Silo vault) {
        vault = _vaultZero ? VAULT0 : VAULT1;
        TestERC20Token token = _vaultZero ? TOKEN0 : TOKEN1;

        uint256 balance = token.balanceOf(address(this));

        if (balance < debtToRepay) {
            if (type(uint256).max - token.totalSupply() < debtToRepay - balance) {
                revert("total supply limit - require it for echidna, so it does not fail on it");
            }

            token.mint(address(this), debtToRepay - balance);
        }

        _approveFunds(_vaultZero, debtToRepay, address(vault));
    }

    function _fund(bool _vaultZero, uint256 _amount) internal {
        TestERC20Token token = _vaultZero ? TOKEN0 : TOKEN1;
        uint256 balance = token.balanceOf(address(this));

        if (balance < _amount) {
            token.mint(address(this), _amount - balance);
        }
    }

    function _approveFunds(bool _vaultZero, uint256 amount, address vault) internal {
        TestERC20Token token = _vaultZero ? TOKEN0 : TOKEN1;
        token.approve(vault, amount);
    }

    function _requireTotalCap(bool _vaultZero, uint256 requiredBalance) internal view {
        TestERC20Token token = _vaultZero ? TOKEN0 : TOKEN1;
        uint256 balance = token.balanceOf(address(this));

        if (balance < requiredBalance) {
            require(type(uint256).max - token.totalSupply() >= requiredBalance - balance, "total supply limit");
        }
    }
}
