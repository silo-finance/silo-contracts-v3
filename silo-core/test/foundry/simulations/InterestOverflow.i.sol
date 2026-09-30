// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";

import {SiloLittleHelper} from "../_common/SiloLittleHelper.sol";
import {SiloConfigOverride} from "../_common/fixtures/SiloFixture.sol";
import {SiloFixture} from "../_common/fixtures/SiloFixture.sol";
import {MintableToken} from "../_common/MintableToken.sol";

/*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc InterestOverflowTest

    this test checks scenario, when we overflow interest, in that case we should be able to repay and exit silo
*/
contract InterestOverflowTest is SiloLittleHelper, Test {
    function _setUp(uint8 _decimals) public {
        SiloFixture siloFixture = new SiloFixture();

        SiloConfigOverride memory configOverride;

        token0 = new MintableToken(_decimals);
        token1 = new MintableToken(_decimals);

        token0.setOnDemand(true);
        token1.setOnDemand(true);

        configOverride.token0 = address(token0);
        configOverride.token1 = address(token1);

        (, silo0, silo1,,,) = siloFixture.deploy_local(configOverride);
    }

    /*
    forge test -vv --ffi --mt test_interestOverflow
    */
    function test_interestOverflow_fuzz(uint8 _decimals) public {
        vm.assume(_decimals <= 18);

        _interestOverflow(_decimals);
    }

    function _interestOverflow(uint8 _decimals) internal {
        _setUp(_decimals);
        uint256 one = 10 ** _decimals;

        address borrower = makeAddr("borrower");
        address borrower2 = makeAddr("borrower2");

        uint256 shares1 = _depositForBorrow(type(uint160).max, makeAddr("user1"));
        uint256 shares2 = _depositForBorrow(1, makeAddr("user2"));
        uint256 shares3 = _depositForBorrow(one, makeAddr("user3"));

        _deposit(type(uint160).max, borrower);
        _borrow(type(uint160).max / 100 * 75, borrower);

        _deposit(type(uint160).max / 100 * 25 * 2, borrower2);
        _borrow(type(uint160).max / 100 * 25, borrower2);

        vm.startPrank(makeAddr("user1"));
        shares1 -= silo1.withdraw(silo1.maxWithdraw(makeAddr("user1")), makeAddr("user1"), makeAddr("user1"));
        vm.stopPrank();

        assertEq(silo1.getLiquidity(), 1, "1 wei of liquidity on silo1");

        // now move into future until we overflow interest

        uint256 ltvBefore = SILO_LENS.getLtv(silo1, borrower);

        emit log_named_decimal_uint("LTV before", ltvBefore, 16);
        _printUtilization(silo1);
        vm.warp(1 days);

        emit log_named_decimal_uint("silo1.getLiquidity() 1", silo1.getLiquidity(), 18);

        uint256 allInterest;

        for (uint256 i;; i++) {
            // if we apply interest often, we will generate more interest in shorter time
            allInterest += silo1.accrueInterest();
            emit log_named_decimal_uint("silo1.getLiquidity()", silo1.getLiquidity(), 18);

            uint256 newLtv = SILO_LENS.getLtv(silo1, borrower);

            if (ltvBefore != newLtv) {
                ltvBefore = newLtv;
                vm.warp(block.timestamp + 10 days);
                emit log_named_uint("days pass", i * 10);
                _printUtilization(silo1);
            } else {
                emit log("INTEREST OVERFLOW");
                break;
            }
        }

        emit log("additional time should make no difference:");
        vm.warp(block.timestamp + 365 days);
        assertEq(silo1.accrueInterest(), 0, "when IRM overflows, there should be no more interest");
        _printUtilization(silo1);

        emit log_named_decimal_uint("LTV after", SILO_LENS.getLtv(silo0, borrower), 16);
        _printUtilization(silo1);

        uint256 dust = silo1.convertToAssets(1);
        assertGt(dust, 0, "ratio is so high, that even 0.001 share produces some assets");
        emit log_named_uint("dust", dust);

        uint256 revenueLost;

        {
            // too deep
            // even when overflow, we can deposit
            // approval is +2 because of rounding UP on convertToAssets and mint
            uint256 minted = _mintForBorrow(dust + 2, 1, makeAddr("user4"));
            assertEq(minted, dust, "minted assets");

            // this repay covers interest only
            (uint256 daoAndDeployerRevenue,,,,) = silo1.getSiloStorage();
            (uint256 daoFee, uint256 deployerFee,,) = silo1.config().getFeesWithAsset(address(silo1));

            uint256 revenue = allInterest * (daoFee + deployerFee) / 1e18;
            revenueLost = revenue - daoAndDeployerRevenue;
            emit log_named_decimal_uint("revenueLost", revenueLost, 18);
            emit log_named_decimal_uint("daoAndDeployerRevenue", daoAndDeployerRevenue, 18);

            assertLe(revenueLost, 6, "we did not lost revenue (6 wei acceptable)");

            // we repay revenue only, so that part that's not going to users as interest
            _repay(daoAndDeployerRevenue, borrower);

            // we have dust because
            assertEq(silo1.getLiquidity(), minted + 1, "even with huge repay, we cover interest first");
        }

        _repay(silo1.maxRepay(borrower), borrower);
        _repay(silo1.maxRepay(borrower2), borrower2);

        emit log("_withdrawAndCheck user1");
        _withdrawAndCheck(makeAddr("user1"), 0, shares1);

        emit log("_withdrawAndCheck user2");
        _withdrawAndCheck(makeAddr("user2"), 0, shares2);

        emit log("_withdrawAndCheck user3");
        _withdrawAndCheck(makeAddr("user3"), one, shares3);

        emit log("_withdrawAndCheck user4");
        _withdrawAndCheck(makeAddr("user4"), silo1.convertToAssets(1), 1);

        {
            (address collateralShare,, address debtShare) =
                ISiloConfig(silo1.config()).getShareTokens(address(silo1));
            (uint256 daoAndDeployerRevenue,,,,) = silo1.getSiloStorage();
            assertGe(token1.balanceOf(address(silo1)), daoAndDeployerRevenue, "got balance for fees");
            silo1.withdrawFees();

            assertEq(IShareToken(debtShare).totalSupply(), 0, "no debt");
            assertEq(IShareToken(collateralShare).totalSupply(), 0, "no collateralShares");

            assertEq(token1.balanceOf(address(silo1)), 906695, "silo balance");
            assertLe(revenueLost, 6, "lost revenue");
        }

        assertEq(_printUtilization(silo1).collateralAssets, 906695, "collateral dust left");

        {
            assertEq(0, SILO_LENS.getLtv(silo1, borrower), "LTV repaid");
            assertEq(0, SILO_LENS.getLtv(silo1, borrower2), "LTV repaid2");
        }
    }

    function _redeemAll(address _user, uint256 _shares) private returns (uint256 assets) {
        vm.prank(_user);
        assets = silo1.redeem(_shares, _user, _user);
    }

    function _printUtilization(ISilo _silo) private returns (ISilo.UtilizationData memory data) {
        data = _silo.utilizationData();

        emit log_named_decimal_uint("[UtilizationData] collateralAssets", data.collateralAssets, 18);
        emit log_named_decimal_uint("[UtilizationData] debtAssets", data.debtAssets, 18);
        emit log_named_uint("[UtilizationData] interestRateTimestamp", data.interestRateTimestamp);
    }

    function _withdrawAndCheck(address _user, uint256 _deposited, uint256 _shares)
        private
        returns (uint256 withdrawn)
    {
        emit log_named_address("withdraw checks for", _user);

        withdrawn = _redeemAll(_user, _shares);
        emit log_named_uint("deposit", _deposited);
        emit log_named_uint("withdraw", withdrawn);

        if (_deposited != 0) {
            assertLe(_deposited, withdrawn + 1, "user should not lose"); // +1 for rounding
        }

        assertEq(silo1.maxWithdraw(_user), 0, "maxWithdraw should be 0 at the end");
    }
}
