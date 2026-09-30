// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";

import {SiloLittleHelper} from "../_common/SiloLittleHelper.sol";

/*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc DustPropagationTest

    conclusions: 
    - when assets:shares are 1:1 there is no dust
    - not whole dust is propagated, offset makes it harder to distribute fully

*/
contract DustPropagationTest is SiloLittleHelper, Test {
    using SiloLensLib for ISilo;

    address constant BORROWER = address(0x123);
    uint256 constant COLLATERAL = 10e18;
    uint256 constant DEBT = 7.5e18;
    bool constant SAME_TOKEN = true;
    uint256 constant DUST_LEFT = 4;

    ISiloConfig siloConfig;

    /*
    this test is based on: test_liquidationCall_badDebt_partial_noDepositors
    */
    function setUp() public {
        siloConfig = _setUpLocalFixture();

        _printState("initial state");

        // provide liquidity to silo0
        token0.mint(address(this), COLLATERAL);
        token0.approve(address(silo0), COLLATERAL);
        silo0.deposit(COLLATERAL, address(this));

        // we cresting debt on silo0, because lt there is 85 and in silo0 95, so it is easier to test because of dust
        vm.startPrank(BORROWER);
        token1.mint(BORROWER, COLLATERAL);
        token1.approve(address(silo1), COLLATERAL);
        silo1.deposit(COLLATERAL, BORROWER);
        silo0.borrow(DEBT, BORROWER, BORROWER);
        vm.stopPrank();

        uint256 timeForward = 120 days;
        vm.warp(block.timestamp + timeForward);
        assertGt(silo0.getLtv(BORROWER), 1e18, "expect bad debt");
        assertEq(silo0.getLiquidity(), 0, "with bad debt and no depositors, no liquidity");
        _printState("after time forward");

        (, uint256 debtToRepay,) = partialLiquidation.maxLiquidation(BORROWER);

        token0.mint(address(this), debtToRepay);
        token0.approve(address(partialLiquidation), debtToRepay);
        bool receiveSToken;

        partialLiquidation.liquidationCall(address(token1), address(token0), BORROWER, debtToRepay, receiveSToken);
        _printState("after liquidation");

        assertTrue(silo0.isSolvent(BORROWER), "user is solvent after liquidation");

        silo0.withdrawFees();
        uint256 maxRedeem = silo0.maxRedeem(address(this));
        emit log_named_uint("maxRedeem for liquidity provider", maxRedeem);
        if (maxRedeem != 0) silo0.redeem(maxRedeem, address(this), address(this));

        _printState("after withdrawFees");

        ISiloConfig.ConfigData memory configData = siloConfig.getConfig(address(silo0));

        assertEq(IShareToken(configData.debtShareToken).totalSupply(), 0, "expected debtShareToken burned");
        // We have 1 wei leftover because of the rounding policy.
        // We round down when converting to shares on liquidation.
        assertEq(IShareToken(configData.protectedShareToken).totalSupply(), 0, "expected protectedShareToken 0");
        assertEq(silo0.getDebtAssets(), 0, "total debt == 0");

        assertEq(token0.balanceOf(address(silo0)), DUST_LEFT, "no balance after withdraw fees (except dust!)");

        assertEq(silo0.getTotalAssetsStorage(ISilo.AssetType.Collateral), DUST_LEFT, "storage AssetType.Collateral");

        assertEq(silo0.getCollateralAssets(), DUST_LEFT, "total collateral == 4, dust!");

        assertEq(silo0.getLiquidity(), DUST_LEFT, "getLiquidity == 4, dust!");

        emit log_named_uint("there is no users in silo, but balance is", token0.balanceOf(address(silo0)));

        emit log_named_uint(
            "IShareToken(configData.collateralShareToken).totalSupply()",
            IShareToken(configData.collateralShareToken).totalSupply()
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_dustPropagation_oneUser
    */
    function test_dustPropagation_oneUser() public {
        address user1 = makeAddr("user1");

        emit log_named_uint("total supply", silo0.totalSupply());
        emit log_named_uint("liquidity", silo0.getLiquidity());

        /*
            user must deposit at least dust + 1, because otherwise math revert with zeroShares
            situation is like this: we have 0 shares, and 4 assets, to get 1 share, min of 5 assets is required
            so we have situation where assets > shares from begin, not only after interest
            and looks like this dust will be locked forever in Silo because in our SiloMathLib we have:

            unchecked {
                // I think we can afford to uncheck +1
                (totalShares, totalAssets) = _assetType == ISilo.AssetType.Debt
                    ? (_totalShares, _totalAssets)
                    : (_totalShares + _DECIMALS_OFFSET_POW, _totalAssets + 1);
            }

            if (totalShares == 0 || totalAssets == 0) return _assets;

            ^ we never enter into this `if` for non debt assets, because we always adding +1 for both variables
            and this is why this dust will be forever locked in silo.
            Atm the only downside I noticed: it creates "minimal deposit" situation in some cases
        */
        uint256 shares1 = _deposit(1, user1);
        emit log_named_uint("[user1] shares1", shares1);
        emit log_named_uint("total supply", silo0.totalSupply());
        emit log_named_uint("liquidity", silo0.getLiquidity());

        // +1 because we underestimated for fractions in maxWithdraw function
        assertEq(
            silo0.maxWithdraw(user1) + 1, 3, "[user1] maxWithdraw 3 - more than deposit, because dust was propagated"
        );

        shares1 += _deposit(1, user1);
        emit log_named_uint("[user1] shares1 #2", shares1);
        emit log_named_uint("total supply #2", silo0.totalSupply());
        emit log_named_uint("liquidity #2", silo0.getLiquidity());

        assertEq(
            silo0.maxWithdraw(user1),
            3,
            "[user1] maxWithdraw 3 - still more than deposit, because dust was propagated"
        );

        // +2 because we deposited it
        assertEq(silo0.getLiquidity(), DUST_LEFT + 2, "getLiquidity == 1, dust left");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_dustPropagation_twoUsers
    */
    function test_dustPropagation_twoUsers() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        uint256 assets = 1;
        uint256 shares1 = _deposit(assets, user1);
        emit log_named_uint("[user1] shares1", shares1);

        uint256 shares2 = _deposit(assets, user2);
        emit log_named_uint("[user2] shares2", shares2);

        uint256 maxWithdraw1 = silo0.maxWithdraw(user1);
        uint256 maxWithdraw2 = silo0.maxWithdraw(user2);

        // +1 because we underestimated for fractions in maxWithdraw function
        assertEq(
            maxWithdraw1 + 1,
            assets + DUST_LEFT / 2,
            "[user1] maxWithdraw - more than deposit, because dust was propagated"
        );
        assertEq(
            maxWithdraw2,
            0,
            "[user2] maxWithdraw 0, because dust was propagated so we 'back to normal' and -1 for rounding"
        );

        shares2 += _deposit(1, user2);
        emit log_named_uint("[user2] shares2 #2", shares2);
        assertEq(
            silo0.maxWithdraw(user2), 1, "[user2] maxWithdraw 1, dust propagated, user lost 1 wei because of rounding"
        );

        assertEq(
            _redeem(shares1, user1),
            assets + DUST_LEFT / 2,
            "[user1] withdrawn assets - more than deposit, because dust was propagated"
        );
        assertEq(
            _redeem(shares2, user2),
            1,
            "[user2] withdrawn assets - less than deposit, because dust was propagated already"
        );

        assertEq(silo0.getLiquidity(), DUST_LEFT - 1, "getLiquidity == 1, 1 wei of dust propagated");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_dustPropagation_noInterest_twoUsers_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 1000
    function test_dustPropagation_noInterest_twoUsers_fuzz(uint128 deposit1, uint128 deposit2) public {
        //        (uint128 deposit1, uint128 deposit2) = (13181, 49673014963301);
        vm.assume(deposit1 > DUST_LEFT);
        vm.assume(deposit2 > DUST_LEFT);

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        uint256 shares1 = _deposit(deposit1, user1);
        uint256 shares2 = _deposit(deposit2, user2);

        emit log_named_uint("shares1", shares1);
        emit log_named_uint("shares2", shares2);

        _withdrawFromSilo(user1, deposit1, shares1);
        _withdrawFromSilo(user2, deposit2, shares2);

        emit log_named_uint("dust was", DUST_LEFT);
        emit log_named_uint("silo0.getLiquidity() is now", silo0.getLiquidity());

        assertLt(silo0.getLiquidity(), DUST_LEFT, "some dust was propagated");
    }

    function _withdrawFromSilo(address _user, uint256 _deposited, uint256 _shares) internal {
        uint256 maxWithdraw = silo0.maxWithdraw(_user);

        bool userGetsMore = maxWithdraw > _deposited;

        emit log_named_string("user1 will get", userGetsMore ? "MORE" : "LESS");
        emit log_named_uint("    deposit1", _deposited);
        emit log_named_uint("maxWithdraw1", maxWithdraw);

        if (!userGetsMore) {
            assertLe(_deposited - maxWithdraw, DUST_LEFT, "[user1] maxWithdraw can be less by DUST_LEFT");
        }

        uint256 withdrawn = _redeem(_shares, _user);
        emit log_named_uint("withdrawn1", withdrawn);
        assertLe(
            withdrawn - maxWithdraw,
            1,
            "[user1] max should match real withdrawn (1wei diff acceptable because of max underestimation)"
        );

        bool userGotMore = withdrawn > _deposited;

        uint256 diff = userGotMore ? withdrawn - _deposited : _deposited - withdrawn;

        emit log_named_uint("diff", diff);

        if (!userGotMore) {
            assertLe(diff, DUST_LEFT, "withdrawn assets can be off by DUST_LEFT max");
        }
    }

    function _printState(string memory _title) private {
        ISiloConfig.ConfigData memory collateralConfig = siloConfig.getConfig(address(silo0));

        emit log_named_string("================ ", _title);

        emit log_named_decimal_uint("[silo0] borrower LTV ", silo0.getLtv(BORROWER), 16);
        emit log_named_decimal_uint(
            "[silo0] borrower collateral shares ",
            IShareToken(collateralConfig.collateralShareToken).balanceOf(BORROWER),
            18
        );
        emit log_named_decimal_uint("[silo0] borrower debt (max repay)", silo0.maxRepay(BORROWER), 18);
        emit log_named_decimal_uint(
            "[silo0] collateral assets RAW (storage)", silo0.getTotalAssetsStorage(ISilo.AssetType.Collateral), 18
        );
        emit log_named_decimal_uint("[silo0] collateral assets with interest", silo0.getCollateralAssets(), 18);
        emit log_named_decimal_uint("[silo0] liquidity", silo0.getLiquidity(), 18);
        emit log_named_decimal_uint("[silo0] balanceOf(silo)", token0.balanceOf(address(silo0)), 18);

        (uint256 collateralToWithdraw, uint256 debtToRepay,) = partialLiquidation.maxLiquidation(BORROWER);

        if (debtToRepay != 0) {
            emit log_named_decimal_uint(
                "[silo0] liquidation possible, collateralToWithdraw", collateralToWithdraw, 18
            );
            emit log_named_decimal_uint("[silo0] liquidation possible, debtToRepay", debtToRepay, 18);
        }

        emit log("_____");
    }
}
