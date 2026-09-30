// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {SiloERC4626LibWithReentrancyIssue} from "./SiloERC4626LibWithReentrancyIssue.sol";
import {SiloStorageLib} from "silo-core/contracts/lib/SiloStorageLib.sol";

contract SiloERC4626LibConsumerVulnerable {
    uint256 public constant INITIAL_TOTAL = 100;

    constructor() {
        SiloStorageLib.getSiloStorage().totalAssets[ISilo.AssetType.Collateral] = INITIAL_TOTAL;
    }

    function deposit(
        address _token,
        address _depositor,
        uint256 _assets,
        uint256 _shares,
        address _receiver,
        IShareToken _collateralShareToken
    ) public {
        SiloERC4626LibWithReentrancyIssue.deposit(
            _token, _depositor, _assets, _shares, _receiver, _collateralShareToken
        );
    }

    function getTotalCollateral() public view returns (uint256) {
        return SiloStorageLib.getSiloStorage().totalAssets[ISilo.AssetType.Collateral];
    }
}
