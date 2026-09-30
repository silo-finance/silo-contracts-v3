// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {SiloRouterV2Deploy} from "silo-core/deploy/SiloRouterV2Deploy.s.sol";
import {SiloRouterV2} from "silo-core/contracts/silo-router/SiloRouterV2.sol";
import {IPendleWrapperLike} from "silo-core/contracts/interfaces/IPendleWrapperLike.sol";
import {SiloRouterV2Implementation} from "silo-core/contracts/silo-router/SiloRouterV2Implementation.sol";
import {AddrKey} from "common/addresses/AddrKey.sol";

/*
FOUNDRY_PROFILE=core_test forge test --mc SiloRouterPendleLPTsTest --ffi -vv
 */
contract SiloRouterPendleLPTsTest is Test {
    SiloRouterV2 public router;
    IPendleWrapperLike public wrapper;
    IERC20 public pendleLPToken;
    address public depositor = makeAddr("Depositor");
    address public pendleLPWhale = 0xF6853c77a2452576EaE5af424975a101FfC47308;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_MAINNET"), 22722152); // forking block Jun 17 2025

        string memory chainAlias = ChainsLib.chainAlias();

        AddrLib.init();
        wrapper = IPendleWrapperLike(AddrLib.getAddressSafe(chainAlias, AddrKey.WRAPPER_LPT_eUSDe_14AUG25));
        pendleLPToken = IERC20(wrapper.LP());

        SiloRouterV2Deploy deployer = new SiloRouterV2Deploy();
        deployer.disableDeploymentsSync();
        router = deployer.run();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_wrapPendleLP --ffi -vv
     */
    function test_wrapPendleLP() public {
        assertEq(pendleLPToken.balanceOf(depositor), 0, "Expect to have no pendle LP tokens");
        assertEq(IERC20(address(wrapper)).balanceOf(depositor), 0, "Expect to have no wrapped pendle LP tokens");

        uint256 amount = 100e18;

        vm.prank(pendleLPWhale);
        require(pendleLPToken.transfer(depositor, amount), "transfer failed");

        assertEq(pendleLPToken.balanceOf(depositor), amount, "Expect to have 100 pendle LP tokens");

        vm.prank(depositor);
        pendleLPToken.approve(address(router), amount);

        bytes[] memory data = new bytes[](1);
        data[0] =
            abi.encodeCall(SiloRouterV2Implementation.wrapPendleLP, (wrapper, pendleLPToken, depositor, amount));

        vm.prank(depositor);
        router.multicall{value: 0}(data);

        assertEq(pendleLPToken.balanceOf(depositor), 0, "Expect to have no pendle LP tokens");
        assertEq(
            IERC20(address(wrapper)).balanceOf(depositor), amount, "Expect to have 100 wrapped pendle LP tokens"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_unwrapPendleLP --ffi -vv
     */
    function test_unwrapPendleLP() public {
        assertEq(pendleLPToken.balanceOf(depositor), 0, "Expect to have no pendle LP tokens");
        assertEq(IERC20(address(wrapper)).balanceOf(depositor), 0, "Expect to have no wrapped pendle LP tokens");

        uint256 amount = 100e18;

        vm.prank(pendleLPWhale);
        require(pendleLPToken.transfer(depositor, amount), "transfer failed");

        vm.prank(depositor);
        pendleLPToken.approve(address(wrapper), amount);

        vm.prank(depositor);
        wrapper.wrap(address(router), amount);

        assertEq(pendleLPToken.balanceOf(depositor), 0, "Expect to have no pendle LP tokens");
        assertEq(
            IERC20(address(wrapper)).balanceOf(address(router)),
            amount,
            "Expect to have 100 wrapped pendle LP tokens"
        );

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(SiloRouterV2Implementation.unwrapPendleLP, (wrapper, depositor, amount));

        vm.prank(depositor);
        router.multicall{value: 0}(data);

        assertEq(pendleLPToken.balanceOf(depositor), amount, "Expect to have 100 pendle LP tokens");
        assertEq(
            IERC20(address(wrapper)).balanceOf(address(router)), 0, "Expect to have no wrapped pendle LP tokens"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_unwrapAllPendleLP --ffi -vv
     */
    function test_unwrapAllPendleLP() public {
        assertEq(pendleLPToken.balanceOf(depositor), 0, "Expect to have no pendle LP tokens");
        assertEq(IERC20(address(wrapper)).balanceOf(depositor), 0, "Expect to have no wrapped pendle LP tokens");

        uint256 amount = 100e18;

        vm.prank(pendleLPWhale);
        require(pendleLPToken.transfer(depositor, amount), "transfer failed");

        vm.prank(depositor);
        pendleLPToken.approve(address(wrapper), amount);

        vm.prank(depositor);
        wrapper.wrap(address(router), amount);

        assertEq(pendleLPToken.balanceOf(depositor), 0, "Expect to have no pendle LP tokens");
        assertEq(
            IERC20(address(wrapper)).balanceOf(address(router)),
            amount,
            "Expect to have 100 wrapped pendle LP tokens"
        );

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(SiloRouterV2Implementation.unwrapAllPendleLP, (wrapper, depositor));

        vm.prank(depositor);
        router.multicall{value: 0}(data);

        assertEq(pendleLPToken.balanceOf(depositor), amount, "Expect to have 100 pendle LP tokens");
        assertEq(
            IERC20(address(wrapper)).balanceOf(address(router)), 0, "Expect to have no wrapped pendle LP tokens"
        );
    }
}
