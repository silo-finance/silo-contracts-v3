// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";

import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {AddrKey} from "common/addresses/AddrKey.sol";

import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";

import {
    LiquidationHelper, ILiquidationHelper
} from "silo-core/contracts/utils/liquidationHelper/LiquidationHelper.sol";

import {CommonDeploy} from "./_CommonDeploy.sol";

/*
    FOUNDRY_PROFILE=core AGGREGATOR=ENSO \
        forge script silo-core/deploy/LiquidationHelperDeploy.s.sol:LiquidationHelperDeploy \
        --ffi --rpc-url $RPC_AVALANCHE \
        --broadcast --verify

    Resume verification:
    FOUNDRY_PROFILE=core AGGREGATOR=ODOS \
        forge script silo-core/deploy/LiquidationHelperDeploy.s.sol:LiquidationHelperDeploy \
        --ffi --rpc-url $RPC_MAINNET \
        --verify \
        --verifier blockscout \
        --private-key $PRIVATE_KEY \
        --resume

    NOTICE: remember to register it in Tower
*/
contract LiquidationHelperDeploy is CommonDeploy {
    address payable constant GNOSIS_SAFE_MAINNET = payable(0xE8e8041cB5E3158A0829A19E014CA1cf91098554);
    address payable constant GNOSIS_SAFE_AVALANCHE = GNOSIS_SAFE_MAINNET;
    address payable constant GNOSIS_SAFE_ARB = payable(0x865A1DA42d512d8854c7b0599c962F67F5A5A9d9);
    address payable constant GNOSIS_SAFE_OP = payable(0x468CD12aa9e9fe4301DB146B0f7037831B52382d);
    address payable constant GNOSIS_SAFE_SONIC = payable(0x7461d8c0fDF376c847b651D882DEa4C73fad2e4B);
    address payable constant GNOSIS_SAFE_INK = GNOSIS_SAFE_MAINNET;
    address payable constant GNOSIS_SAFE_BNB = GNOSIS_SAFE_MAINNET;
    address payable constant GNOSIS_SAFE_OKX = GNOSIS_SAFE_MAINNET;
    address payable constant GNOSIS_SAFE_BASE = GNOSIS_SAFE_MAINNET;

    function run() public virtual returns (address liquidationHelper) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        address nativeToken = _nativeToken();
        address exchangeProxy = _exchangeProxy();
        address payable tokenReceiver = _tokenReceiver();
        string memory deploymentFileName = _generateContractName();

        console2.log("[LiquidationHelperDeploy] AGGREGATOR: ", _envAggregator());
        console2.log("[LiquidationHelperDeploy] nativeToken(): ", nativeToken);
        console2.log("[LiquidationHelperDeploy] exchangeProxy: ", exchangeProxy);
        console2.log("[LiquidationHelperDeploy] tokenReceiver: ", tokenReceiver);
        console2.log("[LiquidationHelperDeploy] deployment name: ", deploymentFileName);

        vm.startBroadcast(deployerPrivateKey);

        liquidationHelper = address(new LiquidationHelper(nativeToken, exchangeProxy, tokenReceiver));

        vm.stopBroadcast();

        _registerDeployment(liquidationHelper, SiloCoreContracts.LIQUIDATION_HELPER, deploymentFileName);
    }

    function _exchangeProxy() internal returns (address exchangeProxy) {
        exchangeProxy = _resolveExchangeProxyAddress();

        require(
            exchangeProxy != address(0),
            string.concat(_envAggregator(), " exchangeProxy not set for `", ChainsLib.chainAlias(), "` blockchain")
        );
    }

    function _resolveExchangeProxyAddress() internal returns (address) {
        uint256 chainId = getChainId();

        if (chainId == ChainsLib.ANVIL_CHAIN_ID) return address(2);

        if (_isRequestedAggregator(AGGREGATOR_1INCH)) return AddrLib.getAddress(AddrKey.EXCHANGE_AGGREGATOR_1INCH);
        if (_isRequestedAggregator(AGGREGATOR_ODOS)) return AddrLib.getAddress(AddrKey.EXCHANGE_AGGREGATOR_ODOS);
        if (_isRequestedAggregator(AGGREGATOR_ENSO)) return AddrLib.getAddress(AddrKey.EXCHANGE_AGGREGATOR_ENSO);
        if (_isRequestedAggregator(AGGREGATOR_0X)) return AddrLib.getAddress(AddrKey.EXCHANGE_AGGREGATOR_0X);

        return address(0);
    }

    function _generateContractName() internal view returns (string memory contractName) {
        uint256 chainId = getChainId();

        if (chainId == ChainsLib.ANVIL_CHAIN_ID) return SiloCoreContracts.LIQUIDATION_HELPER;

        string memory mainPart = "LiquidationHelper_";

        if (_isRequestedAggregator(AGGREGATOR_1INCH)) return string.concat(mainPart, AGGREGATOR_1INCH);
        if (_isRequestedAggregator(AGGREGATOR_ODOS)) return string.concat(mainPart, AGGREGATOR_ODOS);
        if (_isRequestedAggregator(AGGREGATOR_ENSO)) return string.concat(mainPart, AGGREGATOR_ENSO);
        if (_isRequestedAggregator(AGGREGATOR_0X)) return string.concat(mainPart, AGGREGATOR_0X);

        revert("unknown aggregator");
    }

    function _isRequestedAggregator(string memory _aggregator) internal view returns (bool) {
        bytes32 cfgAggregator = keccak256(abi.encodePacked(_envAggregator()));
        return cfgAggregator == keccak256(abi.encodePacked(_aggregator));
    }

    function _envAggregator() internal view returns (string memory aggregator) {
        aggregator = vm.envOr(string("AGGREGATOR"), string(""));
    }

    function _tokenReceiver() internal returns (address payable) {
        uint256 chainId = getChainId();

        if (chainId == ChainsLib.ANVIL_CHAIN_ID) return payable(address(3));
        if (chainId == ChainsLib.OPTIMISM_CHAIN_ID) return GNOSIS_SAFE_OP;
        if (chainId == ChainsLib.ARBITRUM_ONE_CHAIN_ID) return GNOSIS_SAFE_ARB;
        if (chainId == ChainsLib.SONIC_CHAIN_ID) return GNOSIS_SAFE_SONIC;
        if (chainId == ChainsLib.INK_CHAIN_ID) return GNOSIS_SAFE_INK;
        if (chainId == ChainsLib.MAINNET_CHAIN_ID) return GNOSIS_SAFE_MAINNET;
        if (chainId == ChainsLib.AVALANCHE_CHAIN_ID) return GNOSIS_SAFE_AVALANCHE;
        if (chainId == ChainsLib.BNB_CHAIN_ID) return GNOSIS_SAFE_BNB;
        if (chainId == ChainsLib.OKX_CHAIN_ID) return GNOSIS_SAFE_OKX;
        if (chainId == ChainsLib.BASE_CHAIN_ID) return GNOSIS_SAFE_BASE;
        if (chainId == ChainsLib.INJECTIVE_CHAIN_ID) return payable(AddrLib.getAddress(AddrKey.DAO));

        revert(string.concat("[LiquidationHelperDeploy] tokenReceiver not set for ", ChainsLib.chainAlias()));
    }
}
