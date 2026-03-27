// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {SiloOraclesContracts, SiloOraclesDeployments} from "silo-oracles/deploy/SiloOraclesContracts.sol";

/*
FOUNDRY_PROFILE=oracles forge test --ffi --mc CommonAddressesVirtualAssetsTest -vv
*/
contract CommonAddressesVirtualAssetsTest is Test {
    function setUp() public {
        AddrLib.init();
    }

    function test_CommonAddressesVirtualAssets_matchDeployments_mainnet() public {
        _assertVirtualAssetsMatch("mainnet");
    }

    function test_CommonAddressesVirtualAssets_matchDeployments_arbitrumOne() public {
        _assertVirtualAssetsMatch("arbitrum_one");
    }

    function test_CommonAddressesVirtualAssets_matchDeployments_optimism() public {
        _assertVirtualAssetsMatch("optimism");
    }

    function test_CommonAddressesVirtualAssets_matchDeployments_avalanche() public {
        _assertVirtualAssetsMatch("avalanche");
    }

    function test_CommonAddressesVirtualAssets_matchDeployments_bnb() public {
        _assertVirtualAssetsMatch("bnb");
    }

    function test_CommonAddressesVirtualAssets_matchDeployments_base() public {
        _assertVirtualAssetsMatch("base");
    }

    function test_CommonAddressesVirtualAssets_matchDeployments_okx() public {
        _assertVirtualAssetsMatch("okx");
    }
    
    function test_CommonAddressesVirtualAssets_matchDeployments_xdc() public {
        _assertVirtualAssetsMatch("xdc");
    }

    function test_CommonAddressesVirtualAssets_matchDeployments_sonic() public {
        _assertVirtualAssetsMatch("sonic");
    }

    function test_CommonAddressesVirtualAssets_matchDeployments_injective() public {
        _assertVirtualAssetsMatch("injective");
    }

    function _assertVirtualAssetsMatch(string memory chainAlias) internal {
        _assertOne(chainAlias, "SILO_VIRTUAL_USD", SiloOraclesContracts.SILO_VIRTUAL_ASSET_USD);
        _assertOne(chainAlias, "SILO_VIRTUAL_EUR", SiloOraclesContracts.SILO_VIRTUAL_ASSET_EUR);
        _assertOne(chainAlias, "SILO_VIRTUAL_BTC", SiloOraclesContracts.SILO_VIRTUAL_ASSET_BTC);
    }

    function _assertOne(string memory chainAlias, string memory commonKey, string memory deploymentContract) internal {
        address fromCommon = AddrLib.getAddressSafe(chainAlias, commonKey);
        address fromDeployments = SiloOraclesDeployments.get(deploymentContract, chainAlias);
        assertEq(fromCommon, fromDeployments, string.concat(chainAlias, ": mismatch for ", commonKey));
    }
}
