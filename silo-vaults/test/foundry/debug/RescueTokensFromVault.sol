// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {Ownable} from "openzeppelin5/access/Ownable.sol";
import {SiloVault} from "../../../contracts/SiloVault.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

import {IVaultIncentivesModule} from "../../../contracts/interfaces/IVaultIncentivesModule.sol";

import {RescueWAVAX} from "silo-vaults/contracts/utils/RescueWAVAX.sol";

/*
FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_rescue_tokens_from_vault -vvv
*/
contract RescueTokensFromVault is Test {
    address constant MULTISIG = 0xE8e8041cB5E3158A0829A19E014CA1cf91098554;
    SiloVault internal constant VAULT = SiloVault(0x6c09bfdc1df45D6c4Ff78Dc9F1C13aF29eB335d4);

    IVaultIncentivesModule internal incentivesModule;

    IERC20 internal wAvax = IERC20(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_AVALANCHE"), 70678297);
        console2.log("block number", block.number);

        incentivesModule = VAULT.INCENTIVES_MODULE();
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_rescue_tokens_from_vault -vvv
    */
    function test_rescue_tokens_from_vault() public {
        _qaVaultOperations();

        uint256 wAvaxDecimals = IERC20Metadata(address(wAvax)).decimals();
        console2.log("wAvax decimals", wAvaxDecimals);
        emit log_named_decimal_uint("wAvax VAULT balance", wAvax.balanceOf(address(VAULT)), wAvaxDecimals);
        console2.log("VAULT assets", VAULT.asset());
        console2.log("VAULT assets symbol", IERC20Metadata(VAULT.asset()).symbol());
        console2.log("VAULT timelock", VAULT.timelock());

        // we need to have access to owner of the incentivesModule
        address incentivesModuleOwner = Ownable(address(incentivesModule)).owner();
        console2.log("vault incentives module", address(incentivesModule));
        console2.log("incentives module owner", incentivesModuleOwner);

        RescueWAVAX newLogic = new RescueWAVAX();
        uint256 wAvaxBalanceBefore = wAvax.balanceOf(address(newLogic.WAVAX_RECEIVER()));
        console2.log("wAvax balance before", wAvaxBalanceBefore);

        // we need to call `submitIncentivesClaimingLogic` from safe
        vm.prank(incentivesModuleOwner);
        incentivesModule.submitIncentivesClaimingLogic(VAULT, newLogic);

        _qaVaultOperations();
        _printLigics();

        // we need to wait for the timelock to pass, because we not using trusted factory
        vm.warp(block.timestamp + VAULT.timelock());

        // anyone can accept the logic, so we can call it + claim rewards
        incentivesModule.acceptIncentivesClaimingLogic(VAULT, newLogic);

        _qaVaultOperations();

        // THIS WILL RESCUE TOKENS
        VAULT.claimRewards();

        assertEq(wAvax.balanceOf(address(VAULT)), 0, "wAvax should be rescued");

        uint256 wAvaxBalanceAfter = wAvax.balanceOf(address(newLogic.WAVAX_RECEIVER()));
        emit log_named_decimal_uint("wAvax balance after", wAvaxBalanceAfter, wAvaxDecimals);
        assertGt(wAvaxBalanceAfter - wAvaxBalanceBefore, 0, "wAvax balance should be greater than before");

        _qaVaultOperations();

        // then incentive module owner can remove the logic
        vm.prank(incentivesModuleOwner);
        incentivesModule.removeIncentivesClaimingLogic(VAULT, newLogic);

        assertEq(_printLigics(), 0, "no logics should be left");
        _qaVaultOperations();
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_add_remove_logic -vvv
    */
    function test_add_remove_logic() public {
        _qaVaultOperations();

        // we need to have access to owner of the incentivesModule
        address incentivesModuleOwner = Ownable(address(incentivesModule)).owner();
        console2.log("incentives module owner", incentivesModuleOwner);

        RescueWAVAX newLogic = new RescueWAVAX();
        uint256 wAvaxBalanceBefore = wAvax.balanceOf(address(newLogic.WAVAX_RECEIVER()));
        console2.log("wAvax balance before", wAvaxBalanceBefore);

        // we need to call `submitIncentivesClaimingLogic` from safe
        vm.prank(incentivesModuleOwner);
        incentivesModule.submitIncentivesClaimingLogic(VAULT, newLogic);

        _qaVaultOperations();
        _printLigics();

        vm.prank(incentivesModuleOwner);
        incentivesModule.revokePendingClaimingLogic(VAULT, newLogic);

        _qaVaultOperations();

        assertEq(_printLigics(), 0, "no logics should be left");
        _qaVaultOperations();
    }

    function _qaVaultOperations() internal {
        console2.log("\t ------- QA vault operations -------");
        VAULT.claimRewards(); // always work

        address usdtWhale = 0x5fA70a4D7635618afCE319e0F09c67a2Ec661c8b;
        IERC20 asset = IERC20Metadata(VAULT.asset());

        vm.prank(usdtWhale);
        asset.transfer(address(this), 100e6);

        asset.approve(address(VAULT), 100e6);
        VAULT.deposit(100e6, address(this));

        // NOTICE: we can not withdraw total amount of assets for unknown reason (reason not checked)
        VAULT.withdraw(VAULT.maxWithdraw(address(this)), address(this), address(this));

        VAULT.claimRewards(); // always work
    }

    function _printLigics() internal view returns (uint256 totalLogics) {
        address[] memory logics = incentivesModule.getAllIncentivesClaimingLogics();
        totalLogics = logics.length;
        console2.log("--------------------------------\nlogics length", totalLogics);

        for (uint256 i = 0; i < totalLogics; i++) {
            console2.log("logic", logics[i]);
        }
    }
}
