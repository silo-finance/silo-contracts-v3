// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {SiloCoreDeployments, SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";

import {SiloLittleHelper} from "../_common/SiloLittleHelper.sol";

/*
    forge test -vv --ffi --mc SiloCoreDeploymentsTest
*/
contract SiloCoreDeploymentsTest is SiloLittleHelper, Test {
    function setUp() public {
        AddrLib.init();
    }

    /*
    forge test -vv --ffi --mt test_get_exists_
    */
    function test_get_exists_anvil() public {
        _setUpLocalFixture();

        address factoryFromSilo0 = address(silo0.factory());
        address factoryFromSilo1 = address(silo1.factory());
        address deployedFactory = SiloCoreDeployments.get(SiloCoreContracts.SILO_FACTORY, ChainsLib.ANVIL_ALIAS);

        assertEq(factoryFromSilo0, factoryFromSilo1, "factoryFromSilo0 == factoryFromSilo1");
        assertEq(factoryFromSilo0, deployedFactory, "factoryFromSilo0 == deployedFactory");
    }

    function test_get_exists_sonic() public {
        address addr = SiloCoreDeployments.get(SiloCoreContracts.SILO_FACTORY, ChainsLib.SONIC_ALIAS);
        assertEq(addr, 0x55C5b74BC138C42dCb0deb206AE325a828Cd1372, "expect valid address Sonic");
    }

    function test_get_exists_arbitrum_one() public {
        address addr = SiloCoreDeployments.get(SiloCoreContracts.SILO_FACTORY, ChainsLib.ARBITRUM_ONE_ALIAS);
        assertEq(addr, 0x504B8ca9C664AFe72324388122caBAFb72F9269f, "expect valid address on Arbitrum");
    }

    function test_get_contractNotExists() public {
        address addr = SiloCoreDeployments.get("not.exist", ChainsLib.OPTIMISM_ALIAS);
        assertEq(addr, address(0), "expect to return 0");
    }

    function test_get_invalidNetwork() public {
        address addr = SiloCoreDeployments.get(SiloCoreContracts.SILO_FACTORY, "abcd");
        assertEq(addr, address(0), "expect to return 0");
    }

    /*
    forge test -vv --ffi --mt test_parseAddress
    */
    function test_parseAddress() public pure {
        assertEq(SiloCoreDeployments.parseAddress(""), address(0), "empty string");
        assertEq(SiloCoreDeployments.parseAddress("0x"), address(0), "0x string");

        assertEq(
            SiloCoreDeployments.parseAddress("0xb720078680Dc65B54568673410aBb81195E0812"),
            address(0),
            "not an address"
        );

        assertEq(
            SiloCoreDeployments.parseAddress("0xb720078680Dc65B54568673410aBb81195E08122"),
            address(0xb720078680Dc65B54568673410aBb81195E08122),
            "0x string"
        );
    }
}
