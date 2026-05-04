// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";

import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {CommonDeploy} from "../_CommonDeploy.sol";
import {SiloIncentivesControllerDeployments} from "./SiloIncentivesControllerDeployments.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ProxyAdmin} from "openzeppelin5/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "openzeppelin5/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TransparentProxy} from "silo-core/contracts/utils/TransparentProxy.sol";

/*
    SILO=0xe394050D179b72197A458Fdfb962Ae69908Aa5A0 \
    IMPLEMENTATION=0x0000000000000000000000000000000000000001 \
    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/incentives-controller/PermissionedLiquidationControllerFactoryUpgrade.s.sol \
        --ffi --rpc-url $RPC_MAINNET --broadcast --verify
 */
contract PermissionedLiquidationControllerFactoryUpgrade is CommonDeploy {
    error InvalidImplementation();
    error ControllerNotFound();

    function run() public {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        address implementation = vm.envAddress("IMPLEMENTATION");
        require(implementation != address(0), InvalidImplementation());

        ISilo silo = ISilo(vm.envAddress("SILO"));
        ISiloConfig.ConfigData memory config = silo.config().getConfig(address(silo));

        address collateralController =
            SiloIncentivesControllerDeployments.get(ChainsLib.chainAlias(), config.collateralShareToken);
        address protectedController =
            SiloIncentivesControllerDeployments.get(ChainsLib.chainAlias(), config.protectedShareToken);

        require(collateralController != address(0), ControllerNotFound());
        require(protectedController != address(0), ControllerNotFound());

        vm.startBroadcast(deployerPrivateKey);

        _upgrade(collateralController, implementation);
        _upgrade(protectedController, implementation);

        vm.stopBroadcast();

        console2.log("Permissioned controller upgraded (collateral):", collateralController);
        console2.log("Permissioned controller upgraded (protected):", protectedController);
        console2.log("New implementation:", implementation);
        console2.log("Notifier:", IShareToken(address(silo)).hookReceiver());
    }

    function _upgrade(address _controllerProxy, address _newImplementation) internal {
        address proxyAdmin = TransparentProxy(payable(_controllerProxy)).getAdmin();

        ProxyAdmin(proxyAdmin)
            .upgradeAndCall(ITransparentUpgradeableProxy(payable(_controllerProxy)), _newImplementation, bytes(""));
    }
}
