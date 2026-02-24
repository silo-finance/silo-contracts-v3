// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

// solhint-disable no-console
import {console2} from "forge-std/console2.sol";

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {CommonDeploy} from "../CommonDeploy.sol";
import {PriceFormatter} from "silo-core/deploy/lib/PriceFormatter.sol";
import {SiloOraclesFactoriesContracts} from "../SiloOraclesFactoriesContracts.sol";
import {OraclesDeployments} from "../OraclesDeployments.sol";
import {ManageableOracleFactory} from "silo-oracles/contracts/manageable/ManageableOracleFactory.sol";
import {IManageableOracle} from "silo-oracles/contracts/interfaces/IManageableOracle.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";

/*
FOUNDRY_PROFILE=oracles UNDERLYING_ORACLE=CHAINLINK_ETH_USD BASE_TOKEN=wBTC TIMELOCK=86400 OWNER=DAO \
    forge script silo-oracles/deploy/manageable-oracle/ManageableOracleDeploy.s.sol \
    --ffi --rpc-url $RPC_SONIC --broadcast --verify

Env BASE_TOKEN and OWNER are address names (e.g. USDC, DAO) resolved to addresses via AddrLib.
Optional env: TIMELOCK (seconds, default 1 days), EXTERNAL_SALT (bytes32 hex, default 0).
OWNER env defaults to deployer (address from PRIVATE_KEY) when not set.
 */
error UnderlyingOracleNotFound();

contract ManageableOracleDeploy is CommonDeploy {
    function run() public returns (IManageableOracle manageableOracle) {
        AddrLib.init();

        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        address deployer = vm.addr(deployerPrivateKey);
        console2.log("deployer:", deployer);

        address underlyingOracle = AddrLib.getAddress(vm.envString("UNDERLYING_ORACLE"));
        address ownerAddr = AddrLib.getAddress(vm.envString("OWNER"));
        uint32 timelockVal = uint32(vm.envUint("TIMELOCK"));
        bytes32 externalSaltVal = vm.envBytes32("EXTERNAL_SALT");

        console2.log("externalSaltVal:");
        console2.logBytes32(externalSaltVal);

        address factoryAddress = getDeployedAddress(SiloOraclesFactoriesContracts.MANAGEABLE_ORACLE_FACTORY);
        ManageableOracleFactory factory = ManageableOracleFactory(factoryAddress);

        vm.startBroadcast(deployerPrivateKey);

        manageableOracle = factory.create(ISiloOracle(underlyingOracle), ownerAddr, timelockVal, externalSaltVal);

        vm.stopBroadcast();

        string memory oracleName = _getOracleName(address(manageableOracle));
        OraclesDeployments.save(getChainAlias(), oracleName, address(manageableOracle));

        _qa(address(manageableOracle));
    }

    function _getOracleName(address _oracle) internal view returns (string memory) {
        address quoteToken = ISiloOracle(_oracle).quoteToken();
        string memory baseSymbol = IERC20Metadata(IManageableOracle(_oracle).baseToken()).symbol();
        string memory quoteSymbol = IERC20Metadata(quoteToken).symbol();
        return string.concat("MANAGEABLE_ORACLE_", baseSymbol, "_", quoteSymbol);
    }
    function _qa(address _oracle) internal view returns (uint256 quote) {
        IERC20Metadata baseToken = IERC20Metadata(IManageableOracle(_oracle).baseToken());
        uint256 oneBaseToken = 10 ** baseToken.decimals();
        quote = ISiloOracle(_oracle).quote(oneBaseToken, address(baseToken));

        string memory baseSymbol = baseToken.symbol();
        string memory quoteSymbol = IERC20Metadata(ISiloOracle(_oracle).quoteToken()).symbol();

        console2.log("\nQA ------------------------------: %s\n", _oracle);
        console2.log("  Quote (%s, %s): ", PriceFormatter.formatPriceInE18(oneBaseToken), baseSymbol);
        console2.log("    ", PriceFormatter.formatPriceInE18(quote), quoteSymbol);
    }
}
