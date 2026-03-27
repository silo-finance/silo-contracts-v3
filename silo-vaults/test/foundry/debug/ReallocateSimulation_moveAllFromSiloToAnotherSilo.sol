// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";
import {IERC20Metadata} from "openzeppelin5/interfaces/IERC20Metadata.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {MarketAllocation, ISiloVault} from "../../../contracts/interfaces/ISiloVault.sol";

interface INative {
    function deposit() external payable;
}

contract ReallocateSimulation_moveAllFromSiloToAnotherSilo_Test is Test {
    uint8 decimals;
    string symbol;

    /*
        FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_skip_reallocate_fromSiloToSilo -vvv
    */
    function test_skip_reallocate_fromSiloToSilo() public {
        // CONFIG

        vm.createSelectFork(vm.envString("RPC_MAINNET"));

        ISiloVault vault = ISiloVault(0x5362D5086FDef73450145492a66F8EBF210c5B9C);

        IERC4626 fromSilo = IERC4626(0xCE6aB1c71981e79Cd30052C521c162674251018a);
        IERC4626 toSilo = IERC4626(0xe073BE79811469A5726fb74CE84317091626c35E);
        IERC20Metadata asset = IERC20Metadata(fromSilo.asset());

        // CONFIG END

        address multisig = vault.owner();

        console2.log("asset", asset.symbol());
        decimals = asset.decimals();
        symbol = asset.symbol();
        console2.log("vault owner (multisig)", multisig);

        MarketAllocation[] memory allocations = new MarketAllocation[](2);

        // TX simulation

        // 1h is for margin error when we will be running this tx
        vm.warp(block.timestamp + 1 hours);

        uint256 vaultAssets = _printVaultBalance(fromSilo, address(vault));
        require(vaultAssets > 0, "vault assets is 0 in fromSilo, we expect to move something");

        deal(address(asset), multisig, vaultAssets * 2);

        uint256 liquidity = ISilo(address(fromSilo)).getLiquidity();
        emit log_named_decimal_uint("liquidity", liquidity, decimals);

        //total debt
        uint256 totalDebt = ISilo(address(fromSilo)).getDebtAssets();
        emit log_named_decimal_uint("total debt", totalDebt, decimals);

        uint256 vaultShares = fromSilo.balanceOf(address(vault));
        emit log_named_decimal_uint("vault shares", vaultShares, decimals + 3);

        uint256 vaultTotalDepositAmount = fromSilo.previewRedeem(vaultShares);
        emit log_named_decimal_uint("vault total deposit amount", vaultTotalDepositAmount, decimals);

        uint256 amountToDeposit = vaultTotalDepositAmount - liquidity;
        emit log_named_decimal_uint("amount deposit", amountToDeposit, decimals);

        vm.prank(multisig);
        asset.approve(address(fromSilo), amountToDeposit);
        vm.prank(multisig);
        fromSilo.deposit(amountToDeposit, multisig);

        uint256 maxWithdraw = fromSilo.maxWithdraw(address(vault));

        uint256 missingAssets = maxWithdraw < vaultTotalDepositAmount ? vaultTotalDepositAmount - maxWithdraw : 0;
        emit log_named_decimal_uint("missing assets", missingAssets, decimals);

        if (missingAssets > 0) {
            vm.prank(multisig);
            asset.approve(address(fromSilo), missingAssets);
            vm.prank(multisig);
            fromSilo.deposit(missingAssets, multisig);

            amountToDeposit += missingAssets;
        }

        console2.log("\n-------------------------------- ");
        emit log_named_decimal_uint("\ntotal required deposit amount", amountToDeposit, decimals);
        console2.log("\n-------------------------------- ");

        allocations[0].market = fromSilo;
        allocations[0].assets = 0;

        allocations[1].market = toSilo;
        allocations[1].assets = type(uint256).max; // deposit all

        console2.log("allocation[0].market", address(fromSilo));
        console2.log("allocation[0].assets", allocations[0].assets);
        console2.log("allocation[1].market", address(toSilo));
        console2.log("allocation[1].assets", allocations[1].assets);

        _printVaultBalance(fromSilo, address(vault));
        _printVaultBalance(toSilo, address(vault));

        vm.prank(multisig);
        vault.reallocate(allocations);

        _printVaultBalance(fromSilo, address(vault));
        _printVaultBalance(toSilo, address(vault));

        liquidity = ISilo(address(fromSilo)).getLiquidity();
        emit log_named_decimal_uint("liquidity after reallocation", liquidity, decimals);

        console2.log("\n-------------------------------- multisig tx:\n");
        console2.log("1. approve USDC for silo ", address(fromSilo));
        emit log_named_decimal_uint(
            string.concat("2. deposit ", symbol, " amount to silo"), amountToDeposit, decimals
        );
        console2.log("\tthis amount should hold for ~1h");
        console2.log("3. execute reallocation tx: vault.reallocate(allocations);");
        _printAllocation(allocations);

        console2.log("\n\tthis data are calculated on block", block.number);
    }

    function _printVaultBalance(IERC4626 _silo, address _vault) internal returns (uint256 vaultAssets) {
        uint256 vaultShares = _silo.balanceOf(_vault);
        vaultAssets = _silo.convertToAssets(vaultShares);
        string memory siloLabel = IERC20Metadata(address(_silo)).symbol();

        emit log_named_decimal_uint(string.concat(siloLabel, " vault assets"), vaultAssets, decimals);
    }

    function _printAllocation(MarketAllocation[] memory _allocation) internal pure {
        // print in a way that can be copy pasted to the Safe multisig
        string memory allocations = "[";

        for (uint256 i; i < _allocation.length; ++i) {
            allocations = string.concat(
                allocations,
                "[\"",
                Strings.toHexString(address(_allocation[i].market)),
                "\",\"",
                Strings.toString(_allocation[i].assets),
                "\"]",
                i < _allocation.length - 1 ? "," : ""
            );
        }

        allocations = string.concat(allocations, "]");
        console2.log("\treallocation data:\n", allocations);
    }
}
