// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {SiloHookV2} from "./SiloHookV2.sol";

contract SiloHookV3 is SiloHookV2 {
    error NotSupported();

    function liquidationCall(
        address /*_collateralAsset*/,
        address /*_debtAsset*/,
        address /*_borrower*/,
        uint256 /*_maxDebtToCover*/,
        bool /*_receiveSToken*/
    )
        external
        virtual
        override
        returns (uint256 /*withdrawCollateral*/, uint256 /*repayDebtAssets*/) 
    {
        revert NotSupported();
    }

    function VERSION() external pure override returns (string memory) { // solhint-disable-line func-name-mixedcase
        return "SiloHookV3 4.4.0";
    }

    // solhint-disable-next-line func-name-mixedcase
    function LT_MARGIN_FOR_DEFAULTING() public pure override virtual returns (uint256) {
        return 0;
    }
}
