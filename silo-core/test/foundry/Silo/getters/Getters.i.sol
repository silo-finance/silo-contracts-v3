// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISilo, ISiloConfig} from "silo-core/contracts/interfaces/ISilo.sol";
import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
    forge test -vv --ffi --mc GettersTest
*/
contract GettersTest is SiloLittleHelper, Test {
    using SiloLensLib for ISilo;

    ISiloConfig siloConfig;

    function setUp() public {
        siloConfig = _setUpLocalFixture();
    }

    /*
    forge test -vv --ffi --mt test_silo_getLiquidity
    */
    function test_silo_getLiquidity() public view {
        assertEq(silo0.getLiquidity(), 0, "no liquidity after deploy 0");
        assertEq(silo1.getLiquidity(), 0, "no liquidity after deploy 1");
    }

    /*
    forge test -vv --ffi --mt test_silo_getMaxLtv
    */
    function test_silo_getMaxLtv() public view {
        assertEq(silo0.getMaxLtv(), 0.75e18, "getMaxLtv 0");
        assertEq(silo1.getMaxLtv(), 0.85e18, "getMaxLtv 1");
    }

    /*
    forge test -vv --ffi --mt test_silo_getLt
    */
    function test_silo_getLt() public view {
        assertEq(silo0.getLt(), 0.85e18, "LT 0");
        assertEq(silo1.getLt(), 0.95e18, "LT 1");
    }

    /*
    forge test -vv --ffi --mt test_silo_asset
    */
    function test_silo_asset() public view {
        assertEq(silo0.asset(), address(address(token0)), "asset 0");
        assertEq(silo1.asset(), address(address(token1)), "asset 1");
    }

    /*
    forge test -vv --ffi --mt test_silo_getFeesAndFeeReceivers
    */
    function test_silo_getFeesAndFeeReceivers() public view {
        (address daoFeeReceiver, address deployerFeeReceiver, uint256 daoFee, uint256 deployerFee) =
            SILO_LENS.getFeesAndFeeReceivers(silo0);

        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        address deployer = vm.addr(deployerPrivateKey);

        assertEq(daoFeeReceiver, deployer, "daoFeeReceiver");
        assertEq(
            deployerFeeReceiver,
            address(0xdEDEDEDEdEdEdEDedEDeDedEdEdeDedEdEDedEdE),
            "deployerFeeReceiver/silo owner"
        );
        assertEq(daoFee, 0.15e18, "daoFee");
        assertEq(deployerFee, 0.1e18, "deployerFee");

        (daoFeeReceiver, deployerFeeReceiver, daoFee, deployerFee) = SILO_LENS.getFeesAndFeeReceivers(silo1);

        assertEq(daoFeeReceiver, deployer, "daoFeeReceiver 1");
        assertEq(
            deployerFeeReceiver,
            address(0xdEDEDEDEdEdEdEDedEDeDedEdEdeDedEdEDedEdE),
            "deployerFeeReceiver/silo owner 1"
        );
        assertEq(daoFee, 0.15e18, "daoFee 1");
        assertEq(deployerFee, 0.1e18, "deployerFee 1");
    }
}
