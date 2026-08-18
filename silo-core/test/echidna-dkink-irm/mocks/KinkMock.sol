// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DynamicKinkModel} from "silo-core/contracts/interestRateModel/kink/DynamicKinkModel.sol";

contract KinkMock is DynamicKinkModel {
    function calculateUtiliation(uint256 _collateralAssets, uint256 _debtAssets) public pure returns (int256) {
        return super._calculateUtiliation(_collateralAssets, _debtAssets);
    }
}
