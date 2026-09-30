// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {PartialLiquidation} from "silo-core/contracts/hooks/liquidation/PartialLiquidation.sol";

import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";

contract PartialLiquidationMock is PartialLiquidation {
    function isToAssetsConvertionError(bytes memory _error) external pure returns (bool) {
        return _isToAssetsConvertionError(_error);
    }

    function afterAction(address, uint256, bytes calldata) external {}

    function beforeAction(address, uint256, bytes calldata) external {}

    function initialize(ISiloConfig, bytes calldata) external {}
}

contract PartialLiquidationTest is Test {
    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_isToAssetsConvertionError
    */
    function test_isToAssetsConvertionError() public {
        PartialLiquidationMock partialLiquidation = new PartialLiquidationMock();

        bytes memory err = abi.encodeWithSelector(ISilo.ReturnZeroAssets.selector);
        assertTrue(partialLiquidation.isToAssetsConvertionError(err));

        err = abi.encodeWithSelector(IPartialLiquidation.NoCollateralToLiquidate.selector);
        assertFalse(partialLiquidation.isToAssetsConvertionError(err));
    }
}
