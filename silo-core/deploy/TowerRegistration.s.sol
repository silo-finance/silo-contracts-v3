// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";

import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";

import {Tower} from "silo-core/contracts/utils/Tower.sol";
import {
    LiquidationHelper, ILiquidationHelper
} from "silo-core/contracts/utils/liquidationHelper/LiquidationHelper.sol";

import {CommonDeploy} from "./_CommonDeploy.sol";

/*
    FOUNDRY_PROFILE=core \
    forge script silo-core/deploy/TowerRegistration.s.sol:TowerRegistration \
    --ffi --rpc-url $RPC_BNB --broadcast
 */
contract TowerRegistration is CommonDeploy {
    function run() public {
        _register("SiloFactory", getDeployedAddress(SiloCoreContracts.SILO_FACTORY));

        _registerLiquidationHelper(AGGREGATOR_1INCH);
        _registerLiquidationHelper(AGGREGATOR_ODOS);
        _registerLiquidationHelper(AGGREGATOR_ENSO);
        _registerLiquidationHelper(AGGREGATOR_0X);

        _register("ManualLiquidationHelper", getDeployedAddress(SiloCoreContracts.MANUAL_LIQUIDATION_HELPER));

        _register("SiloLens", getDeployedAddress(SiloCoreContracts.SILO_LENS));
        _register("SiloLeverageRouterUsingSilo", getDeployedAddress(SiloCoreContracts.LEVERAGE_ROUTER));
    }

    function _registerLiquidationHelper(string memory _aggregator) internal {
        string memory contractName = _liquidationHelperName(_aggregator);
        address helper = getDeployedAddress(contractName);

        if (helper != address(0)) _register(contractName, helper);
        else console2.log("[TowerRegistration] %s is NOT deployed, no registration needed", contractName);
    }

    function _register(string memory _name, address _currentAddress) internal {
        Tower tower = Tower(getDeployedAddress(SiloCoreContracts.TOWER));
        address old = tower.coordinates(_name);

        if (old == _currentAddress) {
            console2.log("[TowerRegistration] %s up to date", _name);
        } else if (old == address(0)) {
            uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
            console2.log("[TowerRegistration] %s will be register at %s", _name, _currentAddress);

            vm.startBroadcast(deployerPrivateKey);

            tower.register(_name, _currentAddress);

            vm.stopBroadcast();
        } else {
            uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
            console2.log("[TowerRegistration] %s will be updated from %s to %s", _name, old, _currentAddress);

            vm.startBroadcast(deployerPrivateKey);

            tower.update(_name, _currentAddress);

            vm.stopBroadcast();
        }
    }

    function _liquidationHelperName(string memory _aggregator) internal pure returns (string memory) {
        return string.concat("LiquidationHelper_", _aggregator);
    }
}
