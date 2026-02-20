// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {Ownable} from "openzeppelin5/access/Ownable.sol";
import {ERC20Mock} from "openzeppelin5/mocks/token/ERC20Mock.sol";
import {IERC20Errors} from "openzeppelin5/interfaces/draft-IERC6093.sol";

import {XSiloAndStreamDeploy} from "x-silo/deploy/XSiloAndStreamDeploy.s.sol";
import {AddrKey} from "common/addresses/AddrKey.sol";

import {XSilo} from "../../../contracts/XSilo.sol";
import {XRedeemPolicy} from "../../../contracts/modules/XRedeemPolicy.sol";
import {Stream, IStream} from "../../../contracts/modules/Stream.sol";
import {IXRedeemPolicy} from "../../../contracts/interfaces/IXRedeemPolicy.sol";

/*
FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mc XRedeemPolicyTest
*/
contract XRedeemPolicyTest is Test {
    uint256 internal constant _PRECISION = 1e18;

    Stream stream;
    XSilo policy;
    ERC20Mock asset;

    function setUp() public {
        AddrLib.init();

        asset = new ERC20Mock();

        AddrLib.setAddress(AddrKey.SILO_TOKEN_V2, address(asset));
        AddrLib.setAddress(AddrKey.DAO, address(this));

        XSiloAndStreamDeploy deploy = new XSiloAndStreamDeploy();
        deploy.disableDeploymentsSync();
        (policy, stream) = deploy.run();

        // all tests are done for this setup:

        assertEq(policy.minRedeemRatio(), 0.5e18, "expected initial setup for minRedeemRatio");
        assertEq(policy.MAX_REDEEM_RATIO(), 1e18, "expected initial setup for maxRedeemRatio");
        assertEq(policy.minRedeemDuration(), 0, "expected initial setup for minRedeemDuration");
        assertEq(policy.maxRedeemDuration(), 6 * 30 days, "expected initial setup for maxRedeemDuration");
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_getXAmountByVestingDuration_whenZeroDuration_fuzz
    */
    /// forge-config: x_silo.fuzz.runs = 10000
    function test_getXAmountByVestingDuration_whenZeroDuration_fuzz(uint256 _amount) public view {
        assertEq(
            policy.getXAmountByVestingDuration(_amount, 0),
            _amount / 2,
            "any amount for 0 duration returns 1/2"
        );
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_getXAmountByVestingDuration_neverReverts_fuzz
    */
    /// forge-config: x_silo.fuzz.runs = 10000
    function test_getXAmountByVestingDuration_neverReverts_fuzz(uint256 _amount, uint256 _duration) public view {
        policy.getXAmountByVestingDuration(_amount, _duration);
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_getXAmountByVestingDuration_math
    */
    function test_getXAmountByVestingDuration_math() public view {
        uint256 maxTime = policy.maxRedeemDuration();

        assertEq(policy.getXAmountByVestingDuration({_xSiloAmount: 2, _duration: 0}), 1, "[1] loosing 50%");
        assertEq(policy.getXAmountByVestingDuration({_xSiloAmount: 100, _duration: 0}), 50, "[2] loosing 50%");

        assertEq(
            policy.getXAmountByVestingDuration({_xSiloAmount: 100, _duration: maxTime / 2}),
            75,
            "[3] preserve 75%"
        );

        assertEq(
            policy.getXAmountByVestingDuration({_xSiloAmount: 100, _duration: maxTime}),
            100,
            "[4] preserve 100%"
        );
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_getAmountInByVestingDuration_zeroDuration_fuzz
    */
    /// forge-config: x_silo.fuzz.runs = 10000
    function test_getAmountInByVestingDuration_zeroDuration_fuzz(uint256 _xSiloAfterVesting) public view {
        vm.assume(_xSiloAfterVesting <= type(uint128).max);

        assertEq(
            policy.getAmountInByVestingDuration(_xSiloAfterVesting, 0),
            _xSiloAfterVesting * 2,
            "any amount for 0 returns +50%"
        );
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_getAmountInByVestingDuration_neverReverts_fuzz
    */
    /// forge-config: x_silo.fuzz.runs = 10000
    function test_getAmountInByVestingDuration_neverReverts_fuzz(uint256 _xSiloAfterVesting, uint256 _duration)
        public
        view
    {
        vm.assume(_xSiloAfterVesting <= type(uint256).max / _PRECISION);

        policy.getAmountInByVestingDuration(_xSiloAfterVesting, _duration);
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_getAmounts_crosscheck_fuzz
    */
    /// forge-config: x_silo.fuzz.runs = 10000
    function test_getAmounts_crosscheck_fuzz(uint256 _xSiloAfterVesting, uint256 _duration) public view {
        vm.assume(_xSiloAfterVesting <= type(uint128).max);

        uint256 xSiloAmountIn = policy.getAmountInByVestingDuration(_xSiloAfterVesting, _duration);

        uint256 xSiloAfter = policy.getXAmountByVestingDuration(xSiloAmountIn, _duration);

        assertEq(xSiloAfter, _xSiloAfterVesting, "#1 crosscheck calculation");

        uint256 xAmountIn = policy.getAmountInByVestingDuration(xSiloAfter, _duration);

        assertEq(xAmountIn, xSiloAmountIn, "#2 crosscheck calculation");
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_getUserRedeemsBalance_whenAllZeros
    */
    function test_getUserRedeemsBalance_whenAllZeros() public view {
        assertEq(policy.getUserRedeemsBalance(address(1)), 0, "without queue no redeem balance");
        assertEq(policy.getUserRedeemsLength(address(1)), 0, "without items no queue");
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_getUserRedeem_revertsOnInvalidIndex
    */
    function test_getUserRedeem_revertsOnInvalidIndex() public {
        vm.expectRevert(IXRedeemPolicy.RedeemIndexDoesNotExist.selector);
        policy.getUserRedeem(address(1), 100);
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_redeemSilo_zeros
    */
    function test_redeemSilo_zeros() public {
        vm.expectRevert(IXRedeemPolicy.ZeroAmount.selector);
        policy.redeemSilo(0, 0);

        vm.expectRevert(IXRedeemPolicy.NoSiloToRedeem.selector);
        policy.redeemSilo(1, 0);
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_redeemSilo_revertsOnInvalidDuration
    */
    function test_redeemSilo_revertsOnInvalidDuration() public {
        policy.updateRedeemSettings({
            _minRedeemRatio: 1,
            _minRedeemDuration: 1,
            _maxRedeemDuration: 2
        });

        uint256 amount = 1e18;
        address user = makeAddr("user");

        _convert(user, amount);

        vm.expectRevert(IXRedeemPolicy.DurationTooLow.selector);
        policy.redeemSilo(1, 0);

        vm.expectRevert(IXRedeemPolicy.DurationTooHigh.selector);
        policy.redeemSilo(1, 3);
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_redeemSilo_emits_StartRedeem_noRewards_1s
    */
    function test_redeemSilo_emits_StartRedeem_noRewards_1s() public {
        uint256 toRedeem = 0.5e18;
        uint256 duration = 1 seconds;

        _redeemSilo_emits_StartRedeem_noRewards(
            toRedeem, duration, (toRedeem + toRedeem / policy.maxRedeemDuration()) / 2
        );
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_redeemSilo_emits_StartRedeem_noRewards_halfTime
    */
    function test_redeemSilo_emits_StartRedeem_noRewards_halfTime() public {
        uint256 toRedeem = 0.5e18;
        uint256 halfTime = policy.maxRedeemDuration() / 2;

        _redeemSilo_emits_StartRedeem_noRewards(toRedeem, halfTime, toRedeem * 3 / 4);
    }

    function _redeemSilo_emits_StartRedeem_noRewards(
        uint256 _toRedeem,
        uint256 _duration,
        uint256 _siloAmountAfterVesting
    )
        public
    {
        uint256 amount = 1e18;

        address user = makeAddr("user");
        _convert(user, amount);

        vm.expectEmit(address(policy));
        emit IXRedeemPolicy.StartRedeem({
            userAddress: user,
            currentSiloAmount: policy.convertToAssets(_toRedeem),
            xSiloToBurn: _toRedeem,
            siloAmountAfterVesting: _siloAmountAfterVesting,
            duration: _duration
        });

        vm.prank(user);
        policy.redeemSilo(_toRedeem, _duration);
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_redeemSilo_immediate_noStream
    */
    function test_redeemSilo_immediate_noStream() public {
        address user = makeAddr("user");
        vm.startPrank(user);

        asset.mint(user, 100);
        asset.approve(address(policy), 100);

        policy.deposit(asset.balanceOf(user), user);
        policy.redeemSilo(policy.balanceOf(user), 0);

        assertEq(policy.totalSupply(), 0, "vault should be empty");
        assertEq(policy.balanceOf(user), 0, "no user balance");
        assertEq(asset.balanceOf(user), 50, "user got 50% on immediate redeem");
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_redeemSilo_immediate_redeemTooMuch
    */
    function test_redeemSilo_immediate_redeemTooMuch(bool _withRewards, uint32 _warp) public {
        address user = makeAddr("user");

        vm.warp(block.timestamp + 1 minutes);

        uint256 shares = _convert(user, 100);

        if (_withRewards) _setupStream();
        if (_warp != 0) vm.warp(block.timestamp + _warp);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, user, shares, shares + 1));
        vm.prank(user);
        policy.redeemSilo(shares + 1, 0);
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_redeemSilo_immediate_noRewards_withStream_NoWarp_fuzz
    */
    function test_redeemSilo_immediate_noRewards_withStream_NoWarp_fuzz(uint256 _amount) public {
        vm.assume(_amount > 0);
        vm.assume(_amount < 2 ** 128);

        address user = makeAddr("user");

        _convert(user, _amount);

        _setupStream();

        _ensure_redeemSilo_immediate_doesNotGiveRewards(user, _amount);

        assertEq(policy.totalSupply(), 0, "vault should be empty");
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_redeemSilo_immediate_noRewards_withStream_afterTime_fuzz
    */
    function test_redeemSilo_immediate_noRewards_withStream_afterTime_fuzz(uint256 _amount) public {
        vm.assume(_amount > 0);
        vm.assume(_amount < 2 ** 128);

        _convert(makeAddr("first user"), 1e18);
        _setupStream();

        // some rewards in place
        vm.warp(block.timestamp + 1 days);

        address user = makeAddr("user");
        vm.assume(policy.previewDeposit(_amount) != 0);
        _convert(user, _amount);

        _ensure_redeemSilo_immediate_doesNotGiveRewards(user, _amount);
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_redeemSilo_getters
    */
    function test_redeemSilo_getters() public {
        address user = makeAddr("user");
        _convert(user, 1e18);

        uint256 balanceBeforeRedeem = policy.balanceOf(user);
        uint256 maxDuration = policy.maxRedeemDuration();

        vm.prank(user);
        policy.redeemSilo(balanceBeforeRedeem, maxDuration);

        uint256 balanceAfterRedeem = policy.balanceOf(user);
        assertEq(balanceAfterRedeem, 0, "balance should be 0");

        uint256 userRedeemsLength = policy.getUserRedeemsLength(user);
        assertEq(userRedeemsLength, 1, "userRedeemsLength should be 1");

        uint256 userRedeemsBalance = policy.getUserRedeemsBalance(user);
        assertEq(userRedeemsBalance, balanceBeforeRedeem, "userRedeemsBalance should be equal to balanceBeforeRedeem");

        XRedeemPolicy.RedeemInfo[] memory userRedeems = policy.userRedeems(user);
        assertEq(userRedeems.length, 1, "userRedeems should have 1 item");
        assertEq(userRedeems[0].endTime, block.timestamp + maxDuration, "endTime should be equal to maxDuration");

        assertEq(
            userRedeems[0].currentSiloAmount,
            balanceBeforeRedeem,
            "currentSiloAmount should be equal to balanceBeforeRedeem"
        );

        assertEq(
            userRedeems[0].xSiloAmountToBurn,
            balanceBeforeRedeem,
            "xSiloAmountToBurn should be equal to balanceBeforeRedeem"
        );

        assertEq(
            userRedeems[0].siloAmountAfterVesting,
            balanceBeforeRedeem,
            "siloAmountAfterVesting should be equal to balanceBeforeRedeem"
        );

        uint256 currentSiloAmount;
        uint256 xSiloAmount;
        uint256 siloAmountAfterVesting;
        uint256 endTime;

        (currentSiloAmount, xSiloAmount, siloAmountAfterVesting, endTime) = policy.getUserRedeem(user, 0);
        assertEq(currentSiloAmount, balanceBeforeRedeem, "currentSiloAmount should be equal to balanceBeforeRedeem");
        assertEq(xSiloAmount, balanceBeforeRedeem, "xSiloAmount should be equal to balanceBeforeRedeem");
        assertEq(siloAmountAfterVesting, balanceBeforeRedeem, "siloAmountAfterVesting should be equal to balanceBeforeRedeem");
        assertEq(endTime, block.timestamp + maxDuration, "endTime should be equal to maxDuration");

        vm.expectRevert(IXRedeemPolicy.RedeemIndexDoesNotExist.selector);
        policy.getUserRedeem(user, 1);
    }

    function _ensure_redeemSilo_immediate_doesNotGiveRewards(address _user, uint256 _amount) public {
        vm.startPrank(_user);

        uint256 shares = policy.balanceOf(_user);

        vm.assume(policy.getAmountByVestingDuration(shares, 0) != 0);

        policy.redeemSilo(shares, 0);
        vm.stopPrank();

        assertEq(policy.balanceOf(_user), 0, "no user balance");

        // in extreme cases we can get less that 50% because of precision error
        assertLe(
            asset.balanceOf(_user),
            _amount / 2,
            "user got up to 50% on immediate redeem (rewards not included because no time)"
        );
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_redeemSilo_expectNoRewardsOnCancel_single
    */
    function test_redeemSilo_expectNoRewardsOnCancel_single() public {
        uint256 amount = 1e18;
        uint256 duration = 10 hours;

        _redeemSilo_expectNoRewardsOnCancel(amount, duration, false);
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_redeemSilo_expectNoRewardsOnCancel_twoUsers_fuzz
    */
    function test_redeemSilo_expectNoRewardsOnCancel_twoUsers_fuzz(uint256 _amount, uint256 _duration) public {
        _redeemSilo_expectNoRewardsOnCancel(_amount, _duration, true);
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_redeemSilo_expectNoRewardsOnCancel_oneUser_fuzz
    */
    function test_redeemSilo_expectNoRewardsOnCancel_oneUser_fuzz(uint256 _amount, uint256 _duration) public {
        _redeemSilo_expectNoRewardsOnCancel(_amount, _duration, false);
    }

    function _redeemSilo_expectNoRewardsOnCancel(uint256 _amount, uint256 _duration, bool _twoUsers) public {
        vm.assume(_amount > 0);
        vm.assume(_amount < 2 ** 128);
        vm.assume(_duration > 0);
        vm.assume(_duration <= policy.maxRedeemDuration());

        if (_twoUsers) {
            _convert(makeAddr("user2"), _amount / 2 + 1);
        }

        address user = makeAddr("user");

        _convert(user, _amount);
        _setupStream(); // 0.01/s for 1 day

        vm.startPrank(user);

        vm.warp(block.timestamp + 1 hours);
        vm.assume(policy.previewDeposit(_amount) != 0);

        uint256 sharesBeforeRedeem = policy.balanceOf(user);
        uint256 siloAmountBeforeRedeem = policy.convertToAssets(sharesBeforeRedeem);

        policy.redeemSilo(sharesBeforeRedeem, _duration);
        vm.warp(block.timestamp + 1 days);

        (uint256 currentSiloAmount,,,) = policy.getUserRedeem(user, 0);

        uint256 expectedSharesAfterRedeem = policy.convertToShares(siloAmountBeforeRedeem);

        uint256 xSiloToMint = policy.convertToShares(currentSiloAmount);
        uint256 leftSilos = asset.balanceOf(address(policy));

        emit log_named_uint("total assets", policy.totalAssets());
        emit log_named_uint("real balance", leftSilos);
        emit log_named_uint("total shares", policy.totalSupply());
        emit log_named_uint("expectedSharesAfterRedeem", expectedSharesAfterRedeem);
        emit log_named_uint("xSiloToMint", xSiloToMint);
        emit log_named_uint("stream.pendingRewards()", stream.pendingRewards());

        if (xSiloToMint == 0) {
            vm.expectRevert(IXRedeemPolicy.CancelGeneratesZeroShares.selector);
        } else {
            vm.expectEmit(address(policy));
            emit IXRedeemPolicy.CancelRedeem({
                userAddress: user,
                siloAmountRestored: currentSiloAmount,
                xSiloMinted: xSiloToMint
            });
        }

        policy.cancelRedeem(0);

        vm.stopPrank();

        if (_twoUsers) {
            assertLe(expectedSharesAfterRedeem, sharesBeforeRedeem, "cancel will recalculate (reduce) shares");
        } else {
            // with one/last user it is possible to get more, because of leftover in contract
            // cancel will work like xSilo restart if this is last user
        }

        assertEq(policy.balanceOf(user), expectedSharesAfterRedeem, "expectedShares");
        assertEq(asset.balanceOf(user), 0, "user did not get any Silo");

        // we should be able to deposit at the end
        _convert(address(1), 1e18);
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_redeemSiloImmediately_isClaimingRewardsBefore
    */
    function test_redeemSiloImmediately_isClaimingRewardsBefore() public {
        bytes memory data = abi.encodeCall(policy.redeemSilo, (1e15, 0));
        _method_isClaimingRewardsBefore(data);
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_redeemSiloWithDuration_isClaimingRewardsBefore
    */
    function test_redeemSiloWithDuration_isClaimingRewardsBefore() public {
        bytes memory data = abi.encodeCall(policy.redeemSilo, (1e15, 1));
        _method_isClaimingRewardsBefore(data);
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_redeem_isClaimingRewardsBefore
    */
    function test_redeem_isClaimingRewardsBefore() public {
        address user = makeAddr("user");
        bytes memory data = abi.encodeCall(policy.redeem, (1e15, user, user));
        _method_isClaimingRewardsBefore(data);
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_withdraw_isClaimingRewardsBefore
    */
    function test_withdraw_isClaimingRewardsBefore() public {
        address user = makeAddr("user");
        bytes memory data = abi.encodeCall(policy.withdraw, (1e15, user, user));
        _method_isClaimingRewardsBefore(data);
    }

    function _method_isClaimingRewardsBefore(bytes memory _policyCalldata) internal {
        uint256 _amount = 1e18;
        address user = makeAddr("user");

        _convert(user, _amount);

        _setupStream(); // 0.01/s for 1 day

        uint256 balanceBefore = asset.balanceOf(address(policy));

        vm.warp(block.timestamp + 1 hours);

        vm.expectEmit(address(stream));
        emit IStream.RewardsClaimed(0.01e18 * 1 hours);

        vm.prank(user);
        (bool success,) = address(policy).call(_policyCalldata);
        assertTrue(success);

        uint256 balanceAfter = asset.balanceOf(address(policy));

        assertGt(balanceAfter, balanceBefore, "rewards delivered");
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_audit_M01_case
    */
    function test_audit_M01_case() public {
        uint256 siloAmount = 1e18;
        uint256 maxDuration = policy.maxRedeemDuration();

        address user = makeAddr("user");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("last user3");

        uint256 userShares = _convert(user, siloAmount);
        _convert(user2, siloAmount);

        _setupStream(); // 0.01/s for 1 day

        // redeem is started on the same time as setup stream, so there will be no rewards at all for this user
        vm.prank(user);
        policy.redeemSilo(userShares, maxDuration);

        (
            uint256 currentSiloAmount,
            uint256 xSiloAmount,
            uint256 siloAmountAfterVesting,
        ) = policy.getUserRedeem(user, 0);

        assertEq(currentSiloAmount, siloAmount, "users current Silo amounts at the moment, 100%");
        assertEq(xSiloAmount, userShares, "userShares");
        assertEq(siloAmountAfterVesting, siloAmount, "user does not loose Silo if he redeem for max time");

        assertEq(
            policy.totalAssets(),
            siloAmount,
            "total assets after redeem is == one user deposit"
        );

        assertEq(policy.pendingLockedSilo(), siloAmount, "pendingLockedSilo == current user redeem");

        vm.warp(block.timestamp + maxDuration + 1 days);

        uint256 user3shares = _convert(user3, siloAmount);
        uint256 userRedeemAmountBefore = policy.previewRedeem(user3shares);

        vm.prank(user);
        policy.cancelRedeem(0);

        assertEq(
            // -1 because of rounding, uses looses 1 wei
            policy.previewRedeem(user3shares) - 1,
            userRedeemAmountBefore,
            "user3 just deposited, should not gain any extra rewards because of other user cancel redeem"
        );

        assertEq(policy.pendingLockedSilo(), 0, "pendingLockedSilo is reset");

        assertEq(
            // vesting for maxDuration should not give us penalty, so we expecting 100% os SILO as return
            policy.getAmountByVestingDuration(policy.balanceOf(user), maxDuration),
            // -273 is
            currentSiloAmount - 615,
            "after canceling Silos recreated based on `currentSiloAmount`, means we take max penalty for canceling"
        );

        assertEq(stream.pendingRewards(), 0, "there should be no pending rewards");

        uint256 allRewards = 0.01e18 * 1 days;

        assertEq(
            policy.totalAssets(),
            siloAmount * 3 + allRewards,
            "total assets is again both users deposits + all rewards"
        );

        assertEq(
            asset.balanceOf(address(policy)),
            siloAmount * 3 + allRewards,
            "xSilo holds both deposits + all rewards"
        );
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_redeemSilo_everyoneRedeemMax_withStream
    */
    function test_redeemSilo_everyoneRedeemMax_withStream() public {
        _redeemSilo_everyoneRedeemMax(true);
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_redeemSilo_everyoneRedeemMax_withoutStream
    */
    function test_redeemSilo_everyoneRedeemMax_withoutStream() public {
        _redeemSilo_everyoneRedeemMax(false);
    }

    function _redeemSilo_everyoneRedeemMax(bool _withStream) public {
        uint256 siloAmount = 1e18;
        uint256 maxDuration = policy.maxRedeemDuration();

        address user = makeAddr("user");
        address user2 = makeAddr("user2");

        uint256 shares1 = _convert(user, siloAmount);
        uint256 shares2 = _convert(user2, siloAmount);

        if (_withStream) _setupStream(); // 0.01/s for 1 day

        emit log_named_uint("total assets", policy.totalAssets());
        emit log_named_uint("total supply", policy.totalSupply());
        emit log_named_uint("getAmountByVestingDuration", policy.getAmountByVestingDuration(shares2, maxDuration));

        vm.prank(user);
        uint256 siloAmountAfterVesting = policy.redeemSilo(shares1, maxDuration);
        assertEq(siloAmountAfterVesting, siloAmount, "user1 will redeem 100% of Silos");

        emit log_named_uint("total assets", policy.totalAssets());
        emit log_named_uint("total supply", policy.totalSupply());
        emit log_named_uint("getAmountByVestingDuration", policy.getAmountByVestingDuration(shares2, maxDuration));

        vm.prank(user2);
        siloAmountAfterVesting = policy.redeemSilo(shares2, maxDuration);
        assertEq(siloAmountAfterVesting, siloAmount, "user2 will redeem 100% of Silos");

        emit log_named_uint("total assets", policy.totalAssets());
        emit log_named_uint("total supply", policy.totalSupply());

        vm.warp(block.timestamp + maxDuration);

        if (_withStream) stream.claimRewards();

        vm.prank(user);
        policy.finalizeRedeem(0);

        vm.prank(user2);
        policy.finalizeRedeem(0);

        uint256 allRewards = _withStream ? 0.01e18 * 1 days : 0;

        assertEq(stream.pendingRewards(), 0, "no pending rewards");
        assertEq(policy.totalSupply(), 0, "no shares, everyone left");
        assertEq(policy.totalAssets(), 0, "totalAssets hides balance when no shares");
        assertEq(policy.pendingLockedSilo(), 0, "pendingLockedSilo is empty");

        assertEq(
            asset.balanceOf(address(policy)),
            allRewards,
            "even with max vesting, noone got rewards, because redeem was started at rewards distribution"
        );

        assertEq(asset.balanceOf(user), siloAmount, "with max vesting user did not lose tokens");
        assertEq(asset.balanceOf(user2), siloAmount, "with max vesting user2 did not lose tokens");
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_redeemSilo_oneRedeemMax
    */
    function test_redeemSilo_oneRedeemMax() public {
        uint256 siloAmount = 1e18;
        uint256 maxDuration = policy.maxRedeemDuration();

        address user = makeAddr("user");
        address user2 = makeAddr("user2");

        _convert(user, siloAmount);
        _convert(user2, siloAmount);

        _setupStream(); // 0.01/s for 1 day

        vm.prank(user);
        policy.redeemSilo(siloAmount, maxDuration);

        vm.warp(block.timestamp + maxDuration);

        vm.prank(user);
        policy.finalizeRedeem(0);

        uint256 allRewards = 0.01e18 * 1 days;

        assertEq(policy.totalSupply(), siloAmount, "one user left");
        assertEq(
            asset.balanceOf(address(policy)),
            siloAmount,
            "user deposit, no rewards, because rewards are claimed before share transfer, finalize does not claim"
        );
        assertEq(asset.balanceOf(user), siloAmount, "with max vesting user did not lose tokens");
        assertEq(asset.balanceOf(address(stream)), allRewards, "stream has all rewards yet, pending for claim");

        vm.prank(user2);
        policy.redeemSilo(siloAmount, maxDuration);
        vm.warp(block.timestamp + maxDuration);

        vm.prank(user2);
        policy.finalizeRedeem(0);

        assertEq(
            asset.balanceOf(address(policy)),
            864,
            "users should get all (864 dust for rounding based on calculations with offset)"
        );

        assertEq(
            asset.balanceOf(user2),
            1e18 + 0.01e18 * 1 days - 864,
            "user deposit + all rewards for 1 day (-864 for rounding based on calculations with offset)");
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_redeemSilo_expectNoRewardsOnVestingPeriod
    */
    function test_redeemSilo_expectNoRewardsOnVestingPeriod() public {
        uint256 siloAmount = 1e18;

        address user = makeAddr("user");
        address user2 = makeAddr("user2");

        _convert(user, siloAmount);
        _convert(user2, siloAmount);

        assertEq(asset.balanceOf(address(policy)), 2e18, "users Silos");

        _setupStream(); // 0.01/s for 1 day

        assertEq(asset.balanceOf(address(policy)), 2e18, "no rewards transferred yet");

        vm.startPrank(user);

        vm.warp(block.timestamp + 1 hours);

        uint256 pendingRewards = stream.pendingRewards();
        uint256 user2MaxWithdrawBefore = policy.maxWithdraw(user2);

        uint256 siloAmountAfterVesting = policy.redeemSilo(0.25e18, 0);
        assertEq(policy.balanceOf(user), 0.75e18, "shares left after 1st redeem");

        assertEq(
            asset.balanceOf(address(policy)),
            2e18 + pendingRewards - siloAmountAfterVesting,
            "on redeemSilo we have transfer, so we claimed no rewards transferred yet"
        );

        assertGt(
            policy.maxWithdraw(user2),
            user2MaxWithdrawBefore,
            "user2 got boost after user1 redeem before max vesting"
        );

        policy.redeemSilo(0.25e18, 11 hours);
        assertEq(policy.balanceOf(user), 0.5e18, "shares left on user balance");

        policy.redeemSilo(0.25e18, 23 hours);
        policy.redeemSilo(0.25e18, 6 * 30 days);

        assertEq(policy.balanceOf(user), 0, "all shares locked, transferred to contract on redeem");

        _finalizeNextRedeemBeforeMaxVesting("after 11h");
        _finalizeNextRedeemBeforeMaxVesting("after 23h");
        _finalizeNextRedeemBeforeMaxVesting("MAX vesting");

        vm.stopPrank();
    }

    // this is helper method for test: test_redeemSilo_expectNoRewardsOnVestingPeriod
    function _finalizeNextRedeemBeforeMaxVesting(string memory _msg) internal {
        emit log(_msg);
        address user = makeAddr("user");
        address user2 = makeAddr("user2");

        (,,,uint256 endTime) = policy.getUserRedeem(user, 0);
        vm.warp(endTime);

        uint256 user2MaxWithdrawBefore = policy.maxWithdraw(user2);

        emit log_named_uint("total assets before finalizeRedeem", policy.totalAssets());
        emit log_named_uint("pendingLockedSilo before finalizeRedeem", policy.pendingLockedSilo());

        (
            uint256 currentSiloAmount_, uint256 xSiloAmount_, uint256 siloAmountAfterVesting_,
        ) = policy.getUserRedeem(user, 0);

        emit log_named_uint("currentSiloAmount", currentSiloAmount_);
        emit log_named_uint("xSiloAmount", xSiloAmount_);
        emit log_named_uint("siloAmountAfterVesting", siloAmountAfterVesting_);

        policy.finalizeRedeem(0);

        emit log_named_uint(" total assets after finalizeRedeem", policy.totalAssets());
        emit log_named_uint(" pendingLockedSilo after finalizeRedeem", policy.pendingLockedSilo());

        assertGe(
            policy.maxWithdraw(user2),
            user2MaxWithdrawBefore,
            string.concat(
                _msg,
                " user2 might get boost because after finalize redeem fee is paid (if duration is not max) "
                "and this is distributed as reward fee is calculated"
            )
        );
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_settings_zero
    */
    function test_settings_zero() public {
        policy.updateRedeemSettings(0, 0, 1);

        address user = makeAddr("user");

        _convert(user, 1e18);

        vm.startPrank(user);

        uint256 siloAmountAfterVesting = policy.getAmountByVestingDuration(1e18, 0);

        assertEq(siloAmountAfterVesting, 0, "siloAmountAfterVesting iz zero because min ratio is 0");
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_updateRedeemSettings_onlyOwner
    */
    function test_updateRedeemSettings_onlyOwner() public {
        address someAddress = makeAddr("someAddress");

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, someAddress));
        vm.prank(someAddress);
        policy.updateRedeemSettings(0, 0, 0);
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_updateRedeemSettings_DurationTooHigh
    */
    function test_updateRedeemSettings_DurationTooHigh() public {
        vm.expectRevert(IXRedeemPolicy.DurationTooHigh.selector);
        policy.updateRedeemSettings(0, 0, 365 days + 1);
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_donationAttack
    */
    function test_donationAttack() public {
        address user = makeAddr("user");
        // this will NOT create huge ratio, because when totalSupply is zero we will distribute all balance to 1st user
        _setupStream();

        vm.warp(block.timestamp + 1 minutes);

        vm.startPrank(user);

        asset.mint(user, 100);
        asset.approve(address(policy), 100);

        assertEq(policy.deposit(100, user), 100, "user got normal shares amount");

    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_ration_calculation_duration_less_min_duration
    */
    function test_ration_calculation_duration_less_min_duration() public {
        policy.updateRedeemSettings({
            _minRedeemRatio: policy.minRedeemRatio(),
            _minRedeemDuration: 2 days,
            _maxRedeemDuration: policy.maxRedeemDuration()
        });

        uint256 siloAmountAfterVesting = policy.getAmountByVestingDuration(1e18, 1 days);
        // because duration is less than min duration, ration should be 0
        assertEq(siloAmountAfterVesting, 0, "siloAmountAfterVesting should be 0");
    }

    function _setupStream() public returns (uint256 emissionPerSecond) {
        emissionPerSecond = 0.01e18;

        stream.setEmissions(emissionPerSecond, block.timestamp + 1 days);
        asset.mint(address(stream), stream.fundingGap());

        assertEq(asset.balanceOf(address(stream)), 0.01e18 * 1 days, "pending rewards balance");
    }

    function _convert(address _user, uint256 _amount) public returns (uint256 shares) {
        vm.startPrank(_user);

        asset.mint(_user, _amount);
        asset.approve(address(policy), _amount);
        shares = policy.deposit(_amount, _user);

        assertGt(shares, 0, "[_convert] shares received");

        vm.stopPrank();
    }
}
