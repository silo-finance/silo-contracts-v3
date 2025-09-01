// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";
import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {SiloCoreContracts, SiloCoreDeployments} from "silo-core/common/SiloCoreContracts.sol";
import {CommonDeploy} from "./_CommonDeploy.sol";

import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";
import {ISiloDeployer} from "silo-core/contracts/interfaces/ISiloDeployer.sol";
import {IDynamicKinkModelFactory} from "silo-core/contracts/interfaces/IDynamicKinkModelFactory.sol";
import {IDynamicKinkModel} from "silo-core/contracts/interfaces/IDynamicKinkModel.sol";
import {IInterestRateModel} from "silo-core/contracts/interfaces/IInterestRateModel.sol";

import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";
import {InterestRateModelKinkConfigData} from "./input-readers/InterestRateModelKinkConfigData.sol";

/*
FOUNDRY_PROFILE=core CONFIG=empty MODEL_OWNER=0x0000000000000000000000000000000000000000 \
    forge script silo-core/deploy/KinkModelDeploy.s.sol \
    --ffi --rpc-url $RPC_SONIC --broadcast --verify
 */
contract KinkModelDeploy is CommonDeploy {
    string public configName;

    function run() public virtual returns (IInterestRateModel irm) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        console2.log("[KinkModelDeploy] run()");

        configName = bytes(configName).length == 0 ? vm.envString("CONFIG") : configName;
        console2.log("[KinkModelDeploy] using CONFIG: ", configName);

        InterestRateModelKinkConfigData modelData = new InterestRateModelKinkConfigData();

        IDynamicKinkModel.Config memory irmConfigData = modelData.getConfigData(configName);

        string memory chainAlias = ChainsLib.chainAlias();

        IDynamicKinkModelFactory kinkFactory = IDynamicKinkModelFactory(
            SiloCoreDeployments.get(SiloCoreContracts.DYNAMIC_KINK_MODEL_FACTORY, chainAlias)
        );
        
        if (address(kinkFactory) == address(0)) revert("[KinkModelDeploy] DynamicKinkModelFactory not deployed");

        address _initialOwner = _modelOwner();

        vm.startBroadcast(deployerPrivateKey);

        irm = kinkFactory.create(irmConfigData, _initialOwner);

        vm.stopBroadcast();

        console2.log("[KinkModelDeploy] deploy done, %s: %s with owner %s", configName, address(irm), _initialOwner);

        console2.log("[KinkModelDeploy] run() finished.");
    }

    function _modelOwner() internal virtual returns (address modelOwner) {
        modelOwner = vm.envAddress("MODEL_OWNER");
    }
}
