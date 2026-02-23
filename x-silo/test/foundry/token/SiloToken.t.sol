// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";
import {SiloToken} from "x-silo/contracts/token/SiloToken.sol";
import {ERC20Burnable} from "openzeppelin5/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "openzeppelin5/access/Ownable2Step.sol";
import {ERC20Capped} from "openzeppelin5/token/ERC20/extensions/ERC20Capped.sol";
import {Pausable} from "gitmodules/openzeppelin-contracts-5/contracts/utils/Pausable.sol";
import {IERC20Errors} from "openzeppelin5/interfaces/draft-IERC6093.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {SiloTokenDeploy} from "x-silo/deploy/token/SiloTokenDeploy.s.sol";
import {ERC20Mock} from "openzeppelin5/mocks/token/ERC20Mock.sol";

contract SiloTokenTest is IntegrationTest {
    ERC20Burnable public constant SILO_V1 = ERC20Burnable(0x6f80310CA7F2C654691D1383149Fa1A57d8AB1f8);
    address public constant OWNER = 0xE8e8041cB5E3158A0829A19E014CA1cf91098554;
    address public constant SILO_V1_WHALE = 0xE641Dca2E131FA8BFe1D7931b9b040e3fE0c5BDc;
    uint256 public constant FORKING_BLOCK = 22395354;
    uint256 public constant CAP = 10**9 * 10**18;
    SiloToken token;

    function setUp() public {
        AddrLib.init();
        vm.createSelectFork(getChainRpcUrl(MAINNET_ALIAS), FORKING_BLOCK);

        AddrLib.setAddress("SILO", address(SILO_V1));
        AddrLib.setAddress("NEW_SILO_TOKEN_OWNER", address(OWNER));
        SiloTokenDeploy deployer = new SiloTokenDeploy();
        deployer.disableDeploymentsSync();
        token = SiloToken(deployer.run());
    }

    function test_constructor() public view {
        assertEq(token.owner(), OWNER);
        assertEq(address(token.SILO_V1()), address(SILO_V1));
        assertEq(token.cap(), CAP);
        assertEq(token.symbol(), "SILO");
        assertEq(token.name(), "Silo Token");
    }

    function test_constructor_revertsForZeroSilo() public {
        vm.expectRevert(SiloToken.InvalidSiloV1Address.selector);
        new SiloToken(OWNER, ERC20Burnable(token));

        ERC20Burnable mockInvalidToken = ERC20Burnable(address(new ERC20Mock()));

        vm.expectRevert(SiloToken.InvalidSiloV1Address.selector);
        new SiloToken(OWNER, mockInvalidToken);
    }

    function test_constructor_revertsForZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new SiloToken(address(0), SILO_V1);
    }

    function test_mint_happyPath() public {
        uint256 mintAmount = 10**18;
        uint256 whaleBalanceBefore = SILO_V1.balanceOf(SILO_V1_WHALE);
        assertEq(token.balanceOf(SILO_V1_WHALE), 0);

        _whaleMintsSelf(mintAmount);

        assertEq(whaleBalanceBefore - SILO_V1.balanceOf(SILO_V1_WHALE), mintAmount);
        assertEq(token.balanceOf(SILO_V1_WHALE), mintAmount);
    }

    function test_mint_failsNoApprove() public {
        vm.prank(SILO_V1_WHALE);
        vm.expectRevert("ERC20: burn amount exceeds allowance");
        token.mint(SILO_V1_WHALE, 1);
    }

    function test_mint_failsApproveButNoTokens() public {
        uint256 mintAmount = 10**18;
        assertEq(SILO_V1.balanceOf(address(this)), 0);

        SILO_V1.approve(address(token), mintAmount);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        token.mint(address(this), 1);
    }

    function test_mint_failsAboveCap() public {
        vm.prank(Ownable(address(SILO_V1)).owner());
        SiloToken(address(SILO_V1)).mint(address(this), CAP * 2);

        SILO_V1.approve(address(token), CAP + 1);
        token.mint(address(this), CAP);

        vm.expectRevert(abi.encodeWithSelector(ERC20Capped.ERC20ExceededCap.selector, CAP + 1, CAP));
        token.mint(address(this), 1);
    }

    function test_mint_failsRepeatedMint() public {
        vm.startPrank(SILO_V1_WHALE);
        SILO_V1.approve(address(token), type(uint256).max);
        token.mint(SILO_V1_WHALE, SILO_V1.balanceOf(SILO_V1_WHALE));
        
        assertEq(SILO_V1.balanceOf(SILO_V1_WHALE), 0);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        token.mint(SILO_V1_WHALE, 1);
        vm.stopPrank();
    }

    function test_mint_changesSupplies() public {
        uint256 mintAmount = 10**18;
        uint256 siloV1TotalSupplyBefore = SILO_V1.totalSupply();
        uint256 siloV2TotalSupplyBefore = token.totalSupply();

        _whaleMintsSelf(mintAmount);

        assertEq(token.totalSupply() - siloV2TotalSupplyBefore, mintAmount);
        assertEq(siloV1TotalSupplyBefore - SILO_V1.totalSupply(), mintAmount);
        assertEq(token.totalSupply() + SILO_V1.totalSupply(), siloV1TotalSupplyBefore + siloV2TotalSupplyBefore);
    }

    function test_mint_whenPausedMustFail() public {
        vm.prank(OWNER);
        token.pause();

        vm.prank(SILO_V1_WHALE);
        SILO_V1.approve(address(token), 1);

        vm.prank(SILO_V1_WHALE);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        token.mint(SILO_V1_WHALE, 1);
    }

    function test_transfer_whenPausedMustWork() public {
        uint256 mintAmount = 10**18;
        _whaleMintsSelf(mintAmount);

        vm.prank(OWNER);
        token.pause();

        address receiver = address(123);
        assertEq(token.balanceOf(receiver), 0);
        vm.prank(SILO_V1_WHALE);
        require(token.transfer(receiver, mintAmount), "transfer failed");
        assertEq(token.balanceOf(receiver), mintAmount);
    }

    function test_pause_onlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        token.pause();
    }

    function test_unpause_onlyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        token.unpause();
    }

    function test_pause_canUnpause() public {
        vm.prank(OWNER);
        token.pause();
        assertEq(token.paused(), true);

        vm.prank(OWNER);
        token.unpause();

        assertEq(token.paused(), false);
    }
    function test_unpause_canPause() public {
        assertEq(token.paused(), false);

        vm.prank(OWNER);
        token.pause();

        assertEq(token.paused(), true);
    }

    function test_burnFrom_failsWithNoApproval() public {
        uint256 mintAmount = 10**18;
        _whaleMintsSelf(mintAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(this),
                0,
                mintAmount
            )
        );

        token.burnFrom(SILO_V1_WHALE, mintAmount);
    }

    function test_burn() public {
        uint256 mintAmount = 10**18;
        _whaleMintsSelf(mintAmount);

        assertEq(token.balanceOf(SILO_V1_WHALE), mintAmount);
        vm.prank(SILO_V1_WHALE);
        token.burn(mintAmount);
        assertEq(token.balanceOf(SILO_V1_WHALE), 0);
    }

    function _whaleMintsSelf(uint256 _mintAmount) internal {
        vm.prank(SILO_V1_WHALE);
        SILO_V1.approve(address(token), _mintAmount);

        vm.prank(SILO_V1_WHALE);
        token.mint(SILO_V1_WHALE, _mintAmount);
    }
}
