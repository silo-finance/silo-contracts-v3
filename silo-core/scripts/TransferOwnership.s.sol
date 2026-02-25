// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Math} from "openzeppelin5/utils/math/Math.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";
import {Ownable2Step} from "openzeppelin5/access/Ownable2Step.sol";

import {console2} from "forge-std/console2.sol";

import {StdAssertions} from "forge-std/StdAssertions.sol";

import {AddrKey} from "common/addresses/AddrKey.sol";

import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {CommonDeploy} from "silo-core/deploy/_CommonDeploy.sol";
import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";
import {ISiloLens} from "silo-core/contracts/interfaces/ISiloLens.sol";
import {IMulticall3} from "silo-core/scripts/interfaces/IMulticall3.sol";
import {TokenHelper} from "silo-core/contracts/lib/TokenHelper.sol";
import {Rounding} from "silo-core/contracts/lib/Rounding.sol";
import {PriceFormatter} from "silo-core/deploy/lib/PriceFormatter.sol";

/*
you can run it via:
./silo-core/scripts/transferOwnership.sh

# arbitrum

FOUNDRY_PROFILE=core
  forge script silo-core/scripts/TransferOwnership.s.sol \
  --ffi --rpc-url $RPC_ARBITRUM --broadcast
*/
contract TransferOwnership is CommonDeploy, StdAssertions {
    function run() public {
        Ownable2Step factory = Ownable2Step(getDeployedAddress(SiloCoreContracts.SILO_FACTORY));
        Ownable2Step routerV2 = Ownable2Step(getDeployedAddress(SiloCoreContracts.SILO_ROUTER_V2));

        address newOwner = AddrLib.getAddressSafe(ChainsLib.chainAlias(), AddrKey.DAO);

        _transferOwnership(factory, newOwner);
        _transferOwnership(routerV2, newOwner);
    }

    function _transferOwnership(Ownable2Step _contract, address _newOwner) internal {
        address owner = _contract.owner();

        if (owner == _newOwner) {
            console2.log("Owner is already the DAO");
            return;
        }

        if (_contract.pendingOwner() == _newOwner) {
            console2.log("Pending owner is already the new owner for", address(_contract));
            return;
        }

        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        vm.startBroadcast(deployerPrivateKey);
        _contract.transferOwnership(_newOwner);
        vm.stopBroadcast();

        console2.log("contract: ", address(_contract));
        console2.log("Owner transferred to DAO, pending owner: ", _contract.pendingOwner());
        require(_contract.pendingOwner() == _newOwner, "Pending owner is not the new owner");
    }
}
