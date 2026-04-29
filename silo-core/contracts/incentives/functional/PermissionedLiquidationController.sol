// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {SiloIncentivesControllerCompatible} from "../SiloIncentivesControllerCompatible.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {Whitelist} from "silo-core/contracts/hooks/_common/Whitelist.sol";

contract PermissionedLiquidationController is SiloIncentivesControllerCompatible, Whitelist {
    using SafeERC20 for IERC20;

    address public immutable HOOK_RECEIVER;
    IERC20 public immutable DEBT_ASSET;
    address public immutable DEBT_SILO;
    IERC20 public immutable COLLATERAL_ASSET;

    bool public enabled = true;

    bool private transient _liquidationAllowed;

    error LiquidationNotAllowed();
    error STokenNotSupported();

    constructor(address _owner, address _notifier, address _shareTokenAddress)
        SiloIncentivesControllerCompatible(_owner, _notifier, _shareTokenAddress)
    {
        __Whitelist_init(_owner);

        HOOK_RECEIVER = IShareToken(_shareTokenAddress).hookReceiver();

        address collateralSilo = address(IShareToken(_shareTokenAddress).silo());
        ISiloConfig siloConfig = IShareToken(_shareTokenAddress).siloConfig();
        (address silo0, address silo1) = siloConfig.getSilos();
        DEBT_SILO = silo0 == collateralSilo ? silo1 : silo0;
        DEBT_ASSET = IERC20(siloConfig.getAssetForSilo(DEBT_SILO));
        COLLATERAL_ASSET = IERC20(siloConfig.getAssetForSilo(collateralSilo));

        DEBT_ASSET.approve(HOOK_RECEIVER, type(uint256).max);
    }

    function setEnabled(bool _enabled) external onlyOwner {
        enabled = _enabled;
    }

    /// @dev this incentive controller needs to be set for protected and collateral
    function afterTokenTransfer(
        address _sender,
        uint256 /*_senderBalance*/,
        address /*_recipient*/,
        uint256 /*_recipientBalance*/,
        uint256 /*_totalSupply*/,
        uint256 /*_amount*/
    )
        public
        virtual
        override
    {
        if (!enabled) return;

        // is this liquidation?
        // After transferring collateral, the user will always be insolvent.
        IERC4626 silo = IERC4626(IShareToken(msg.sender).silo());
        bool isLiquidation = !ISilo(address(silo)).isSolvent(_sender);

        if (isLiquidation && !_liquidationAllowed) revert LiquidationNotAllowed();
    }

    // TODO check allowances 
    // TODO should we adapt liquidation helper?
    // TODO should we adapt manual liquidation?
    function liquidationCall( // solhint-disable-line function-max-lines, code-complexity
        address _collateralAsset,
        address _debtAsset,
        address _borrower,
        uint256 _maxDebtToCover,
        bool _receiveSToken
    ) external virtual onlyAllowed returns (uint256 withdrawCollateral, uint256 repayDebtAssets) {
        require(_receiveSToken, STokenNotSupported());

        // we can also use maxLiquidation to get exact debt amount TODO
        DEBT_ASSET.safeTransferFrom(msg.sender, address(this), _maxDebtToCover);
        DEBT_ASSET.safeIncreaseAllowance(DEBT_SILO, _maxDebtToCover);

        _liquidationAllowed = true;

        (withdrawCollateral, repayDebtAssets) = IPartialLiquidation(HOOK_RECEIVER)
            .liquidationCall(_collateralAsset, _debtAsset, _borrower, _maxDebtToCover, _receiveSToken);

        _liquidationAllowed = false;

        _transferBalance(DEBT_ASSET);
        _transferBalance(COLLATERAL_ASSET);
    }

    function _transferBalance(IERC20 _token) internal {
        uint256 balance = _token.balanceOf(address(this));
        if (balance > 0) _token.safeTransfer(msg.sender, balance);
    }
}
