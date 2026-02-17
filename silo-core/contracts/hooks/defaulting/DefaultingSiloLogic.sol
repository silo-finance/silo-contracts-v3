// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import {SiloStorageLib} from "silo-core/contracts/lib/SiloStorageLib.sol";
import {DefaultingRepayLib} from "silo-core/contracts/hooks/defaulting/DefaultingRepayLib.sol";
import {IPartialLiquidationByDefaulting} from "silo-core/contracts/interfaces/IPartialLiquidationByDefaulting.sol";



/// @title DefaultingSiloLogic
/// @dev implements custom logic for Silo to do delegate calls
contract DefaultingSiloLogic {
    using Math for uint256;
    using Math for uint192;
    using SafeCast for uint256;

    /// @dev This is a copy of Silo.sol repay() function with this changes:
    /// - DefaultingRepayLib.actionsRepay() is used instead of Actions.repay()
    /// - returns shares and assets instead only shares
    function repayDebtByDefaulting(uint256 _assets, address _borrower) 
        external
        virtual
        returns (uint256 shares, uint256 assets) 
    {
        (assets, shares) = DefaultingRepayLib.actionsRepay({
            _assets: _assets,
            _shares: 0,
            _borrower: _borrower,
            _repayer: msg.sender
        });

        emit ISilo.Repay(msg.sender, _borrower, assets, shares);
    }

    function deductDefaultedDebtFromCollateral(uint256 _assetsToRepay) external virtual {
        ISilo.SiloStorage storage $ = SiloStorageLib.getSiloStorage();

        bool success;
        uint256 totalCollateralAssets = $.totalAssets[ISilo.AssetType.Collateral];

        // if underflow happens, $.totalAssets[ISilo.AssetType.Collateral] is set to 0 and success is false
        (success, $.totalAssets[ISilo.AssetType.Collateral]) = totalCollateralAssets.trySub(_assetsToRepay);
        uint256 deductedFromCollateral = _assetsToRepay;
        
        if (!success) {
            uint256 excessDebt = _assetsToRepay - totalCollateralAssets;
            deductedFromCollateral = totalCollateralAssets;
            (, uint256 revenue) = uint256($.daoAndDeployerRevenue).trySub(excessDebt);
            $.daoAndDeployerRevenue = revenue.toUint192();
        }

        emit IPartialLiquidationByDefaulting.DefaultingLiquidation(_assetsToRepay, deductedFromCollateral);
    }
}
