// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {IERC4626, IERC20} from "openzeppelin5/interfaces/IERC4626.sol";

import {ErrorsLib} from "../../../contracts/libraries/ErrorsLib.sol";
import {IdleVault} from "../../../contracts/IdleVault.sol";

import {IntegrationTest} from "../helpers/IntegrationTest.sol";

interface IBefore {
    function beforeDeposit() external;
}

contract ERC4626WithBeforeHook is IdleVault {
    IBefore hook;
    uint8 offset = 6; // default for idle

    constructor(IBefore _hook, IERC4626 _vault) IdleVault(address(_vault), _vault.asset(), "n", "s") {
        hook = _hook;
    }

    /// @inheritdoc IERC4626
    function deposit(uint256 _assets, address _receiver) public virtual override returns (uint256 shares) {
        hook.beforeDeposit();

        return super.deposit(_assets, _receiver);
    }

    function setOffset(uint8 _offset) external {
        require(totalSupply() == 0, "vault must be empty to set offset");

        offset = _offset;
    }
    
    function _decimalsOffset() internal view virtual override returns (uint8) {
        return offset;
    }
}

/*
 FOUNDRY_PROFILE=vaults_tests forge test --ffi --mc MarketLossTest -vvv
*/
contract MarketLossTest is IBefore, IntegrationTest {
    address attacker = makeAddr("attacker");
    uint256 donationAmount;

    function setUp() public virtual override {
        super.setUp();

        // previous idle market removal
        _setCapSimple(idleMarket, 0);
        emit log_named_address("old idleMarket", address(idleMarket));

        idleMarket = new ERC4626WithBeforeHook(this, vault);
        allMarkets[allMarkets.length - 1] = idleMarket;
        donationAmount = 0;
        emit log_named_address("NEW idleMarket", address(idleMarket));

        IERC4626[] memory supplyQueue = new IERC4626[](2);
        supplyQueue[0] = allMarkets[0];
        supplyQueue[1] = idleMarket;

        _setCapSimple(allMarkets[0], 1);
        _setCapSimple(idleMarket, type(uint128).max);

        vm.prank(ALLOCATOR);
        vault.setSupplyQueue(supplyQueue);

        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 2;
        indexes[1] = 1;
        vm.prank(ALLOCATOR);
        vault.updateWithdrawQueue(indexes);

        assertEq(vault.supplyQueueLength(), 2, "only 2 markets");
        assertEq(vault.withdrawQueueLength(), 2, "only 2 markets on withdraw");
        assertEq(address(vault.supplyQueue(1)), address(idleMarket), "ensure we have idle");

        assertEq(
            address(vault.withdrawQueue(0)),
            address(idleMarket),
            "ensure we have idle at begin, so when we withdraw, we do it from 'invalid` market first"
        );
    }

    function beforeDeposit() external {
        if (donationAmount == 0) return;

        emit log_named_uint("executing donation attack with amount", donationAmount);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        IERC20(idleMarket.asset()).transfer(address(idleMarket), donationAmount);
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mc MarketLossTest --mt test_idleVault_InflationAttackWithDonation -vvv
    */
    /// forge-config: vaults_tests.fuzz.runs = 10000
    function test_idleVault_InflationAttackWithDonation(
        uint64 _attackerDeposit,
        uint64 _supplierDeposit,
        uint64 _donation,
        uint8 _idleVaultOffset
    ) public {
        // case where we can NOT detect loss on market:
//        (uint64 _attackerDeposit,
//            uint64 _supplierDeposit,
//            uint64 _donation,
//            uint8 _idleVaultOffset) = (14652472, 7522162, 18446744073709551614, 6);

        _idleVault_InflationAttackWithDonation({
            _attackUsingHookBeforeDeposit: false,
            _attackerDeposit: _attackerDeposit,
            _supplierDeposit: _supplierDeposit,
            _donation: _donation,
            _idleVaultOffset: _idleVaultOffset,
            _acceptableLoss: vault.DEFAULT_LOST_THRESHOLD()
        });
    }

    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mc MarketLossTest --mt test_idleVault_hookAttackWithDonation -vvv
    */
    /// forge-config: vaults_tests.fuzz.runs = 10000
    function test_idleVault_hookAttackWithDonation(
        uint64 _attackerDeposit,
        uint64 _supplierDeposit,
        uint64 _donation,
        uint8 _idleVaultOffset
    ) public {
//        (uint64 _attackerDeposit,
//            uint64 _supplierDeposit,
//            uint64 _donation,
//            uint8 _idleVaultOffset) = (8707779, 9692708345249, 18446744073709551614, 0);

        _idleVault_InflationAttackWithDonation({
            _attackUsingHookBeforeDeposit: true,
            _attackerDeposit: _attackerDeposit,
            _supplierDeposit: _supplierDeposit,
            _donation: _donation,
            _idleVaultOffset: _idleVaultOffset,
            _acceptableLoss: vault.DEFAULT_LOST_THRESHOLD()
        });
    }

    function _idleVault_InflationAttackWithDonation(
        bool _attackUsingHookBeforeDeposit,
        uint64 _attackerDeposit,
        uint64 _supplierDeposit,
        uint64 _donation,
        uint8 _idleVaultOffset,
        uint256 _acceptableLoss
    ) public {
        vm.assume(uint256(_attackerDeposit) * _supplierDeposit * _donation != 0);
        vm.assume(_supplierDeposit >= 2);
        vm.assume(_idleVaultOffset <= 6);

        ERC4626WithBeforeHook(address(idleMarket)).setOffset(_idleVaultOffset);

        // we want some founds to go to idle market, so cap must be lower than supplier deposit
        _setCap(allMarkets[0], _supplierDeposit / 2);

        vm.prank(attacker);
        vault.deposit(_attackerDeposit, attacker);

        // we want cases where asset generates some shares
        vm.assume(vault.convertToShares(_supplierDeposit) != 0);

        // to avoid losses caused by rounding error, recalculate assets
        emit log_named_uint("original _supplierDeposit", _supplierDeposit);

        // here we have frontrun with donation
        if (_attackUsingHookBeforeDeposit) donationAmount = _donation;
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        else IERC20(idleMarket.asset()).transfer(address(idleMarket), _donation);

        vm.prank(SUPPLIER);

        emit log("SUPPLIER doing deposit");

        try vault.deposit(_supplierDeposit, SUPPLIER) returns (uint256 supplierShares) {
            // if did not revert, we expect no loss

            uint256 supplierWithdraw;

            emit log(".................................. SUPPLIER withdraw");
            supplierWithdraw = _vaultWithdrawAll(SUPPLIER);

            if (supplierWithdraw > _supplierDeposit) {
                emit log("there should be no gain for supplier on healthy markets, but we gain:");
                emit log_uint(supplierWithdraw - _supplierDeposit);
            }

            uint256 supplierLoss = _supplierDeposit < supplierWithdraw ? 0 : _supplierDeposit - supplierWithdraw;

            emit log_named_uint(" SUPPLIER deposit", _supplierDeposit);
            emit log_named_uint(" SUPPLIER shares", supplierShares);
            emit log_named_uint("SUPPLIER withdraw", supplierWithdraw);
            emit log_named_uint("    SUPPLIER loss", supplierLoss);

            uint256 supplierLostPercent = supplierLoss * 1e18 / _supplierDeposit;
            emit log_named_decimal_uint("supplierLostPercent", supplierLostPercent, 18);

            uint256 lostShares = vault.convertToShares(supplierLoss);
            emit log_named_uint("lostShares", lostShares);

            if (lostShares > 1) {
                assertLe(
                    supplierLoss,
                    _acceptableLoss,
                    "% is higher than THRESHOLD, we should detect"
                );
            } else {
                // if we only lost up to 1 share, it is because of precision error or rounding
            }
        } catch (bytes memory data) {
            emit log("deposit reverted for SUPPLIER");

            bytes4 errorType = bytes4(data);

            if (
                // AllCapsReached: in case we got 0 shares in idle because of price manipulation
                errorType == ErrorsLib.AllCapsReached.selector ||
                errorType == ErrorsLib.AssetLoss.selector ||
                errorType == ErrorsLib.ZeroShares.selector
            ) {
                // ok
            } else {
                revert("AssetLoss/ZeroShares is only acceptable revert here");
            }
        }
    }


    /*
    FOUNDRY_PROFILE=vaults_tests forge test --ffi --mt test_idleVault_InflationAttack_permanentLoss -vvv

    1. withdraw from idle
    2. inflate price
    3. deposit to idle (loss?): yes, it is the same as donation

    */
    function test_idleVault_InflationAttack_permanentLoss(
        uint64 _supplierDeposit, uint64 donation
    ) public {
//        (uint64 _supplierDeposit, uint64 donation) = (104637192540, 2730, 18446744073709551615);
        vm.assume(uint256(_supplierDeposit) * donation != 0);
        vm.assume(_supplierDeposit >= 2);

        emit log_named_uint("_supplierDeposit", _supplierDeposit);
        emit log_named_uint("donation", donation);

        // we want some founds to go to idle market, so cap must be lower than deposit
        _setCap(allMarkets[0], _supplierDeposit / 2);

        vm.prank(SUPPLIER);
        vault.deposit(_supplierDeposit, SUPPLIER);

        // simulate reallocation (withdraw from idle)
        vm.startPrank(address(vault));
        // when redeem uses full balance, ratio will be correct even on donation, because market will be empty
        // so we have to leave at least something in market, that's why -1
        uint256 idleAmount = idleMarket.redeem(idleMarket.balanceOf(address(vault)) - 1, address(vault), address(vault));
        vm.stopPrank();

        // inflate price, possible eg on before deposit
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        IERC20(idleMarket.asset()).transfer(address(idleMarket), donation);

        // simulate reallocation back
        vm.startPrank(address(vault));
        idleMarket.deposit(idleAmount, address(vault));
        vm.stopPrank();

        uint256 availableToRedeem = vault.balanceOf(SUPPLIER) - 1e6;
        vm.assume(vault.convertToAssets(availableToRedeem) != 0);

        vm.startPrank(SUPPLIER);
        uint256 supplierWithdraw = vault.redeem(availableToRedeem, SUPPLIER, SUPPLIER);
        vm.stopPrank();

        uint256 supplierDiff = supplierWithdraw > _supplierDeposit ? 0 : _supplierDeposit - supplierWithdraw;
        uint256 supplierLostPercent = supplierDiff * 1e18 / _supplierDeposit;
        emit log_named_uint("supplierLostPercent", supplierLostPercent);

        assertLe(
            supplierDiff,
            2, // NOTICE: 1 or 2 wei can be 50% loss for dust deposits
            "SUPPLIER should not lost (2 wei acceptable for rounding)"
        );
    }

    function _vaultWithdrawAll(address _user) internal returns (uint256 amount) {
        printUser(_user);
        vm.startPrank(_user);
        // we can use all shares instead of maxRedeem because maxRedeem can underestimate
        uint256 balance = vault.balanceOf(_user);
        emit log_named_uint("_vaultWithdrawAll", balance);
        if (balance == 0) return 0;

        amount = vault.redeem(balance, _user, _user);
        vm.stopPrank();
    }

    function printUser(address _user) internal {
        emit log_named_address("[printUser] user", _user);
        emit log_named_uint("[printUser] totalAssets", vault.totalAssets());
        emit log_named_uint("[printUser] total shares", vault.totalSupply());
        emit log_named_uint("[printUser] shares",  vault.balanceOf(_user));
        emit log_named_uint("[printUser] maxWithdraw (might be underestimated)",  vault.maxWithdraw(_user));
        emit log_named_uint("[printUser] maxRedeem (might be underestimated)",  vault.maxRedeem(_user));
    }
}
