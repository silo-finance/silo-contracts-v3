// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ShareDebtToken} from "silo-core/contracts/utils/ShareDebtToken.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
    FOUNDRY_PROFILE=core_test  forge test -vv --ffi --mc MaxRedeemDustTest
*/
contract MaxRedeemDustTest is SiloLittleHelper, Test {
    function setUp() public {
        _setUpLocalFixture();
    }

    /*
        FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxWithdraw_dust_protected
    */
    function test_maxWithdraw_dust_protected() public {
        _maxWithdraw_dust(ISilo.CollateralType.Protected);
    }

    /*
        FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxWithdraw_dust_collateral
    */
    function test_maxWithdraw_dust_collateral() public {
        _maxWithdraw_dust(ISilo.CollateralType.Collateral);
    }

    /*
        FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxWithdraw_dust_withDebt_protected
    */
    function test_maxWithdraw_dust_withDebt_protected() public {
        _maxWithdraw_dust_withDebt(ISilo.CollateralType.Protected);
    }

    /*
        FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_maxWithdraw_dust_withDebt_collateral
    */
    function test_maxWithdraw_dust_withDebt_collateral() public {
        _maxWithdraw_dust_withDebt(ISilo.CollateralType.Collateral);
    }

    function _maxWithdraw_dust(ISilo.CollateralType _type) internal {
        address depositor = makeAddr("depositor");
        address owner = address(this);
        vm.label(owner, "owner");

        _deposit(10, depositor, _type);

        (address protectedShareToken, address collateralShareToken,) = silo0.config().getShareTokens(address(silo0));

        address shareToken = _type == ISilo.CollateralType.Protected ? protectedShareToken : collateralShareToken;

        uint256 notwithrawableShares = silo0.convertToShares(1, ISilo.AssetType(uint8(_type))) - 1;
        console2.log("notwithrawableShares", notwithrawableShares);
        vm.prank(depositor);
        require(IShareToken(shareToken).transfer(owner, notwithrawableShares), "transfer failed");

        uint256 maxRedeem = silo0.maxRedeem(owner, _type);
        assertEq(maxRedeem, 0, "max redeem should return 0 because of rounding and fractions");

        vm.expectRevert();
        silo0.redeem(notwithrawableShares, owner, owner);

        vm.prank(depositor);
        require(IShareToken(shareToken).transfer(owner, 1), "transfer failed");

        silo0.redeem(IShareToken(shareToken).balanceOf(owner), owner, owner, _type);
    }

    function _maxWithdraw_dust_withDebt(ISilo.CollateralType _type) internal {
        address depositor = makeAddr("depositor");
        address owner = address(this);

        _deposit(10, depositor, _type);

        (address protectedShareToken, address collateralShareToken,) = silo0.config().getShareTokens(address(silo0));

        address shareToken = _type == ISilo.CollateralType.Protected ? protectedShareToken : collateralShareToken;

        vm.prank(depositor);
        require(IShareToken(shareToken).transfer(owner, 999), "transfer failed");

        (,, address debtShareToken) = silo1.config().getShareTokens(address(silo1));

        _depositForBorrow(9, address(2));
        _borrow(3, depositor);

        ShareDebtToken(debtShareToken).setReceiveApproval(depositor, 3);
        vm.prank(depositor);

        // we can not transfer debt if shares value is 0 (dust will be translated to 0)
        vm.expectRevert(IShareToken.RecipientNotSolventAfterTransfer.selector);
        require(IShareToken(debtShareToken).transfer(owner, 1), "transfer failed");
    }
}
