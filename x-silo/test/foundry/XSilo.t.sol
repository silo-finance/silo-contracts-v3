// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Math} from "openzeppelin5/utils/math/Math.sol";

import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";

import {ERC20Mock} from "openzeppelin5/mocks/token/ERC20Mock.sol";

import {XSiloAndStreamDeploy} from "x-silo/deploy/XSiloAndStreamDeploy.s.sol";
import {AddrKey} from "common/addresses/AddrKey.sol";

import {XSilo} from "../../contracts/XSilo.sol";
import {Stream} from "../../contracts/modules/Stream.sol";
import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";

/*
FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mc XSiloTest
*/
contract XSiloTest is Test {
    using SafeERC20 for IERC20;

    uint256 internal constant _PRECISION = 1e18;

    Stream stream;
    XSilo xSilo;
    ERC20Mock asset;

    struct CustomSetup {
        uint64 minRedeemRatio;
        uint64 minRedeemDuration;
        uint64 maxRedeemDuration;
    }

    function setUp() public {
        AddrLib.init();

        asset = new ERC20Mock();

        AddrLib.setAddress(AddrKey.SILO_TOKEN_V2, address(asset));
        AddrLib.setAddress(AddrKey.DAO, address(this));

        XSiloAndStreamDeploy deploy = new XSiloAndStreamDeploy();
        deploy.disableDeploymentsSync();
        (xSilo, stream) = deploy.run();
        // all tests are done for this setup:

        _defaultSetupVerification();
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_SelfTransferNotAllowed
    */
    function test_SelfTransferNotAllowed(CustomSetup memory _customSetup) public {
        _assumeCustomSetup({_customSetup: _customSetup, _allowForZeros: true});

        _convert(address(this), 10);

        vm.expectRevert(XSilo.SelfTransferNotAllowed.selector);
        xSilo.safeTransfer(address(this), 1);
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_ZeroTransfer
    */
    function test_ZeroTransfer(CustomSetup memory _customSetup) public {
        _assumeCustomSetup({_customSetup: _customSetup, _allowForZeros: true});

        _convert(address(this), 10);

        vm.expectRevert(XSilo.ZeroTransfer.selector);
        xSilo.safeTransfer(address(2), 0);
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_transferFrom_success
    */
    function test_transferFrom_success(CustomSetup memory _customSetup) public {
        _assumeCustomSetup({_customSetup: _customSetup, _allowForZeros: true});

        address user = makeAddr("user");
        address spender = makeAddr("spender");

        uint256 xSiloAmount = 10e18;

        _convert(user, xSiloAmount);

        vm.prank(user);
        xSilo.approve(spender, xSiloAmount);

        assertEq(xSilo.balanceOf(user), xSiloAmount, "user balance should be xSiloAmount");
        assertEq(xSilo.balanceOf(spender), 0, "spender balance should be 0");

        vm.prank(spender);
        xSilo.safeTransferFrom(user, spender, xSiloAmount);

        assertEq(xSilo.balanceOf(user), 0, "user balance should be 0");
        assertEq(xSilo.balanceOf(spender), xSiloAmount, "spender balance should be xSiloAmount");
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_maxWithdraw_usersDuration0_fuzz
    */
    /// forge-config: x_silo.fuzz.runs = 10000
    function test_maxWithdraw_usersDuration0_fuzz(CustomSetup memory _customSetup, uint256 _assets) public {
        _assumeCustomSetup({_customSetup: _customSetup, _allowForZeros: true});

        vm.assume(_assets > 0);
        vm.assume(_assets < type(uint256).max / _PRECISION); // to not cause overflow on calculation

        address user = makeAddr("user");

        _convert(user, _assets);

        assertEq(
            xSilo.maxWithdraw(user),
            xSilo.getAmountByVestingDuration(xSilo.balanceOf(user), 0),
            "withdraw give us same result as redeem with 0 duration"
        );
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_previewWithdraw_usersDuration0_fuzz
    */
    /// forge-config: x_silo.fuzz.runs = 10000
    function test_previewWithdraw_usersDuration0_fuzz(
        CustomSetup memory _customSetup,
        uint256 _assets
    ) public {
        _assumeCustomSetup({_customSetup: _customSetup, _allowForZeros: true});

        vm.assume(_assets > 0);
        vm.assume(_assets < type(uint256).max / _PRECISION); // to not cause overflow on calculation

        uint256 xSiloRequiredForAssets = xSilo.previewWithdraw(_assets);
        emit log_named_uint("xSiloRequiredForAssets", xSiloRequiredForAssets);

        if (xSiloRequiredForAssets == type(uint256).max) {
            assertEq(
                xSilo.getAmountByVestingDuration(type(uint256).max, 0),
                0,
                "(ratio is 0) previewWithdraw give us MAX, because there are no amount that can withdraw even 1 wei"
            );
        } else {
            assertEq(
                xSilo.getAmountByVestingDuration(xSiloRequiredForAssets, 0),
                _assets,
                "previewWithdraw give us same result as vesting with 0 duration"
            );
        }
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_maxRedeem_returnsAll_fuzz
    */
    /// forge-config: x_silo.fuzz.runs = 10000
    function test_maxRedeem_returnsAll_fuzz(CustomSetup memory _customSetup, uint256 _silos) public {
        _assumeCustomSetup({_customSetup: _customSetup, _allowForZeros: true});

        vm.assume(_silos > 0);
        vm.assume(_silos < type(uint256).max / _PRECISION); // to not cause overflow on calculation

        address user = makeAddr("user");

        _convert(user, _silos);

        assertEq(
            xSilo.maxRedeem(user),
            xSilo.balanceOf(user),
            "max redeem return all user balance even if not all can be translated immediatly to Silo"
        );
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_previewRedeem_usersDuration0_fuzz
    */
    /// forge-config: x_silo.fuzz.runs = 10000
    function test_previewRedeem_usersDuration0_fuzz(CustomSetup memory _customSetup, uint256 _shares) public {
        _assumeCustomSetup({_customSetup: _customSetup, _allowForZeros: true});

        vm.assume(_shares > 0);

        assertEq(
            xSilo.previewRedeem(_shares),
            xSilo.getAmountByVestingDuration(_shares, 0),
            "previewRedeem give us same result as vesting with 0 duration"
        );
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_withdraw_usesDuration0_WithdrawPossible_fuzz
    */
    /// forge-config: x_silo.fuzz.runs = 5000
    function test_withdraw_usesDuration0_WithdrawPossible_fuzz(
        CustomSetup memory _customSetup,
        uint256 _assetsToDeposit,
        uint16 _percentAssetsToWithdraw
    ) public {
        vm.assume(_assetsToDeposit > 0);
        vm.assume(_assetsToDeposit < type(uint256).max / _PRECISION); // to not cause overflow on calculation

        uint256 precision = 100;

        _percentAssetsToWithdraw = uint16(bound(_percentAssetsToWithdraw, 1, precision));

        _assumeCustomSetup({_customSetup: _customSetup, _allowForZeros: true});

        address user = makeAddr("user");

        _convert(user, _assetsToDeposit);

        uint256 assetsToWithdraw = Math.mulDiv(
            xSilo.maxWithdraw(user), _percentAssetsToWithdraw, precision, Math.Rounding.Floor
        );

        vm.startPrank(user);

        uint256 checkpoint = vm.snapshotState();

        vm.assume(xSilo.previewWithdraw(assetsToWithdraw) > 0);

        uint256 withdrawnShares = xSilo.withdraw(assetsToWithdraw, user, user);

        assertEq(asset.balanceOf(user), assetsToWithdraw, "user got exact amount of tokens");

        vm.revertToState(checkpoint);

        emit log_named_uint("withdrawnShares after rollback", withdrawnShares);
        emit log_named_uint("_siloToWithdraw", assetsToWithdraw);

        vm.startPrank(user);

        assertEq(
            assetsToWithdraw,
            xSilo.getAmountByVestingDuration(withdrawnShares, 0),
            "withdraw give us same result as vesting with 0 duration"
        );

        vm.stopPrank();
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_withdraw_usesDuration0_zeroShares_fuzz
    */
    /// forge-config: x_silo.fuzz.runs = 10000
    function test_withdraw_usesDuration0_zeroShares_fuzz(
        CustomSetup memory _customSetup,
        uint256 _assetsToDeposit,
        uint64 _percentAssetsToWithdraw
    ) public {
        vm.assume(_assetsToDeposit > 0);
        vm.assume(_assetsToDeposit < type(uint256).max / _PRECISION); // to not cause overflow on calculation

        _percentAssetsToWithdraw = uint64(bound(_percentAssetsToWithdraw, 1, _PRECISION));

        _assumeCustomSetup({_customSetup: _customSetup, _allowForZeros: true});

        address user = makeAddr("user");

        _convert(user, _assetsToDeposit);

        uint256 assetsToWithdraw = Math.mulDiv(
            xSilo.maxWithdraw(user), _percentAssetsToWithdraw, _PRECISION, Math.Rounding.Floor
        );

        bool zeroShares = xSilo.previewWithdraw(assetsToWithdraw) == 0;
        vm.assume(zeroShares);

        vm.expectRevert(XSilo.ZeroShares.selector);
        vm.prank(user);
        xSilo.withdraw(assetsToWithdraw, user, user);
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_redeem_all
    */
    /// forge-config: x_silo.fuzz.runs = 5000
    function test_redeem_all_fuzz(CustomSetup memory _customSetup, uint256 _assets) public {
        _assumeCustomSetup({_customSetup: _customSetup, _allowForZeros: true});

        vm.assume(_assets > 0);
        vm.assume(_assets < type(uint256).max / _PRECISION); // to not cause overflow on calculation

        address user = makeAddr("user");

        _convert(user, _assets);

        uint256 siloPreview = xSilo.getAmountByVestingDuration(xSilo.balanceOf(user), 0);
        vm.assume(siloPreview != 0);

        vm.startPrank(user);

        uint256 gotSilos = xSilo.redeem(xSilo.balanceOf(user), user, user);

        assertEq(
            siloPreview,
            gotSilos,
            "redeem give us same result as vesting with 0 duration"
        );

        assertEq(asset.balanceOf(user), gotSilos, "user got exact amount of tokens");

        vm.stopPrank();
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_redeem_usesDuration0_fuzz
    */
    /// forge-config: x_silo.fuzz.runs = 2000
    function test_redeem_usesDuration0_fuzz(
        CustomSetup memory _customSetup,
        uint256 _assets,
        uint16 _percentToRedeem
    ) public {
        vm.assume(_assets > 0);
        vm.assume(_assets < type(uint256).max / _PRECISION); // to not cause overflow on calculation

        _assumeCustomSetup({_customSetup: _customSetup, _allowForZeros: true});

        address user = makeAddr("user");

        _convert(user, _assets);

        _percentToRedeem = uint16(bound(_percentToRedeem, 1, 100));

        uint256 xSiloToRedeem = Math.mulDiv(xSilo.balanceOf(user), _percentToRedeem, _PRECISION, Math.Rounding.Floor);

        uint256 siloPreview = xSilo.getAmountByVestingDuration(xSiloToRedeem, 0);
        vm.assume(siloPreview != 0);

        vm.startPrank(user);

        uint256 gotSilos = xSilo.redeem(xSiloToRedeem, user, user);

        assertEq(
            siloPreview,
            gotSilos,
            "redeem give us same result as vesting with 0 duration"
        );

        assertEq(asset.balanceOf(user), gotSilos, "user got exact amount of tokens");

        vm.stopPrank();
    }

    struct TestFlow {
        uint64 amount;
        uint64 redeemDuration;
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_xSilo_flowShouldNotRevert_default_fuzz
    */
    /// forge-config: x_silo.fuzz.runs = 1000
    function test_xSilo_flowShouldNotRevert_default_fuzz(
        TestFlow[] memory _data,
        uint32 _emissionPerSecond,
        uint32 _streamDistribution
    ) public {
        _xSilo_flowShouldNotRevert(_data, _emissionPerSecond, _streamDistribution);
    }

    /*
    FOUNDRY_PROFILE=x_silo forge test -vv --ffi --mt test_xSilo_flowShouldNotRevert_custom_fuzz
    */
    /// forge-config: x_silo.fuzz.runs = 1000
    function test_xSilo_flowShouldNotRevert_custom_fuzz(
        CustomSetup memory _customSetup,
        TestFlow[] memory _data,
        uint32 _emissionPerSecond,
        uint32 _streamDistribution
    ) public {
        vm.assume(_customSetup.minRedeemRatio > 0); // so we do not stuck will all xSilos at the end

        _assumeCustomSetup({_customSetup: _customSetup, _allowForZeros: false});

        _xSilo_flowShouldNotRevert(_data, _emissionPerSecond, _streamDistribution);
    }

    function _xSilo_flowShouldNotRevert(
        TestFlow[] memory _data,
        uint32 _emissionPerSecond,
        uint32 _streamDistribution
    ) internal {
        vm.assume(_data.length > 0);
        vm.assume(_data.length <= 50);

        uint256 assetShareRatio = _getAssetShareRatio();

        for (uint i = 0; i < _data.length; i++) {
            emit log_named_uint("--------- depositing", i);

            address user = _userAddr(i);
            uint256 amount = _data[i].amount;
            vm.assume(amount > 1e3); // to prevent ratio issue on stream rewards

            _convert(user, amount);
            emit log_named_decimal_uint("amount", amount, 18);
            emit log_named_decimal_uint("ratio", _getAssetShareRatio(), 18);

            vm.warp(block.timestamp + 1 minutes);

            assetShareRatio = _assertAssetShareRatioGoesOnlyUp(assetShareRatio);
        }

        uint256 maxTotalShares = xSilo.totalSupply();

        _setupStream(_emissionPerSecond, block.timestamp + _streamDistribution);
        vm.warp(block.timestamp + 1 hours);

        for (uint i = 0; i < _data.length; i++) {
            emit log_named_uint("--------- redeemSilo", i);

            address user = _userAddr(i);
            uint256 amount = xSilo.balanceOf(user) * 10 / 100;
            if (amount == 0) continue;

            _data[i].redeemDuration = uint64(
                bound(_data[i].redeemDuration, xSilo.minRedeemDuration(), xSilo.maxRedeemDuration())
            );

            vm.prank(user);

            try xSilo.redeemSilo(amount, _data[i].redeemDuration) {
                emit log_named_decimal_uint("amount", amount, 18);
                emit log_named_decimal_uint("ratio", _getAssetShareRatio(), 18);
            } catch {
                // it is ok if fail in this step, this is just random simulation
            }

            vm.warp(block.timestamp + 30 minutes);

            maxTotalShares = _assertTotalSupplyOnlyDecreasingWhenNoNewDeposits(maxTotalShares);
            assetShareRatio = _assertAssetShareRatioGoesOnlyUp(assetShareRatio);
        }

        vm.warp(block.timestamp + xSilo.maxRedeemDuration() + 1);

        uint256 maxDurationToExit = xSilo.maxRedeemDuration();

        for (uint i = 0; i < _data.length; i++) {
            emit log_named_uint("\t--------- finalizeRedeem", i);

            address user = _userAddr(i);

            if (xSilo.getUserRedeemsLength(user) != 0) {
                vm.prank(user);
                xSilo.finalizeRedeem(0);
                emit log_named_uint("finalized", i);
                vm.warp(block.timestamp + 30 minutes);
            }

            uint256 shares = xSilo.balanceOf(user);
            uint256 amountByVestingDuration = xSilo.getAmountByVestingDuration(shares, maxDurationToExit);

            if (xSilo.maxWithdraw(user) != 0) {
                vm.prank(user);
                emit log_named_decimal_uint("shares to exit", shares, 18);
                xSilo.redeem(shares, user, user);
                emit log_named_decimal_uint("ratio", xSilo.convertToAssets(1e18), 18);
                vm.warp(block.timestamp + 30 minutes);
            } else if (shares != 0 && amountByVestingDuration != 0) {
                vm.prank(user);
                emit log_named_decimal_uint("redeemSilo", shares, 18);
                xSilo.redeemSilo(shares, maxDurationToExit);
                emit log_named_decimal_uint("ratio", xSilo.convertToAssets(1e18), 18);
            } else {
                emit log_named_decimal_uint("non withdrowable", shares, 18);
                stream.claimRewards();
            }

            maxTotalShares = _assertTotalSupplyOnlyDecreasingWhenNoNewDeposits(maxTotalShares);
            assetShareRatio = _assertAssetShareRatioGoesOnlyUp(assetShareRatio);
        }

        vm.warp(block.timestamp + maxDurationToExit);

        for (uint i = 0; i < _data.length; i++) {
            emit log_named_uint("--------- exiting", i);

            address user = _userAddr(i);

            if (xSilo.getUserRedeemsLength(user) != 0) {
                vm.prank(user);
                xSilo.finalizeRedeem(0);
                emit log_named_decimal_uint("ratio", _getAssetShareRatio(), 18);
                vm.warp(block.timestamp + 30 minutes);
            }

            stream.claimRewards();

            maxTotalShares = _assertTotalSupplyOnlyDecreasingWhenNoNewDeposits(maxTotalShares);
            assetShareRatio = _assertAssetShareRatioGoesOnlyUp(assetShareRatio);
        }

        assertEq(stream.pendingRewards(), 0, "all rewards should be distributed");
        // I think it might be a case when someone can not exit and xSilo will be locked
        // eg some dust that can not be converted back to Silo, but fuzzing not fining it so assets is set to 0
        assertEq(xSilo.totalSupply(), 0, "everyone should exit");
        
        if (stream.distributionEnd() <= block.timestamp) {
            assertEq(asset.balanceOf(address(stream)), 0, "stream has no balance");
        }
    }

    function _assertTotalSupplyOnlyDecreasingWhenNoNewDeposits(uint256 _prevMaxTotal)
        internal
        view
        returns (uint256 newMaxTotal)
    {
        newMaxTotal = xSilo.totalSupply();
        assertLe(newMaxTotal, _prevMaxTotal, " assert TotalSupply Only Decreasing When No New Deposits");
    }

    function _getAssetShareRatio() internal view returns (uint256 ratio) {
        ratio = xSilo.convertToAssets(1e18);
    }

    function _assertAssetShareRatioGoesOnlyUp(uint256 _prevRatio)
        internal
        view
        returns (uint256 newRatio)
    {
        newRatio = _getAssetShareRatio();

        // if there are no shares, ex last user exit, we do not check, because it will go down eg back to 1:1
        if (xSilo.totalSupply() != 0) assertGe(newRatio, _prevRatio, " asset:share ration can only go up");
    }

    function _userAddr(uint256 _i) internal returns (address addr) {
        addr = makeAddr(string.concat("user#", string(abi.encodePacked(_i + 48))));
    }

    function _setupStream(uint256 _emissionPerSecond, uint256 _distribution) internal {
        stream.setEmissions(_emissionPerSecond, block.timestamp + _distribution);
        asset.mint(address(stream), stream.fundingGap());
    }

    function _convert(address _user, uint256 _amount) internal returns (uint256 shares){
        vm.startPrank(_user);

        asset.mint(_user, _amount);
        asset.approve(address(xSilo), _amount);
        shares = xSilo.deposit(_amount, _user);

        assertGt(shares, 0, "[_convert] shares received");

        vm.stopPrank();
    }

    function _defaultSetupVerification() internal view {
        // all tests are done for this setup:

        assertEq(xSilo.minRedeemRatio(), 0.5e18, "expected initial setup for minRedeemRatio");
        assertEq(xSilo.MAX_REDEEM_RATIO(), 1e18, "expected initial setup for maxRedeemRatio");
        assertEq(xSilo.minRedeemDuration(), 0, "expected initial setup for minRedeemDuration");
        assertEq(xSilo.maxRedeemDuration(), 6 * 30 days, "expected initial setup for maxRedeemDuration");
    }

    function _assumeCustomSetup(CustomSetup memory _customSetup, bool _allowForZeros) internal {
        _customSetup.minRedeemRatio = uint64(bound(
            _customSetup.minRedeemRatio, _allowForZeros ? 0 : 1, xSilo.MAX_REDEEM_RATIO())
        );

        _customSetup.maxRedeemDuration = uint64(bound(
            _customSetup.maxRedeemDuration, _allowForZeros ? 1 : 2, 365 days)
        );

        _customSetup.minRedeemDuration = uint64(bound(
            _customSetup.minRedeemDuration, _allowForZeros ? 0 : 1, _customSetup.maxRedeemDuration - 1)
        );

        emit log_named_uint("minRedeemRatio", _customSetup.minRedeemRatio);
        emit log_named_uint("minRedeemDuration", _customSetup.minRedeemDuration);
        emit log_named_uint("maxRedeemDuration", _customSetup.maxRedeemDuration);

        try xSilo.updateRedeemSettings({
            _minRedeemRatio: _customSetup.minRedeemRatio,
            _minRedeemDuration: _customSetup.minRedeemDuration,
            _maxRedeemDuration: _customSetup.maxRedeemDuration
        }) {
            // OK
        } catch {
            vm.assume(false);
        }
    }
}
