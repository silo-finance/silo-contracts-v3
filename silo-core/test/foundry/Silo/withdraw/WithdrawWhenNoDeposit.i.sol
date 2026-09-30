// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20Errors} from "openzeppelin5/interfaces/draft-IERC6093.sol";

import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";

import {TokenMock} from "silo-core/test/foundry/_mocks/TokenMock.sol";
import {SiloConfigOverride} from "../../_common/fixtures/SiloFixture.sol";
import {SiloFixture} from "../../_common/fixtures/SiloFixture.sol";

/*
    forge test -vv --ffi --mc WithdrawWhenNoDepositTest
*/
contract WithdrawWhenNoDepositTest is IntegrationTest {
    ISiloConfig siloConfig;
    ISilo silo0;
    ISilo silo1;

    TokenMock token0;
    TokenMock token1;

    function setUp() public {
        SiloFixture siloFixture = new SiloFixture();
        address t0 = makeAddr("Token0");
        address t1 = makeAddr("Token1");
        SiloConfigOverride memory configOverride;
        configOverride.token0 = t0;
        configOverride.token1 = t1;

        (siloConfig, silo0, silo1,,,) = siloFixture.deploy_local(configOverride);

        token0 = new TokenMock(t0);
        token1 = new TokenMock(t1);
    }

    /*
    forge test -vv --ffi --mt test_withdraw_zeros
    */
    function test_withdraw_zeros() public {
        vm.expectRevert(ISilo.NothingToWithdraw.selector);
        silo0.withdraw(0, address(0), address(0));
    }

    /*
    forge test -vv --ffi --mt test_withdraw_WrongAssetType
    */
    function test_withdraw_WrongAssetType() public {
        vm.expectRevert();
        silo0.withdraw(0, address(1), address(1), ISilo.CollateralType(uint8(ISilo.AssetType.Debt)));
    }

    /*
    forge test -vv --ffi --mt test_withdraw_NothingToWithdraw
    */
    function test_withdraw_NothingToWithdraw() public {
        vm.expectRevert(ISilo.NothingToWithdraw.selector);
        silo0.withdraw(0, address(this), address(this), ISilo.CollateralType.Collateral);

        vm.expectRevert(ISilo.NothingToWithdraw.selector);
        silo0.withdraw(0, address(this), address(this), ISilo.CollateralType.Protected);

        vm.expectRevert(ISilo.NothingToWithdraw.selector);
        silo0.withdraw(1, address(this), address(this), ISilo.CollateralType.Collateral);

        vm.expectRevert(ISilo.NothingToWithdraw.selector);
        silo0.withdraw(1, address(this), address(this), ISilo.CollateralType.Protected);
    }

    /*
    forge test -vv --ffi --mt test_withdraw_when_liquidity_but_NothingToWithdraw
    */
    function test_withdraw_when_liquidity_but_NothingToWithdraw() public {
        // any deposit so we have liquidity
        _anyDeposit(ISilo.CollateralType.Collateral);

        // test
        vm.expectRevert(ISilo.InputZeroShares.selector);
        silo0.withdraw(0, address(this), address(this), ISilo.CollateralType.Collateral);

        vm.expectRevert(ISilo.NothingToWithdraw.selector);
        silo0.withdraw(0, address(this), address(this), ISilo.CollateralType.Protected);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, SiloMathLib._DECIMALS_OFFSET_POW
            )
        );
        silo0.withdraw(1, address(this), address(this), ISilo.CollateralType.Collateral);

        vm.expectRevert(ISilo.NothingToWithdraw.selector);
        silo0.withdraw(1, address(this), address(this), ISilo.CollateralType.Protected);

        // any deposit so we have liquidity
        _anyDeposit(ISilo.CollateralType.Protected);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, SiloMathLib._DECIMALS_OFFSET_POW
            )
        );
        silo0.withdraw(1, address(this), address(this), ISilo.CollateralType.Protected);
    }

    function _anyDeposit(ISilo.CollateralType _type) public {
        address otherDepositor = address(1);
        uint256 depositAmount = 1e18;

        token0.transferFromMock(otherDepositor, address(silo0), depositAmount);
        vm.prank(otherDepositor);
        silo0.deposit(depositAmount, otherDepositor, _type);
    }
}
