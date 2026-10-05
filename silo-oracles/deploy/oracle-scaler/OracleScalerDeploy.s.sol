// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {CommonDeploy} from "../CommonDeploy.sol";
import {SiloOraclesFactoriesContracts} from "../SiloOraclesFactoriesContracts.sol";
import {ERC4626OracleFactory} from "silo-oracles/contracts/erc4626/ERC4626OracleFactory.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {OracleScalerFactory} from "silo-oracles/contracts/scaler/OracleScalerFactory.sol";
import {OraclesDeployments} from "../OraclesDeployments.sol";

/*
FOUNDRY_PROFILE=oracles QUOTE_TOKEN=USDC \
    forge script silo-oracles/deploy/oracle-scaler/OracleScalerDeploy.s.sol \
    --ffi --rpc-url $RPC_PHAROS --broadcast --verify \
    --verifier-url $VERIFIER_URL_PHAROS --verifier blockscout

    resume verification:
    FOUNDRY_PROFILE=oracles QUOTE_TOKEN=USDC \
    forge script silo-oracles/deploy/oracle-scaler/OracleScalerDeploy.s.sol \
    --ffi --rpc-url $RPC_PHAROS --verify \
    --verifier-url $VERIFIER_URL_PHAROS --verifier blockscout \
    --resume --private-key $PRIVATE_KEY
 */
contract OracleScalerDeploy is CommonDeploy {
    string public quoteTokenKey;

    function setQuoteTokenKey(string memory _quoteTokenKey) public {
        quoteTokenKey = _quoteTokenKey;
    }

    function run() public returns (ISiloOracle oracle) {
        AddrLib.init();

        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        if (bytes(quoteTokenKey).length == 0) {
            quoteTokenKey = vm.envString("QUOTE_TOKEN");
        }

        address quoteToken = AddrLib.getAddress(quoteTokenKey);

        address factory = getDeployedAddress(SiloOraclesFactoriesContracts.ORACLE_SCALER_FACTORY);

        vm.startBroadcast(deployerPrivateKey);

        oracle = OracleScalerFactory(factory).createOracleScaler(quoteToken, bytes32(0));

        vm.stopBroadcast();

        string memory oracleName = string.concat("SCALER_", quoteTokenKey);

        OraclesDeployments.save(getChainAlias(), oracleName, address(oracle));
    }
}
