// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

struct Loan {
    uint256 collateral; // shares of token staked
    uint256 borrowed; // user reward per token paid
    uint256 endDate;
    uint256 numberOfDays;
}

interface IEggs {
    function buy(address receiver) external payable;
    function burn(uint256 value) external;
    function sell(uint256 eggs) external;
    function borrow(uint256 sonic, uint256 numberOfDays) external;
    function SONICtoEGGS(uint256 value) external view returns (uint256);
    function EGGStoSONIC(uint256 value) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function liquidate() external;
    function Loans(address) external view returns (Loan memory);
    function getTotalCollateral() external view returns (uint256);
    function closePosition() external payable;
    function flashClosePosition() external payable;
    function leverage(uint256 sonic, uint256 numberOfDays) external payable;
}

// FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc EggsSonicPriceProvider
contract EggsSonicPriceProvider is IntegrationTest {
    IEggs internal _eggs = IEggs(0xf26Ff70573ddc8a90Bd7865AF8d7d70B8Ff019bC);
    address internal _eggsWhale = 0x66A8289bdD968D1157eB1a608f60a87759632cd6;

    function setUp() public {
        uint256 blockToFork = 10053279;
        vm.createSelectFork(vm.envString("RPC_SONIC"), blockToFork);
    }

    receive() external payable {}

    function test_EggsSonicPriceProvider_sell() public {
        uint256 priceBefore = _eggs.EGGStoSONIC(1e18);
        assertEq(priceBefore, 1136010235775762, "priceBefore");

        uint256 eggsAmount = _eggs.balanceOf(address(_eggsWhale));

        vm.prank(_eggsWhale);
        IERC20(address(_eggs)).transfer(address(this), eggsAmount);

        _eggs.sell(eggsAmount);

        uint256 priceAfter = _eggs.EGGStoSONIC(1e18);
        assertEq(priceAfter, 1136374922743370, "priceAfter");

        assertTrue(priceAfter > priceBefore, "Price should have increased");
    }

    function test_EggsSonicPriceProvider_burn() public {
        uint256 priceBefore = _eggs.EGGStoSONIC(1e18);
        uint256 eggsAmount = _eggs.balanceOf(address(_eggsWhale));

        vm.prank(_eggsWhale);
        _eggs.burn(eggsAmount);
        uint256 priceAfter = _eggs.EGGStoSONIC(1e18);

        assertTrue(priceAfter > priceBefore, "Price should have increased");
    }

    function test_EggsSonicPriceProvider_donationAttack() public {
        uint256 priceBefore = _eggs.EGGStoSONIC(1e18);
        require(payable(address(_eggs)).send(100000 ether));
        uint256 priceAfter = _eggs.EGGStoSONIC(1e18);

        assertTrue(priceAfter > priceBefore, "Price should have increased");
    }

    function test_EggsSonicPriceProvider_liquidate() public {
        uint256 collateralBefore = _eggs.getTotalCollateral();
        vm.warp(block.timestamp + 1 days);
        uint256 priceBefore = _eggs.EGGStoSONIC(1e18);
        _eggs.liquidate();
        uint256 priceAfter = _eggs.EGGStoSONIC(1e18);
        uint256 collateralAfter = _eggs.getTotalCollateral();

        assertTrue(priceAfter > priceBefore, "Price should have increased");
        assertTrue(collateralBefore > collateralAfter, "Collateral should have decreased");
    }

    function test_EggsSonicPriceProvider_leverage() public {
        uint256 priceBefore = _eggs.EGGStoSONIC(1e18);
        _eggs.leverage{value: 1000000}(1000000, 365);
        uint256 priceAfter = _eggs.EGGStoSONIC(1e18);

        assertTrue(priceAfter == priceBefore, "Price did not change");
    }

    function test_EggsSonicPriceProvider_buy() public {
        uint256 eggsAmount = _eggs.balanceOf(address(_eggsWhale));

        vm.prank(_eggsWhale);
        IERC20(address(_eggs)).transfer(address(this), eggsAmount);

        _eggs.sell(eggsAmount);

        uint256 priceBefore = _eggs.EGGStoSONIC(1e18);
        _eggs.buy{value: 1000000}(address(this));
        uint256 priceAfter = _eggs.EGGStoSONIC(1e18);

        assertTrue(priceAfter == priceBefore, "Price did not change");
    }

    function test_EggsSonicPriceProvider_borrow() public {
        uint256 priceBefore = _eggs.EGGStoSONIC(1e18);
        assertEq(priceBefore, 1136010235775762, "priceBefore");

        uint256 sonicAmount = 1000_000e18;
        uint256 eggsAmount = _eggs.balanceOf(address(_eggsWhale));

        vm.prank(_eggsWhale);
        IERC20(address(_eggs)).transfer(address(this), eggsAmount);

        _eggs.borrow(sonicAmount, 1);

        uint256 priceAfter = _eggs.EGGStoSONIC(1e18);
        assertEq(priceAfter, 1136019114778502, "priceAfter");

        assertTrue(priceAfter > priceBefore, "Price should have increased");
    }

    function test_EggsSonicPriceProvider_closePosition() public {
        uint256 sonicAmount = 1000_000e18;
        uint256 eggsAmount = _eggs.balanceOf(address(_eggsWhale));

        vm.prank(_eggsWhale);
        IERC20(address(_eggs)).transfer(address(this), eggsAmount);

        _eggs.borrow(sonicAmount, 1);

        uint256 priceBefore = _eggs.EGGStoSONIC(1e18);
        _eggs.closePosition{value: _eggs.Loans(address(this)).borrowed}();
        uint256 priceAfter = _eggs.EGGStoSONIC(1e18);

        assertTrue(priceAfter == priceBefore, "Price did not change");
    }
}
