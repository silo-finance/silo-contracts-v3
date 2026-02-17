// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";

contract GetCollateralShareTokenAndAssetReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will revert only for wrong silo"));
        _ensureItWillRevertAsExpected();
    }

    function verifyReentrancy() external {
        _ensureItWillRevertAsExpected();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "getCollateralShareTokenAndAsset(address,uint8)";
    }

    function _ensureItWillRevertAsExpected() internal {
        ISiloConfig config = TestStateLib.siloConfig();

        address silo0 = address(TestStateLib.silo0());
        address silo1 = address(TestStateLib.silo1());
        address wrongSilo = makeAddr("Wrong silo");

        config.getCollateralShareTokenAndAsset(silo0, ISilo.CollateralType.Collateral);
        config.getCollateralShareTokenAndAsset(silo0, ISilo.CollateralType.Protected);

        config.getCollateralShareTokenAndAsset(silo1, ISilo.CollateralType.Collateral);
        config.getCollateralShareTokenAndAsset(silo1, ISilo.CollateralType.Protected);

        vm.expectRevert(ISiloConfig.WrongSilo.selector);
        config.getCollateralShareTokenAndAsset(wrongSilo, ISilo.CollateralType.Protected);
    }
}
