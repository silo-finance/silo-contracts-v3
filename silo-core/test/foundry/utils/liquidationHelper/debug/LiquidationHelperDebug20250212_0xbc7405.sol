// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import "silo-core/contracts/lib/Actions.sol";
import "silo-core/contracts/Silo.sol";

import {SiloLens} from "silo-core/contracts/SiloLens.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

/*
 FOUNDRY_PROFILE=core_test forge test --ffi --mc LiquidationHelperDebug20250113_0x0a25ac -vv

https://sonicscan.org/tx/0x0a25acfed112e7388a293d1e934b398ac097ce458cdae0bb2c8258b319494c73

USER IS SOLVENT


executeLiquidation(address, address, uint256, (address,address,address), (address,address,bytes)[])
#	Name	Type	Data
1	_flashLoanFrom	address	0xf55902DE87Bd80c6a35614b48d7f8B612a083C12
2	_debtAsset	address	0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38
3	_maxDebtToCover	uint256
608582362650680541
3	_liquidation.hook	address	0x6AAFD9Dd424541885fd79C06FDA96929CFD512f9
3	_liquidation.collateralAsset	address	0x29219dd400f2Bf60E5a23d13Be72B486D4038894
3	_liquidation.user	address	0x85204a5E932b69455822033F33E378DFF4Bb8960
4	_swapsInputs0x.sellToken	address	0x29219dd400f2Bf60E5a23d13Be72B486D4038894
4	_swapsInputs0x.allowanceTarget	address	0xaC041Df48dF9791B0654f1Dbbf2CC8450C5f2e9D
4	_swapsInputs0x.swapCallData	bytes
0x83bd37f9000129219dd400f2bf60e5a23d13be72b486d40388940001039e2fb66102314ce7b64ce5ce3e5183bc94ad380305c9490809154a2d067e908007ae140001b28ca7e465c452ce4252598e0bc96aeba553cf820001eedbfc66b751b5411c1c182d7c836d5044708441000124f1a7c0d05893182fd9443ea8835ffe2ce661c50000000003010203000301010001020019ff00000000000000000000000000000000000000eedbfc66b751b5411c1c182d7c836d504470844129219dd400f2bf60e5a23d13be72b486d4038894000000000000000000000000000000000000000000000000


*/
contract LiquidationHelperDebug20250113_0x0a25ac is Test {
    /*
    1. when was first attempt to liquidate this user?
    */
    function setUp() public {}

    /*
         TODO this can must be skip because foundry do not support Sonic network yet
    */
    function test_skip_debug_liquidationCall() public {
        address borrower = 0x85204a5E932b69455822033F33E378DFF4Bb8960;
        ISilo silo = ISilo(0xf55902DE87Bd80c6a35614b48d7f8B612a083C12);
        SiloLens lens = SiloLens(0xE05966aee69CeCD677a30f469812Ced650cE3b5E);

        uint256 notSolventBlock;

        uint256 offset = 140;

        uint256 blockToFork = 7686558; // (Feb-13-2025 11:08:05 AM +UTC)
        //        uint256 blockToFork = 7686422;  // (Feb-13-2025 11:07:04 AM +UTC)

        for (uint256 i = offset; i < offset + 10; i++) {
            vm.createSelectFork(vm.envString("RPC_SONIC"), blockToFork - i);

            console.log("block %s [-%s]", block.number, i);
            bool solvent = silo.isSolvent(borrower);
            emit log_named_string("solvent?", solvent ? "yes" : ">>>>>>>>>>> NO <<<<<<<");
            emit log_named_decimal_uint("getLtv", lens.getLtv(silo, borrower), 16);

            if (!solvent) {
                notSolventBlock = block.number;
            }
        }

        if (notSolventBlock != 0) {
            emit log_named_uint("notSolventBlock", notSolventBlock);
        }
        /*
        block -7686558 [0]
    solvent?: yes
    getLtv: 77.9999448987193596
    block -7686558 [1]
    solvent?: yes
    getLtv: 77.9999448987193596
    block -7686557 [2]
    solvent?: yes
    getLtv: 77.9999447742259131
    block -7686556 [3]
    solvent?: yes
    getLtv: 77.9999447742259131
    block -7686555 [4]
    solvent?: yes
    getLtv: 77.9999446497324666
    block -7686554 [5]
    solvent?: yes
    getLtv: 77.9999446497324666
    block -7686553 [6]
    solvent?: yes
    getLtv: 77.9999446497324666
    block -7686552 [7]
    solvent?: yes
    getLtv: 77.9999445252390204
    block -7686551 [8]
    solvent?: yes
    getLtv: 77.9999445252390204
    block -7686550 [9]
    solvent?: yes
    getLtv: 77.9999445252390204
        block 7686558 [-10]
    solvent?: yes
    getLtv: 77.9999448987193596
    block 7686548 [-11]
    solvent?: yes
    getLtv: 77.9999444007455744
    block 7686547 [-12]
    solvent?: yes
    getLtv: 77.9999444007455744
    block 7686546 [-13]
    solvent?: yes
    getLtv: 77.9999442762521286
    block 7686545 [-14]
    solvent?: yes
    getLtv: 77.9999442762521286
    block 7686544 [-15]
    solvent?: yes
    getLtv: 77.9999441517586830
    block 7686543 [-16]
    solvent?: yes
    getLtv: 77.9999440272652375
    block 7686542 [-17]
    solvent?: yes
    getLtv: 77.9999440272652375
    block 7686541 [-18]
    solvent?: yes
    getLtv: 77.9999440272652375
    block 7686540 [-19]
    solvent?: yes
    getLtv: 77.9999440272652375
        block 7686558 [-20]
    solvent?: yes
    getLtv: 77.9999448987193596
    block 7686538 [-21]
    solvent?: yes
    getLtv: 77.9999437782783473
    block 7686537 [-22]
    solvent?: yes
    getLtv: 77.9999437782783473
    block 7686536 [-23]
    solvent?: yes
    getLtv: 77.9999436537849026
    block 7686535 [-24]
    solvent?: yes
    getLtv: 77.9999436537849026
    block 7686534 [-25]
    solvent?: yes
    getLtv: 77.9999435292914579
    block 7686533 [-26]
    solvent?: yes
    getLtv: 77.9999435292914579
    block 7686532 [-27]
    solvent?: yes
    getLtv: 77.9999434047980135
    block 7686531 [-28]
    solvent?: yes
    getLtv: 77.9999434047980135
    block 7686530 [-29]
    solvent?: yes
    getLtv: 77.9999432803045693
    block 7686558 [-30]
    solvent?: yes
    getLtv: 77.9999448987193596
    block 7686528 [-31]
    solvent?: yes
    getLtv: 77.9999431558111252
    block 7686527 [-32]
    solvent?: yes
    getLtv: 77.9999431558111252
    block 7686526 [-33]
    solvent?: yes
    getLtv: 77.9999430313176815
    block 7686525 [-34]
    solvent?: yes
    getLtv: 77.9999429068242378
    block 7686524 [-35]
    solvent?: yes
    getLtv: 77.9999429068242378
    block 7686523 [-36]
    solvent?: yes
    getLtv: 77.9999429068242378
    block 7686522 [-37]
    solvent?: yes
    getLtv: 77.9999427823307945
    block 7686521 [-38]
    solvent?: yes
    getLtv: 77.9999426578373512
    block 7686520 [-39]
    solvent?: yes
    getLtv: 77.9999768738569969

        block 7686424 [-134]
    solvent?: yes
    getLtv: 77.9999717696237568
    block 7686423 [-135]
    solvent?: >>>>>>>>>>> NO <<<<<<<
    getLtv: 80.2744996785704974
    block 7686422 [-136]
    solvent?: >>>>>>>>>>> NO <<<<<<<
    getLtv: 80.2744996785704974
    block 7686421 [-137]
    solvent?: >>>>>>>>>>> NO <<<<<<<
    getLtv: 80.2744995504466936
    block 7686420 [-138]
    solvent?: >>>>>>>>>>> NO <<<<<<<
    getLtv: 80.2744995504466936
    block 7686419 [-139]
    solvent?: >>>>>>>>>>> NO <<<<<<<

        */
    }
}
