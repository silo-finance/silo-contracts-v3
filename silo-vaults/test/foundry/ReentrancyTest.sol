// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";

import {IERC1820Implementer} from "openzeppelin5/interfaces/IERC1820Implementer.sol";
import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {IIncentivesClaimingLogic} from "silo-vaults/contracts/interfaces/IIncentivesClaimingLogic.sol";
import {IIncentivesClaimingLogicFactory} from "silo-vaults/contracts/interfaces/IIncentivesClaimingLogicFactory.sol";
import {ISiloVault, MarketAllocation} from "../../contracts/interfaces/ISiloVault.sol";
import {ERC1820Registry} from "../../contracts/mocks/ERC1820Registry.sol";
import {ERC777Mock, IERC1820Registry} from "../../contracts/mocks/ERC777Mock.sol";
import {ErrorsLib} from "../../contracts/libraries/ErrorsLib.sol";

import {IntegrationTest} from "./helpers/IntegrationTest.sol";
import {TIMELOCK} from "./helpers/BaseTest.sol";

uint256 constant FEE = 0.1 ether; // 50%
bytes32 constant TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
bytes32 constant TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

/*
FOUNDRY_PROFILE=vaults_tests forge test --ffi --mc ReentrancyTest -vvv
*/
contract ReentrancyTest is IntegrationTest, IERC1820Implementer {
    address internal attacker = makeAddr("attacker");
    address internal someMarket = makeAddr("someMarket");

    ERC777Mock internal reentrantToken;
    ERC1820Registry internal registry;

    /// @dev Protected methods against reentrancy.
    enum ReenterMethod {
        None, // 0
        Redeem,
        Withdraw,
        Mint,
        Deposit,
        Reallocate,
        ClaimRewards,
        SetSupplyQueue,
        UpdateWithdrawQueue,
        AcceptCap
    }

    function setUp() public override {
        super.setUp();

        registry = new ERC1820Registry();

        registry.setInterfaceImplementer(address(this), TOKENS_SENDER_INTERFACE_HASH, address(this));
        registry.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));

        reentrantToken = new ERC777Mock(100_000, new address[](0), IERC1820Registry(address(registry)));

        idleMarket = _createNewMarket(address(collateralToken), address(reentrantToken));

        vault = siloVaultsFactory.createSiloVault(
            OWNER,
            TIMELOCK,
            address(reentrantToken),
            "SiloVault Vault",
            "MMV",
            bytes32(0),
            address(0),
            new IIncentivesClaimingLogic[](0),
            new IERC4626[](0),
            new IIncentivesClaimingLogicFactory[](0)
        );

        vm.startPrank(OWNER);
        vault.setCurator(CURATOR);
        vault.setIsAllocator(ALLOCATOR, true);
        vault.setFeeRecipient(FEE_RECIPIENT);
        vm.stopPrank();

        _setCap(idleMarket, type(uint184).max);
        _setFee(FEE);

        reentrantToken.approve(address(vault), type(uint256).max);

        vm.prank(SUPPLIER);
        reentrantToken.approve(address(vault), type(uint256).max);

        reentrantToken.setBalance(SUPPLIER, 100_000 ether); // SUPPLIER supplies 100_000e18 tokens to SiloVault.

        console2.log("Supplier starting with %s tokens.", loanToken.balanceOf(SUPPLIER));

        vm.prank(SUPPLIER);
        uint256 userShares = vault.deposit(100_000 ether, SUPPLIER);

        console2.log(
            "Supplier deposited %s loanTokens to SiloVault_no_timelock in exchange for %s shares.",
            vault.previewRedeem(userShares),
            userShares
        );
        console2.log("Finished setUp.");
    }

    function test777Reentrancy() public {
        reentrantToken.setBalance(attacker, 100_000); // Mint 100_000 tokens to attacker.
        reentrantToken.setBalance(address(this), 100_000); // Mint 100_000 tokens to the test contract.

        vm.startPrank(attacker);

        registry.setInterfaceImplementer(attacker, TOKENS_SENDER_INTERFACE_HASH, address(this)); // Set test contract
        // to receive ERC-777 callbacks.
        registry.setInterfaceImplementer(attacker, TOKENS_RECIPIENT_INTERFACE_HASH, address(this)); // Required "hack"
        // because done all in a single Foundry test.

        reentrantToken.approve(address(vault), 100_000);

        vm.stopPrank();

        // The test will try to reenter on the deposit.

        vault.deposit(uint256(ReenterMethod.Deposit), attacker);
        vault.deposit(uint256(ReenterMethod.Withdraw), attacker);
        vault.deposit(uint256(ReenterMethod.Mint), attacker);
        vault.deposit(uint256(ReenterMethod.Reallocate), attacker);
        vault.deposit(uint256(ReenterMethod.ClaimRewards), attacker);
        vault.deposit(uint256(ReenterMethod.SetSupplyQueue), attacker);
        vault.deposit(uint256(ReenterMethod.UpdateWithdrawQueue), attacker);
        vault.deposit(uint256(ReenterMethod.Redeem), attacker);

        vm.mockCall(
            address(someMarket),
            abi.encodeWithSelector(IERC4626.asset.selector),
            abi.encode(address(reentrantToken))
        );

        vm.prank(OWNER);
        vault.submitCap(IERC4626(someMarket), 100);

        vm.warp(block.timestamp + 1 weeks);

        vault.deposit(uint256(ReenterMethod.AcceptCap), attacker);

        // deposit some other amount to ensure the deposit works.

        vm.prank(attacker);
        vault.deposit(100, attacker);
    }

    function tokensToSend(address, address from, address to, uint256 amount, bytes calldata, bytes calldata) external {
        if ((from == attacker) && (amount == uint256(ReenterMethod.Deposit))) {
            vm.prank(attacker);
            vm.expectRevert(ErrorsLib.ReentrancyError.selector);
            vault.deposit(1, attacker);
        } else if ((from == attacker) && (amount == uint256(ReenterMethod.Withdraw))) {
            vm.prank(attacker);
            vm.expectRevert(ErrorsLib.ReentrancyError.selector);
            ISiloVault(to).withdraw(1, attacker, attacker);
        } else if ((from == attacker) && (amount == uint256(ReenterMethod.Mint))) {
            vm.prank(attacker);
            vm.expectRevert(ErrorsLib.ReentrancyError.selector);
            vault.mint(1, attacker);
        } else if ((from == attacker) && (amount == uint256(ReenterMethod.Reallocate))) {
            MarketAllocation[] memory allocations;
            vm.prank(OWNER);
            vm.expectRevert(ErrorsLib.ReentrancyError.selector);
            vault.reallocate(allocations);
        } else if ((from == attacker) && (amount == uint256(ReenterMethod.ClaimRewards))) {
            vm.expectRevert(ErrorsLib.ReentrancyError.selector);
            vault.claimRewards();
        } else if ((from == attacker) && (amount == uint256(ReenterMethod.SetSupplyQueue))) {
            IERC4626[] memory newSupplyQueue;
            vm.prank(OWNER);
            vm.expectRevert(ErrorsLib.ReentrancyError.selector);
            vault.setSupplyQueue(newSupplyQueue);
        } else if ((from == attacker) && (amount == uint256(ReenterMethod.UpdateWithdrawQueue))) {
            uint256[] memory indexes;
            vm.prank(OWNER);
            vm.expectRevert(ErrorsLib.ReentrancyError.selector);
            vault.updateWithdrawQueue(indexes);
        } else if ((from == attacker) && (amount == uint256(ReenterMethod.Redeem))) {
            vm.prank(attacker);
            vm.expectRevert(ErrorsLib.ReentrancyError.selector);
            vault.redeem(1, attacker, attacker);
        } else if ((from == attacker) && (amount == uint256(ReenterMethod.AcceptCap))) {
            vm.prank(OWNER);
            vm.expectRevert(ErrorsLib.ReentrancyError.selector);
            vault.acceptCap(IERC4626(someMarket));
        }
    }

    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata data,
        bytes calldata operatorData
    ) external {}

    function canImplementInterfaceForAddress(bytes32, address) external pure returns (bytes32) {
        // Required for ERC-777
        return keccak256(abi.encodePacked("ERC1820_ACCEPT_MAGIC"));
    }
}
