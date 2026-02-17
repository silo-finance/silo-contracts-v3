// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {PriceFormatter} from "silo-core/deploy/lib/PriceFormatter.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

import {CommonDeploy} from "../CommonDeploy.sol";
import {OracleForQA} from "silo-oracles/contracts/oracleForQA/OracleForQA.sol";
import {OraclesDeployments} from "../OraclesDeployments.sol";

/*
ETHERSCAN_API_KEY=$ARBISCAN_API_KEY \
FOUNDRY_PROFILE=oracles \
BASE=wS \
QUOTE=USDC.e \
ADMIN=0x0000000000000000000000000000000000000000 \
INITIAL_PRICE=0.09e18 \
    forge script silo-oracles/deploy/oracleForQA/OracleForQADeploy.s.sol \
    --ffi --rpc-url $RPC_SONIC --broadcast --verify
 */
contract OracleForQADeploy is CommonDeploy {
    function run() public returns (OracleForQA oracle) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        AddrLib.init();

        address base = AddrLib.getAddress(vm.envString("BASE"));
        address quote = AddrLib.getAddress(vm.envString("QUOTE"));
        require(base != address(0), "Base address is not set");
        require(quote != address(0), "Quote address is not set");

        console2.log("Base %s address: %s", vm.envString("BASE"), base);
        console2.log("Quote %s address: %s", vm.envString("QUOTE"), quote);

        address admin = vm.envAddress("ADMIN");
        uint256 initialPrice = vm.envUint("INITIAL_PRICE");
        require(initialPrice != 0, "Initial price is not set");

        console2.log("Admin address: %s", admin);
        console2.log("Initial price: %s (%s)", PriceFormatter.formatPriceInE18(initialPrice), initialPrice);

        string memory bSymbol = IERC20Metadata(base).symbol();
        string memory qSymbol = IERC20Metadata(quote).symbol();

        vm.startBroadcast(deployerPrivateKey);

        oracle = new OracleForQA(base, quote, admin, initialPrice);

        vm.stopBroadcast();

        string memory oracleName = string.concat("OracleForQA_", bSymbol, "-", qSymbol);

        OraclesDeployments.save(getChainAlias(), oracleName, address(oracle));
    }
}
