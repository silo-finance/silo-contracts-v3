// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC4626OracleFactoryDeploy} from "silo-oracles/deploy/erc4626/ERC4626OracleFactoryDeploy.sol";
import {ERC4626OracleFactory} from "silo-oracles/contracts/erc4626/ERC4626OracleFactory.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";

/*
FOUNDRY_PROFILE=oracles VAULT=savETH forge test -vv --ffi --mc ERC4626PriceManipulation
*/
contract ERC4626PriceManipulation is IntegrationTest {
    using SafeERC20 for IERC20;

    IERC4626 internal _vault = IERC4626(0xc8CF6D7991f15525488b2A83Df53468D682Ba4B0); // sUSDf - Ethereum

    ISiloOracle internal _erc4626Oracle;
    IERC20 internal _asset;
    string internal _ticker;
    string internal _vaultSymbol;
    string internal _assetSymbol;
    uint256 internal _vaultDecimals;
    uint256 internal _assetDecimals;
    address internal _attacker = makeAddr("attacker");

    function setUp() public {
        uint256 blockToFork = 23377000;
        vm.createSelectFork(vm.envString("RPC_MAINNET"), blockToFork);
        string memory vaultAddressString = vm.envOr("VAULT", string(""));

        AddrLib.init();

        if (bytes(vaultAddressString).length != 0) {
            _vault = IERC4626(AddrLib.getAddressSafe(ChainsLib.chainAlias(), vaultAddressString));
        }

        ERC4626OracleFactoryDeploy erc4626OracleFactoryDeploy = new ERC4626OracleFactoryDeploy();
        erc4626OracleFactoryDeploy.disableDeploymentsSync();
        ERC4626OracleFactory factory = ERC4626OracleFactory(erc4626OracleFactoryDeploy.run());

        _erc4626Oracle = factory.createERC4626Oracle(_vault, bytes32(0));

        _asset = IERC20(_erc4626Oracle.quoteToken());
        _vaultDecimals = IERC20Metadata(address(_vault)).decimals();
        _assetDecimals = IERC20Metadata(address(_asset)).decimals();

        _vaultSymbol = IERC20Metadata(address(_vault)).symbol();
        _assetSymbol = IERC20Metadata(address(_asset)).symbol();
        _ticker = string.concat(_vaultSymbol, "/", _assetSymbol);

        _logPrice("[setUp]Initial price");
        _logVaultSharesAndAssets();

        emit log_string("[setUp] end \n");
    }

    modifier priceDidNotChange() {
        uint256 initialPrice = _getPrice();
        _;
        uint256 finalPrice = _getPrice();

        string memory direction = initialPrice < finalPrice ? "increased" : "decreased";

        console2.log("[priceDidNotChange] check: ", initialPrice == finalPrice ? "PASS" : "FAILED");

        assertEq(
            initialPrice,
            finalPrice,
            string.concat("Price ", direction, ": ", vm.toString(initialPrice), " => ", vm.toString(finalPrice))
        );
    }

    /*
    VAULT=savETH FOUNDRY_PROFILE=oracles forge test --ffi --mt test_ERC4626PriceManipulation_donation -vv
    */
    function test_ERC4626PriceManipulation_donation() public {
        uint256 attackerBalance = _fundAttackerWithTotalAssets();

        uint256 priceBeforeDonation = _getPrice();

        vm.prank(_attacker);
        _asset.safeTransfer(address(_vault), attackerBalance);

        _logPrice("\tAfter 100% donation\n");
        _logVaultSharesAndAssets();

        uint256 priceAfterDonation = _getPrice();

        assertEq(priceBeforeDonation * 2, priceAfterDonation, "Expected price to double");
    }

    // FOUNDRY_PROFILE=oracles forge test --ffi --mt test_ERC4626PriceManipulation_deposit -vv
    function test_ERC4626PriceManipulation_deposit() public priceDidNotChange {
        uint256 attackerBalance = _fundAttackerWithTotalAssets();

        vm.prank(_attacker);
        _asset.approve(address(_vault), attackerBalance);

        vm.prank(_attacker);
        _vault.deposit(attackerBalance, address(_attacker));

        _logPrice("After 100% deposit");
        _logVaultSharesAndAssets();
    }

    // FOUNDRY_PROFILE=oracles forge test --ffi --mt test_ERC4626PriceManipulation_mint -vv
    function test_ERC4626PriceManipulation_mint() public priceDidNotChange {
        uint256 attackerBalance = _fundAttackerWithTotalAssets();

        vm.prank(_attacker);
        _asset.approve(address(_vault), attackerBalance);

        uint256 expectedShares = _vault.convertToShares(attackerBalance);

        vm.prank(_attacker);
        _vault.mint(expectedShares, address(_attacker));

        _logPrice("After 100% mint");
        _logVaultSharesAndAssets();
    }

    // FOUNDRY_PROFILE=oracles forge test --ffi --mt test_ERC4626PriceManipulation_deposit_and_withdraw -vv
    function test_ERC4626PriceManipulation_deposit_and_withdraw() public priceDidNotChange {
        uint256 attackerBalance = _fundAttackerWithTotalAssets();

        vm.prank(_attacker);
        _asset.approve(address(_vault), attackerBalance);

        vm.prank(_attacker);
        _vault.deposit(attackerBalance, address(_attacker));

        _logPrice("After 100% deposit");

        uint256 maxWithdraw = _vault.maxWithdraw(address(_attacker));
        assertNotEq(maxWithdraw, 0, "Max withdraw is 0");

        emit log_named_decimal_uint("Max withdraw", maxWithdraw, _assetDecimals);

        vm.prank(_attacker);
        _vault.withdraw(maxWithdraw, _attacker, _attacker);

        _logPrice("After 100% withdraw");

        _logVaultSharesAndAssets();
    }

    // FOUNDRY_PROFILE=oracles forge test --ffi --mt test_ERC4626PriceManipulation_mint_and_redeem -vv
    function test_ERC4626PriceManipulation_mint_and_redeem() public priceDidNotChange {
        uint256 attackerBalance = _fundAttackerWithTotalAssets();

        vm.prank(_attacker);
        _asset.approve(address(_vault), attackerBalance);

        uint256 expectedShares = _vault.convertToShares(attackerBalance);

        vm.prank(_attacker);
        _vault.mint(expectedShares, address(_attacker));

        _logPrice("After 100% mint");

        uint256 maxRedeem = _vault.maxRedeem(address(_attacker));
        assertNotEq(maxRedeem, 0, "Max redeem is 0");

        emit log_named_decimal_uint("Max redeem", maxRedeem, _assetDecimals);

        vm.prank(_attacker);
        _vault.redeem(maxRedeem, _attacker, _attacker);

        _logPrice("After 100% redeem");

        _logVaultSharesAndAssets();
    }

    // FOUNDRY_PROFILE=oracles forge test --ffi --mt test_ERC4626PriceManipulation_crossCheck_mint_withdraw -vv
    function test_ERC4626PriceManipulation_crossCheck_mint_withdraw() public priceDidNotChange {
        uint256 attackerBalance = _fundAttackerWithTotalAssets();

        vm.prank(_attacker);
        _asset.approve(address(_vault), attackerBalance);

        uint256 expectedShares = _vault.convertToShares(attackerBalance);

        vm.prank(_attacker);
        _vault.mint(expectedShares, address(_attacker));

        _logPrice("After 100% mint");

        uint256 maxWithdraw = _vault.maxWithdraw(address(_attacker));
        assertNotEq(maxWithdraw, 0, "Max withdraw is 0");

        emit log_named_decimal_uint("Max withdraw", maxWithdraw, _assetDecimals);

        vm.prank(_attacker);
        _vault.withdraw(maxWithdraw, _attacker, _attacker);

        _logPrice("After 100% withdraw");

        _logVaultSharesAndAssets();
    }

    // FOUNDRY_PROFILE=oracles forge test --ffi --mt test_ERC4626PriceManipulation_crossCheck_deposit_redeem -vv
    function test_ERC4626PriceManipulation_crossCheck_deposit_redeem() public priceDidNotChange {
        uint256 attackerBalance = _fundAttackerWithTotalAssets();

        vm.prank(_attacker);
        _asset.approve(address(_vault), attackerBalance);

        vm.prank(_attacker);
        _vault.deposit(attackerBalance, address(_attacker));

        _logPrice("After 100% deposit");

        uint256 maxRedeem = _vault.maxRedeem(address(_attacker));
        assertNotEq(maxRedeem, 0, "Max redeem is 0");

        emit log_named_decimal_uint("Max redeem", maxRedeem, _assetDecimals);

        vm.prank(_attacker);
        _vault.redeem(maxRedeem, _attacker, _attacker);

        _logPrice("After 100% redeem");

        _logVaultSharesAndAssets();
    }

    function _dealAsset(address _to, uint256 _amount) internal {
        deal(address(_asset), _to, _amount);
    }

    function _fundAttackerWithTotalAssets() internal returns (uint256 attackerBalance) {
        uint256 totalShares = _vault.totalSupply();
        uint256 totalAssets = _vault.convertToAssets(totalShares);

        _dealAsset(_attacker, totalAssets);

        attackerBalance = _asset.balanceOf(_attacker);
        assertEq(attackerBalance, totalAssets);
    }

    function _logPrice(string memory _prefix) internal {
        uint256 price = _getPrice();

        string memory namedAs = string.concat(_prefix, " ", _ticker);

        emit log_named_decimal_uint(namedAs, price, IERC20Metadata(address(_vault)).decimals());
    }

    function _logVaultSharesAndAssets() internal {
        uint256 totalShares = _vault.totalSupply();
        uint256 totalAssets = _vault.convertToAssets(totalShares);

        emit log_named_decimal_uint(
            string.concat("Vault ", _vaultSymbol, " total shares"), totalShares, _vaultDecimals
        );
        emit log_named_decimal_uint(
            string.concat("Vault ", _vaultSymbol, " total assets"), totalAssets, _assetDecimals
        );
    }

    function _getPrice() internal view returns (uint256 price) {
        price = _erc4626Oracle.quote(10 ** _vaultDecimals, address(_vault));
    }
}
