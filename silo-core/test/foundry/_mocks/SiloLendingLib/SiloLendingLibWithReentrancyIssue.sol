// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";
import {Rounding} from "silo-core/contracts/lib/Rounding.sol";
import {SiloStorageLib} from "silo-core/contracts/lib/SiloStorageLib.sol";

library SiloLendingLibWithReentrancyIssue {
    using SafeERC20 for IERC20;

    // deposit fn with reentrancy issue
    // original code can be found here:
    // https://github.com/silo-finance/silo-contracts-v3/blob/06378822519ad8f164e7c18a4d3f8954d773ce60/silo-core/contracts/lib/SiloLendingLib.sol#L133
    function repay(
        ISiloConfig.ConfigData memory _configData,
        uint256 _assets,
        uint256 _shares,
        address _borrower,
        address _repayer
    ) external returns (uint256 assets, uint256 shares) {
        ISilo.SiloStorage storage $ = SiloStorageLib.getSiloStorage();
        IShareToken debtShareToken = IShareToken(_configData.debtShareToken);
        uint256 totalDebtAssets = $.totalAssets[ISilo.AssetType.Debt];

        (assets, shares) = SiloMathLib.convertToAssetsOrToShares(
            _assets,
            _shares,
            totalDebtAssets,
            debtShareToken.totalSupply(),
            Rounding.REPAY_TO_ASSETS,
            Rounding.REPAY_TO_SHARES,
            ISilo.AssetType.Debt
        );

        // fee-on-transfer is ignored
        // If token reenters, no harm done because we didn't change the state yet.
        IERC20(_configData.token).safeTransferFrom(_repayer, address(this), assets);
        // subtract repayment from debt
        $.totalAssets[ISilo.AssetType.Debt] = totalDebtAssets - assets;
        // Anyone can repay anyone's debt so no approval check is needed. If hook receiver reenters then
        // no harm done because state changes are completed.
        debtShareToken.burn(_borrower, _repayer, shares);
    }
}
