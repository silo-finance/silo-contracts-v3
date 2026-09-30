// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";
import {AddrKey} from "common/addresses/AddrKey.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {DexSwap} from "silo-core/contracts/utils/liquidationHelper/DexSwap.sol";

/*
FOUNDRY_PROFILE=core_test forge test --gas-price 1 --ffi -vv --mc DexSwapOdosSonicTest
*/
contract DexSwapOdosSonicTest is IntegrationTest {
    DexSwap dex; // solhint-disable-line var-name-mixedcase

    function setUp() public {
        uint256 blockToFork = 2838462;
        vm.createSelectFork(vm.envString("RPC_SONIC"), blockToFork);
        AddrLib.init();
        dex = new DexSwap(getAddress(AddrKey.ODOS_ROUTER));
    }

    function test_skip_fillQuote_StoWETH() public {
        address whale = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

        IERC20 sellToken = IERC20(getAddress(AddrKey.wS));
        vm.prank(whale);
        require(sellToken.transfer(address(dex), 50e18), "transfer failed");

        IERC20 buyToken = IERC20(getAddress(AddrKey.WETH));
        address allowanceTarget = getAddress(AddrKey.ODOS_ROUTER);

        uint256 wethBefore = buyToken.balanceOf(address(dex));
        assertEq(wethBefore, 0, "expect to have no WETH");

        // seller address in swap data: 5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f
        bytes memory swapCallData =
            hex"83bd37f90001039e2fb66102314ce7b64ce5ce3e5183bc94ad38000150c42deacd8fc9773493ed674b675be577f2634b0902b5e3af16b188000007257ed11a78e51e028f5c00018e7591e2919157A6BBE9E3defe0F1Ff793e65Ec1000000015615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f000000000301020300060101010201ff000000000000000000000000000000000000000000e45a270b10cfed62ba586d3f1b72b36989a623ba039e2fb66102314ce7b64ce5ce3e5183bc94ad38000000000000000000000000000000000000000000000000";
        dex.fillQuote(address(sellToken), allowanceTarget, swapCallData);

        assertEq(buyToken.balanceOf(address(dex)), 10535913188180254, "expect to have WETH");
        assertEq(sellToken.allowance(address(dex), allowanceTarget), 0, "allowance should be reset to 0");
    }
}
