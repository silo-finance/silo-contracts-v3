// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IERC4626, IERC20} from "openzeppelin5/interfaces/IERC4626.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {MarketAllocation, ISiloVault} from "../../../contracts/interfaces/ISiloVault.sol";

interface INative {
    function deposit() external payable;
}

contract ReallocateSimulationTest is Test {
    
    /*
     FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_20250811_reallocate_simulation -vvv
    */
    function test_skip_20250811_reallocate_simulation() public {
        vm.createSelectFork(vm.envString("RPC_SONIC"), 42552900);

        ISiloVault vault = ISiloVault(0xDED4aC8645619334186f28B8798e07ca354CFa0e);

        IERC4626 fromSilo = IERC4626(0x8c98b43BF61F2B07c4D26f85732217948Fca2a90);
        IERC4626 toSilo = IERC4626(0x47d8490Be37ADC7Af053322d6d779153689E13C1);
        IERC20 wS = IERC20(0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38);
        address wSWhale = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

        address multisig = 0xd8454B3787c6Aab1cf2846AF7882f8c440C3903d;

        MarketAllocation[] memory allocations = new MarketAllocation[](2);

        // TX simulation


        uint256 vaultAssets = _printVaultBalance(fromSilo, address(vault));

        vm.prank(wSWhale); // give wS tokens to multisig
        wS.transfer(multisig, vaultAssets);


        console2.log("vault assets", vaultAssets / 1e18);

        uint256 amountToCoverDebt = 406629682203253781797819; //vaultAssets;

        // DEBUG:
        // amountToCoverDebt = 500e18;

        // INative(address(wS)).deposit{value: amountToCoverDebt}();

        // vm.prank(multisig);
        // wS.approve(address(fromSilo), amountToCoverDebt);
        vm.prank(multisig);
        fromSilo.deposit(amountToCoverDebt, multisig);

        uint256 maxWithdraw = fromSilo.maxWithdraw(address(vault));
        uint256 previewWithdraw = fromSilo.previewWithdraw(fromSilo.balanceOf(address(vault)));

        console2.log("            deposited", amountToCoverDebt / 1e18);
        console2.log("max withdraw by vault", maxWithdraw / 1e18);
        console2.log("preview withdraw", previewWithdraw / 1e18);

        uint256 debtToRepay = 45e18; // amountToCoverDebt - maxWithdraw + 10e18;
        console2.log("debt to repay", debtToRepay / 1e18);

        uint256 liquidity = ISilo(address(fromSilo)).getLiquidity();
        console2.log("liquidity", liquidity / 1e18);

        allocations[0].market = fromSilo;
        allocations[0].assets =  vaultAssets - liquidity + 20e18; // +1 to minimise risk of failing tx

        allocations[1].market = toSilo;
        allocations[1].assets = type(uint256).max; // deposit all

        console2.log("allocation[0].market", address(fromSilo));
        console2.log("allocation[0].assets", allocations[0].assets);
        console2.log("allocation[1].market", address(toSilo));
        console2.log("allocation[1].assets", allocations[1].assets);

        _printVaultBalance(fromSilo, address(vault));

        vm.prank(multisig);
        vault.reallocate(allocations);

        _printVaultBalance(fromSilo, address(vault));

        console2.log("\n-------------------------------- multisig tx:\n"); 
        console2.log("approve and deposit amount: ", amountToCoverDebt);
        console2.log("tokens: ", amountToCoverDebt / 1e18);
        _printAllocation(allocations);
    }

    function _printVaultBalance(IERC4626 _silo, address _vault) internal view returns (uint256 vaultAssets) {
        uint256 vaultShares = _silo.balanceOf(_vault);
        vaultAssets = _silo.convertToAssets(vaultShares);

        // console2.log("vault shares", vaultShares / 1e18);
        console2.log("vault assets", vaultAssets / 1e18);
    }

    function _printAllocation(MarketAllocation[] memory _allocation) internal pure {
        // print in a way that can be copy pasted to the Safe multisig
        string memory allocations = "[";

        for (uint256 i; i < _allocation.length; ++i) {
            allocations = string.concat(
                allocations,
                "[",
                Strings.toHexString(address(_allocation[i].market)),
                ", ",
                Strings.toString(_allocation[i].assets),
                "]",
                i < _allocation.length - 1 ? "," : ""
            );
        }

        allocations = string.concat(allocations, "]");
        console2.log("reallocation data:\n", allocations);
    }
}
