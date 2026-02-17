// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {MintableToken} from "../../_common/MintableToken.sol";
import {CantinaTicket} from "./CantinaTicket.sol";

/*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc CantinaTicket148
*/
contract CantinaTicket148 is CantinaTicket {
    MintableToken internal WETH;
    MintableToken internal USDC;

    function setUp() public override {
        super.setUp();

        WETH = token0;
        USDC = token1;
    }

    function test_poc_ponzi() public {
        // Setup actors
        address alice = makeAddr("Alice");
        address bob = makeAddr("Bob");
        address seeder = makeAddr("Seeder");

        console.log("\n=== Step 1: Seed Initial WETH Liquidity ===");
        uint256 seedAmount = 100e18; // 100 WETH
        WETH.mint(seeder, seedAmount);
        vm.startPrank(seeder);
        WETH.approve(address(silo0), seedAmount);
        silo0.deposit(seedAmount, seeder, ISilo.CollateralType.Collateral);
        vm.stopPrank();

        console.log("Seeder deposited:", seedAmount, "WETH");
        console.log("Total WETH in Silo0 after Seeder deposit:", silo0.totalAssets());

        console.log("\n=== Step 2: Alice's Deposit ===");
        uint256 aliceDeposit = 1e15; // 0.001 WETH
        WETH.mint(alice, aliceDeposit);
        vm.startPrank(alice);
        WETH.approve(address(silo0), aliceDeposit);
        /* SILO: deposit chnaged to Collateral */
        silo0.deposit(aliceDeposit, alice, ISilo.CollateralType.Collateral);
        vm.stopPrank();

        console.log("Alice deposited:", aliceDeposit, "WETH");
        /* SILO: this is collateral balance not protected! */
        console.log("Alice's WETH shares in Silo0:", silo0.balanceOf(alice));

        console.log("\n=== Step 3: Seed USDC Liquidity ===");
        uint256 usdcLiquidity = 1_000_000e6; // 1M USDC
        USDC.mint(address(this), usdcLiquidity);
        USDC.approve(address(silo1), usdcLiquidity);
        silo1.deposit(usdcLiquidity, address(this), ISilo.CollateralType.Collateral);

        console.log("Contract deposited:", usdcLiquidity, "USDC into Silo1");
        console.log("Total USDC in Silo1 :", silo1.totalAssets());

        //oracle price for WETH
        /* SILO: this mock doing nothing, can be commented out */
        //        address oracle = siloConfig.getConfig(address(silo0)).maxLtvOracle;
        //        vm.mockCall(oracle, abi.encodeWithSignature("getPrice()"), abi.encode(2000e18)); // WETH = $2000
        //        console.log("Oracle price: WETH = $2000");

        console.log("\n=== Step 4: Alice's Borrow ===");
        uint256 aliceBorrow = 150_000e6; // 150k USDC
        vm.startPrank(alice);
        silo1.borrow(aliceBorrow, alice, alice);
        vm.stopPrank();

        console.log("Alice borrowed:", aliceBorrow, "USDC");
        console.log("Alice's USDC balance:", USDC.balanceOf(alice));
        console.log("Alice's debt in Silo1:", silo1.balanceOf(alice));

        console.log("\n=== Step 5: Bob's Deposit ===");
        uint256 bobDeposit = 1000e18; // 1000 WETH
        WETH.mint(bob, bobDeposit);
        vm.startPrank(bob);
        WETH.approve(address(silo0), bobDeposit);
        silo0.deposit(bobDeposit, bob, ISilo.CollateralType.Collateral);
        vm.stopPrank();

        console.log("Bob deposited:", bobDeposit, "WETH");
        console.log("Bob's WETH shares in Silo0:", silo0.balanceOf(bob));

        //        console.log("\n=== Step 6: Market Crash ===");
        //        vm.mockCall(
        //            oracle,
        //            abi.encodeWithSignature("getPrice()"),
        //            abi.encode(1000e18)
        //        );

        //        console.log("Oracle price updated: WETH = $1000");

        // Print detailed state
        console.log("\n=== Detailed State After Market Crash ===");
        console.log("Alice's WETH collateral:", silo0.balanceOf(alice));
        console.log("Alice's USDC debt:", silo1.balanceOf(alice));
        console.log("Alice's USDC balance:", USDC.balanceOf(alice));
        console.log("Bob's WETH shares:", silo0.balanceOf(bob));
        console.log("Bob's USDC balance:", USDC.balanceOf(bob));

        //Alice borrowed funds
        uint256 aliceProfit = USDC.balanceOf(alice);
        vm.startPrank(alice);
        USDC.transfer(address(this), aliceProfit);
        vm.stopPrank();

        console.log("Alice's profit:", aliceProfit);

        //Bob's loss
        /* SILO: assets mismatch with shared */
        //        uint256 bobFinalWETH = silo0.balanceOf(bob);
        uint256 bobFinalWETH = silo0.convertToAssets(silo0.balanceOf(bob));
        uint256 bobLoss = bobDeposit - bobFinalWETH;

        console.log("Bob's loss:", bobLoss);

        //prove
        assertTrue(aliceProfit > 0, "Alice USDC profit");
        assertTrue(bobLoss == 0, "Bob NOT lost WETH");
        assertTrue(silo1.balanceOf(alice) == 0, "Alice debt");
        /* SILO: convertToAsset to asset were missing */
        //        assertTrue(silo0.balanceOf(bob) < bobDeposit, "Bob WETH shares lost");
        assertTrue(silo0.convertToAssets(silo0.balanceOf(bob)) == bobDeposit, "Bob WETH shares NOT lost");
    }
}
