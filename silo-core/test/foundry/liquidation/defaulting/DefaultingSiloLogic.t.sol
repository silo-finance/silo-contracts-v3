// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {SiloStorageLib} from "silo-core/contracts/lib/SiloStorageLib.sol";
import {DefaultingSiloLogic} from "silo-core/contracts/hooks/defaulting/DefaultingSiloLogic.sol";

/*
FOUNDRY_PROFILE=core_test forge test --ffi --mc DefaultingSiloLogicTest -vvv
*/
contract DefaultingSiloLogicTest is Test {
    address logic = address(new DefaultingSiloLogic());

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_deductDefaultedDebtFromCollateral_onlyChangesCollateralAssets -vvv
    */
    function test_deductDefaultedDebtFromCollateral_onlyChangesCollateralAssets(
        uint192 _daoAndDeployerRevenue,
        uint64 _interestRateTimestamp,
        ISilo.Fractions memory _fractions,
        uint256 _protectedAssets,
        uint256 _collateralAssets,
        uint256 _debtAssets,
        uint256 _assetsToRepay
    ) public {
        vm.assume(_collateralAssets >= _assetsToRepay);

        bool success = _common_deductDefaultedDebtFromCollateral(
            _daoAndDeployerRevenue,
            _interestRateTimestamp,
            _fractions,
            _protectedAssets,
            _collateralAssets,
            _debtAssets,
            _assetsToRepay
        );

        assertTrue(success, "deductDefaultedDebtFromCollateral should not revert");

        ISilo.SiloStorage storage $ = SiloStorageLib.getSiloStorage();

        assertEq(
            $.totalAssets[ISilo.AssetType.Collateral], _collateralAssets - _assetsToRepay, "collateralAssets deducted"
        );
    }

    function _common_deductDefaultedDebtFromCollateral(
        uint192 _daoAndDeployerRevenue,
        uint64 _interestRateTimestamp,
        ISilo.Fractions memory _fractions,
        uint256 _protectedAssets,
        uint256 _collateralAssets,
        uint256 _debtAssets,
        uint256 _assetsToRepay
    ) internal returns (bool success) {
        ISilo.SiloStorage storage $ = SiloStorageLib.getSiloStorage();
        $.daoAndDeployerRevenue = _daoAndDeployerRevenue;
        $.interestRateTimestamp = _interestRateTimestamp;
        $.fractions = _fractions;
        $.totalAssets[ISilo.AssetType.Protected] = _protectedAssets;
        $.totalAssets[ISilo.AssetType.Collateral] = _collateralAssets;
        $.totalAssets[ISilo.AssetType.Debt] = _debtAssets;

        // forge-lint: disable-next-line(asm-keccak256)
        bytes32 fractionsHash = keccak256(abi.encode(_fractions));

        console2.log("collateralAssets before", $.totalAssets[ISilo.AssetType.Collateral]);

        (success,) = logic.delegatecall(
            abi.encodeWithSelector(DefaultingSiloLogic.deductDefaultedDebtFromCollateral.selector, _assetsToRepay)
        );

        console2.log(" collateralAssets after", $.totalAssets[ISilo.AssetType.Collateral]);

        assertEq(fractionsHash, keccak256(abi.encode($.fractions)), "fractions should not change");
        assertEq($.daoAndDeployerRevenue, _daoAndDeployerRevenue, "daoAndDeployerRevenue should not change");
        assertEq($.interestRateTimestamp, _interestRateTimestamp, "interestRateTimestamp should not change");
        assertEq($.totalAssets[ISilo.AssetType.Protected], _protectedAssets, "protectedAssets should not change");
        assertEq($.totalAssets[ISilo.AssetType.Debt], _debtAssets, "debtAssets should not change");
    }
}
