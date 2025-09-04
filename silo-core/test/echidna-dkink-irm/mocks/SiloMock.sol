// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IDynamicKinkModel} from "silo-core/contracts/interfaces/IDynamicKinkModel.sol";
import {IInterestRateModel} from "silo-core/contracts/interfaces/IInterestRateModel.sol";
import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";

/// @title SiloMock
/// @notice Mock Silo contract for testing DynamicKinkModel Interest Rate Model
/// @dev Implements only the utilizationData() function that DynamicKinkModel reads
contract SiloMock {
    /// @notice Storage for utilization data
    ISilo.UtilizationData private _utilizationData;
    IInterestRateModel private _irm;

    /// @notice Error thrown when deploying SiloDKinkMock without deploying IRM first
    error SiloMock__DeployIrmFirst();

    function setIRM(IInterestRateModel _irmInput) external {
        require(address(_irmInput) != address(0), SiloMock__DeployIrmFirst());
        require(address(_irm) == address(0), "already set");

        _irm = IInterestRateModel(address(_irmInput));
    }

    function deposit(uint128 _collateralAssets) external {
        console2.log("deposit(%s)", _collateralAssets);

        _utilizationData.collateralAssets += _collateralAssets;
    }

    function withdraw(uint128 _collateralAssets) external {
        console2.log("withdraw(%s)", _collateralAssets);

        _utilizationData.collateralAssets -= _collateralAssets;
        require(_ltv() <= 1e18, "we can only withdraw up to 100%");
    }

    /// @notice Set debt assets amount
    /// @param _debtAssets Amount of debt assets
    function borrow(uint128 _debtAssets) external {
        console2.log("borrow(%s)", _debtAssets);

        _utilizationData.debtAssets += _debtAssets;
        require(_ltv() <= 1e18, "we can only borrow up to 100%");
    }

    function repay(uint128 _debtAssets) external {
        console2.log("repay(%s)", _debtAssets);

        _utilizationData.debtAssets -= _debtAssets;
    }

    /// @notice Accrue interest is based on Silo logic, but we do not handle fractions
    function acrueInterest() external returns (uint256 rcomp) {
        console2.log("\nacrueInterest()");

        // Interest has already been accrued this block
        if (_utilizationData.interestRateTimestamp == block.timestamp) {
            console2.log("Interest has already been accrued this block");
            return 0;
        }

        // This is the first time, so we can return early and save some gas
        if (_utilizationData.interestRateTimestamp == 0) {
            console2.log("This is the first time, just update the timestamp");
            _utilizationData.interestRateTimestamp = uint64(block.timestamp);
            return 0;
        }

        rcomp = _irm.getCompoundInterestRateAndUpdate(
            _utilizationData.collateralAssets, _utilizationData.debtAssets, _utilizationData.interestRateTimestamp
        );

        console2.log("getCompoundInterestRateAndUpdate: rcomp %s", rcomp);

        if (rcomp > calculateMaxRcomp(block.timestamp)) {
            console2.log("rcomp CAP failed: %s", rcomp);
            assert(false);
        }

        if (rcomp == 0) {
            _utilizationData.interestRateTimestamp = uint64(block.timestamp);
            console2.log("rcomp == 0. no interest accrued");
            return 0;
        }

        uint256 accruedInterest;

        (
            _utilizationData.collateralAssets, _utilizationData.debtAssets,, accruedInterest
        ) = SiloMathLib.getCollateralAmountsWithInterest({
            _collateralAssets: _utilizationData.collateralAssets,
            _debtAssets: _utilizationData.debtAssets,
            _rcomp: rcomp,
            _daoFee: 0,
            _deployerFee: 0
        });

        console2.log("accruedInterest %s", accruedInterest);

        // update remaining contract state
        _utilizationData.interestRateTimestamp = uint64(block.timestamp);
    }

    // function doSiloAction(uint256 _collateralAssets, uint256 _debtAssets) external returns (uint256 rcomp) {
    //     acrueInterest();

    //     _utilizationData.collateralAssets = _collateralAssets;
    //     _utilizationData.debtAssets = _debtAssets;
    // } TODO uncomment once everything else will pass

    function calculateMaxRcomp(uint256 _blockTimestamp) public view returns (uint256) {
        return (_blockTimestamp - _utilizationData.interestRateTimestamp) 
            * uint256(IDynamicKinkModel(address(_irm)).RCOMP_CAP_PER_SECOND());
    }

    /// @notice Get utilization data
    /// @return The current utilization data
    function utilizationData() external view returns (ISilo.UtilizationData memory) {
        return _utilizationData;
    }

    function _ltv() internal view returns (uint256) {
        return _utilizationData.collateralAssets == 0 ? 0 : _utilizationData.debtAssets * 1e18 / _utilizationData.collateralAssets;
    }
}
