// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {IManageableOracle} from "silo-oracles/contracts/interfaces/IManageableOracle.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {Aggregator} from "silo-oracles/contracts/_common/Aggregator.sol";

/*
    FOUNDRY_PROFILE=oracles forge test --mc UpdateOracleXDCTest --ffi -vv
*/
contract UpdateOracleXDCTest is Test {
    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_MEGAETH"), 15378649);
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_skip_simulation --ffi -vv
     */
    function test_skip_simulation() public {
        console2.log("block number: ", block.number);
        IManageableOracle manageableOracle = IManageableOracle(0xe8c163ba02E589CD6Cd3eB738CBd3a13F208621C); // live
        uint256 t = manageableOracle.timelock();

        ISiloOracle oracle = ISiloOracle(makeAddr("oracle"));

        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(ISiloOracle.quoteToken.selector),
            abi.encode(ISiloOracle(address(manageableOracle)).quoteToken())
        );
        
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(Aggregator.baseToken.selector),
            abi.encode(Aggregator(address(manageableOracle)).baseToken())
        );
        
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(Aggregator.quote.selector, 1e18, Aggregator(address(manageableOracle)).baseToken()),
            abi.encode(1)
        );

        vm.prank(manageableOracle.owner());
        manageableOracle.proposeOracle(oracle);

        vm.warp(block.timestamp + t);

        vm.prank(manageableOracle.owner());
        manageableOracle.acceptOracle();
    }
}
