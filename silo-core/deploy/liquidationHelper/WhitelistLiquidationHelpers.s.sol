// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {CommonDeploy} from "../_CommonDeploy.sol";
import {SiloCoreContracts, SiloCoreDeployments} from "silo-core/common/SiloCoreContracts.sol";
import {Whitelist} from "silo-core/contracts/hooks/_common/Whitelist.sol";

/*
    Grant ALLOWED_ROLE on deployed LiquidationHelper / ManualLiquidationHelper contracts
    to the liquidation bot EOAs. Must use the same PRIVATE_KEY as the helper deployer
    (constructor sets DEFAULT_ADMIN_ROLE to msg.sender).

    FOUNDRY_PROFILE=core \
        forge script silo-core/deploy/liquidationHelper/WhitelistLiquidationHelpers.s.sol \
        --ffi --rpc-url $RPC_MAINNET --broadcast
*/
contract WhitelistLiquidationHelpers is CommonDeploy {
    address internal constant BOT_1 = 0x1fF60e85852Ac73cd05B69A8B6641fc24A3FC011;
    address internal constant BOT_2 = 0xC04f84A02cC65f14f4e8C982a7a467EE88c5311e;
    address internal constant BOT_3 = 0xd3EC1026c9F911e201De4d52A667dC10bc3754d7;

    function run() public {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        string memory chainAlias = ChainsLib.chainAlias();

        address[] memory helpers = _collectHelpers({_chainAlias: chainAlias});
        address[] memory bots = _bots();

        console2.log("[WhitelistLiquidationHelpers] chain:", chainAlias);
        console2.log("[WhitelistLiquidationHelpers] helpers:", helpers.length);
        console2.log("[WhitelistLiquidationHelpers] bots:", bots.length);

        require(helpers.length != 0, "no liquidation helpers found in deployments");

        vm.startBroadcast(deployerPrivateKey);

        for (uint256 i; i < helpers.length; i++) {
            Whitelist helper = Whitelist(helpers[i]);
            bytes32 role = helper.ALLOWED_ROLE();

            for (uint256 j; j < bots.length; j++) {
                if (helper.hasRole({role: role, account: bots[j]})) {
                    console2.log("  already allowed", helpers[i], bots[j]);
                    continue;
                }

                helper.grantRole({role: role, account: bots[j]});
                console2.log("  granted", helpers[i], bots[j]);
            }
        }

        vm.stopBroadcast();
    }

    function _bots() internal pure returns (address[] memory bots) {
        bots = new address[](3);
        bots[0] = BOT_1;
        bots[1] = BOT_2;
        bots[2] = BOT_3;
    }

    function _collectHelpers(string memory _chainAlias) internal returns (address[] memory helpers) {
        string[] memory names = _candidateNames();
        address[] memory found = new address[](names.length);
        uint256 count;

        for (uint256 i; i < names.length; i++) {
            address addr = SiloCoreDeployments.get({_contract: names[i], _network: _chainAlias});
            if (addr == address(0)) continue;

            bool duplicate;
            for (uint256 j; j < count; j++) {
                if (found[j] == addr) {
                    duplicate = true;
                    break;
                }
            }
            if (duplicate) continue;

            found[count] = addr;
            console2.log("  helper", names[i], addr);
            count++;
        }

        helpers = new address[](count);
        for (uint256 i; i < count; i++) {
            helpers[i] = found[i];
        }
    }

    function _candidateNames() internal pure returns (string[] memory names) {
        names = new string[](7);
        names[0] = SiloCoreContracts.MANUAL_LIQUIDATION_HELPER;
        names[1] = SiloCoreContracts.LIQUIDATION_HELPER;
        names[2] = "LiquidationHelper_1INCH";
        names[3] = "LiquidationHelper_ODOS";
        names[4] = "LiquidationHelper_ENSO";
        names[5] = "LiquidationHelper_0x";
        names[6] = "LiquidationHelper_LI_FI";
    }
}
