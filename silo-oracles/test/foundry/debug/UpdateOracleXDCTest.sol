// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {console2} from "forge-std/console2.sol";

import {
    ERC4626OracleWithUnderlyingFactoryDeploy
} from "../../../deploy/erc4626/ERC4626OracleWithUnderlyingFactoryDeploy.s.sol";
import {ERC4626OracleWithUnderlyingDeploy} from "../../../deploy/erc4626/ERC4626OracleWithUnderlyingDeploy.s.sol";
import {
    ERC4626OracleWithUnderlyingFactory
} from "silo-oracles/contracts/erc4626/ERC4626OracleWithUnderlyingFactory.sol";
import {ERC4626OracleWithUnderlying} from "silo-oracles/contracts/erc4626/ERC4626OracleWithUnderlying.sol";
import {SiloOraclesFactoriesContracts} from "silo-oracles/deploy/SiloOraclesFactoriesContracts.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626OracleWithUnderlying} from "silo-oracles/contracts/interfaces/IERC4626OracleWithUnderlying.sol";
import {IManageableOracle} from "silo-oracles/contracts/interfaces/IManageableOracle.sol";
import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {Aggregator} from "silo-oracles/contracts/_common/Aggregator.sol";

/*
    FOUNDRY_PROFILE=oracles forge test --mc UpdateOracleXDCTest --ffi -vv
*/
contract UpdateOracleXDCTest is Test {
    ERC4626OracleWithUnderlying oracle;
    address wstUSR;

    ERC4626OracleWithUnderlyingFactory factory;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_MEGAETH"), 15378649);

        AddrLib.init();

        factory = ERC4626OracleWithUnderlyingFactory(
            AddrLib.getAddress(SiloOraclesFactoriesContracts.ERC4626_ORACLE_UNDERLYING_FACTORY)
        );
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_skip_simulation --ffi -vv
     */
    function test_skip_simulation() public {
        console2.log("block number: ", block.number);
        IManageableOracle manageableOracle = IManageableOracle(0xe8c163ba02E589CD6Cd3eB738CBd3a13F208621C); // live
        uint256 t = manageableOracle.timelock();

        IERC4626 vault = IERC4626(makeAddr("vault"));
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
