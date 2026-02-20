// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {IERC20Errors} from "openzeppelin5/interfaces/draft-IERC6093.sol";
import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
    forge test --ffi -vv --mc WithdrawAllowanceTest
*/
contract WithdrawAllowanceTest is SiloLittleHelper, Test {
    uint256 internal constant ASSETS = 1e18;

    address immutable DEPOSITOR;
    address immutable RECEIVER;

    ISiloConfig siloConfig;

    constructor() {
        DEPOSITOR = makeAddr("Depositor");
        RECEIVER = makeAddr("Other");
    }

    function setUp() public {
        siloConfig = _setUpLocalFixture();
    }

    /*
    forge test --ffi -vv --mt test_withdraw_collateralWithoutAllowance
    */
    function test_withdraw_collateralWithoutAllowance() public {
        _deposit(ASSETS, DEPOSITOR);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(this),
                0,
                ASSETS * SiloMathLib._DECIMALS_OFFSET_POW
            )
        );
        silo0.withdraw(ASSETS, RECEIVER, DEPOSITOR);
    }

    /*
    forge test --ffi -vv --mt test_withdraw_collateralWithAllowance
    */
    function test_withdraw_collateralWithAllowance() public {
        _withdraw_WithAllowance(ISilo.CollateralType.Collateral);
    }

    function test_withdraw_protectedWithAllowance() public {
        _withdraw_WithAllowance(ISilo.CollateralType.Protected);
    }

    function _withdraw_WithAllowance(ISilo.CollateralType _type) internal {
        _deposit(ASSETS, DEPOSITOR, _type);

        (address protectedShareToken, address collateralShareToken,) = siloConfig.getShareTokens(address(silo0));

        address shareToken = _type == ISilo.CollateralType.Collateral ? collateralShareToken : protectedShareToken;
        vm.prank(DEPOSITOR);
        // forge-lint: disable-next-line(divide-before-multiply)
        IShareToken(shareToken).approve(address(this), (ASSETS / 2) * SiloMathLib._DECIMALS_OFFSET_POW);

        assertEq(token0.balanceOf(RECEIVER), 0, "no balance before");

        silo0.withdraw(ASSETS / 2, RECEIVER, DEPOSITOR, _type);

        assertEq(token0.balanceOf(RECEIVER), ASSETS / 2, "receiver got tokens");
        assertEq(IShareToken(shareToken).allowance(DEPOSITOR, address(this)), 0, "allowance used");

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, SiloMathLib._DECIMALS_OFFSET_POW
            )
        );
        silo0.withdraw(1, RECEIVER, DEPOSITOR, _type);

        _withdraw(ASSETS / 2, DEPOSITOR, _type);
        assertEq(token0.balanceOf(DEPOSITOR), ASSETS / 2, "depositor got the rest");
    }
}
