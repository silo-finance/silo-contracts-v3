// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";

import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";
import {HookReceiverMock} from "silo-core/test/foundry/_mocks/HookReceiverMock.sol";

import {MintableToken} from "../../_common/MintableToken.sol";
import {SiloConfigOverride} from "../../_common/fixtures/SiloFixture.sol";
import {SiloFixture} from "../../_common/fixtures/SiloFixture.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
    forge test -vv --ffi --mc WithdrawWhenNoDebtTest
*/
contract WithdrawWhenNoDebtTest is SiloLittleHelper, Test {
    ISiloConfig siloConfig;

    function setUp() public {
        token0 = new MintableToken(18);
        token1 = new MintableToken(18);

        // Setting the hook receiver mock to force Actions lib _hookCallAfter fn execution
        HookReceiverMock hookReceiverMock = new HookReceiverMock(address(0));
        // Hook receiver config doesn't matter for this test
        hookReceiverMock.hookReceiverConfigMock(0, 0);

        SiloConfigOverride memory overrides;
        overrides.token0 = address(token0);
        overrides.token1 = address(token1);
        overrides.hookReceiver = hookReceiverMock.ADDRESS();
        overrides.configName = SiloConfigsNames.SILO_LOCAL_DEPLOYER;

        SiloFixture siloFixture = new SiloFixture();

        address hook;
        (siloConfig, silo0, silo1,,, hook) = siloFixture.deploy_local(overrides);
        partialLiquidation = IPartialLiquidation(hook);
    }

    /*
    forge test -vv --ffi --mt test_withdraw_all_Collateral
    */
    function test_withdraw_all_Collateral() public {
        _deposit(address(this), 2e18, ISilo.CollateralType.Collateral);
        _deposit(address(this), 1e18, ISilo.CollateralType.Protected);

        (address protectedShareToken, address collateralShareToken, address debtShareToken) =
            siloConfig.getShareTokens(address(silo0));
        uint256 sharesBefore = IShareToken(collateralShareToken).balanceOf(address(this));

        assertEq(silo0.maxWithdraw(address(this)), 2e18 - 1, "available collateral");

        uint256 gotShares = _withdraw(address(this), 2e18, ISilo.CollateralType.Collateral);

        assertEq(IShareToken(debtShareToken).balanceOf(address(this)), 0, "debtShareToken");
        assertEq(
            IShareToken(protectedShareToken).balanceOf(address(this)),
            1e18 * SiloMathLib._DECIMALS_OFFSET_POW,
            "protectedShareToken stays the same"
        );
        assertEq(IShareToken(collateralShareToken).balanceOf(address(this)), 0, "collateral burned");
        assertEq(gotShares, sharesBefore, "withdraw all shares");

        assertEq(silo0.getCollateralAssets(), 0, "CollateralAssets should be withdrawn");
    }

    /*
    forge test -vv --ffi --mt test_withdraw_all_Protected
    */
    function test_withdraw_all_Protected() public {
        _deposit(address(this), 2e18, ISilo.CollateralType.Collateral);
        _deposit(address(this), 1e18, ISilo.CollateralType.Protected);

        (address protectedShareToken, address collateralShareToken, address debtShareToken) =
            siloConfig.getShareTokens(address(silo0));
        uint256 sharesBefore = IShareToken(protectedShareToken).balanceOf(address(this));

        assertEq(silo0.maxWithdraw(address(this)), 2e18 - 1, "available collateral");

        uint256 gotShares = _withdraw(address(this), 1e18, ISilo.CollateralType.Protected);

        assertEq(silo0.maxWithdraw(address(this)), 2e18 - 1, "available collateral");

        assertEq(IShareToken(debtShareToken).balanceOf(address(this)), 0, "debtShareToken");
        assertEq(IShareToken(protectedShareToken).balanceOf(address(this)), 0, "protectedShareToken stays the same");
        assertEq(
            IShareToken(collateralShareToken).balanceOf(address(this)),
            2e18 * SiloMathLib._DECIMALS_OFFSET_POW,
            "collateral burned"
        );
        assertEq(gotShares, sharesBefore, "withdraw all shares");

        assertEq(silo0.getTotalAssetsStorage(ISilo.AssetType.Protected), 0, "protected Assets should be withdrawn");
    }

    /*
    forge test -vv --ffi --mt test_withdraw_scenario_oneUser
    */
    function test_withdraw_scenario_oneUser() public {
        _deposit(address(this), 2e18, ISilo.CollateralType.Collateral);
        _deposit(address(this), 1e18, ISilo.CollateralType.Protected);

        _userWithdrawing_oneUser();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_withdraw_scenario_manyUsers
    */
    function test_withdraw_scenario_manyUsers() public {
        _deposit(address(5555), 1, ISilo.CollateralType.Protected);
        _deposit(address(6666), 1, ISilo.CollateralType.Collateral);

        _deposit(address(this), 2e18, ISilo.CollateralType.Collateral);
        _deposit(address(this), 1e18, ISilo.CollateralType.Protected);

        _userWithdrawing();

        _deposit(address(3344), 11e18, ISilo.CollateralType.Protected);
        _deposit(address(3344), 22e18, ISilo.CollateralType.Collateral);

        _deposit(address(this), 2e18, ISilo.CollateralType.Collateral);
        _deposit(address(this), 1e18, ISilo.CollateralType.Protected);

        _userWithdrawing();

        assertEq(
            silo0.getTotalAssetsStorage(ISilo.AssetType.Protected),
            11e18 + 1,
            "protected Assets should be withdrawn"
        );
        assertEq(silo0.getCollateralAssets(), 22e18 + 1, "protected Assets should be withdrawn");
    }

    /*
    forge test -vv --ffi --mt test_withdraw_scenarios_fuzz
    */
    function test_withdraw_scenarios_fuzz(uint256 _deposit1, uint256 _deposit2, uint256 _deposit3) public {
        vm.assume(_deposit1 > 2 && _deposit1 < 2 ** 128);
        vm.assume(_deposit2 != 0 && _deposit2 < 2 ** 128);
        vm.assume(_deposit3 != 0 && _deposit3 < 2 ** 128);

        _deposit(address(1), _deposit1, ISilo.CollateralType.Protected);
        _deposit(address(1), _deposit1, ISilo.CollateralType.Collateral);

        _deposit(address(2), _deposit2, ISilo.CollateralType.Protected);
        _deposit(address(2), _deposit2, ISilo.CollateralType.Collateral);

        _withdraw(address(1), _deposit1 / 2, ISilo.CollateralType.Protected);
        _withdraw(address(1), _deposit1 / 2, ISilo.CollateralType.Collateral);

        _deposit(address(3), _deposit3, ISilo.CollateralType.Protected);
        _deposit(address(3), _deposit3, ISilo.CollateralType.Collateral);

        _withdraw(address(2), _deposit2, ISilo.CollateralType.Protected);
        _withdraw(address(2), _deposit2, ISilo.CollateralType.Collateral);

        _withdraw(address(3), _deposit3, ISilo.CollateralType.Protected);
        _withdraw(address(3), _deposit3, ISilo.CollateralType.Collateral);

        _withdraw(address(1), _deposit1 - _deposit1 / 2, ISilo.CollateralType.Protected);
        _withdraw(address(1), _deposit1 - _deposit1 / 2, ISilo.CollateralType.Collateral);

        assertEq(silo0.getTotalAssetsStorage(ISilo.AssetType.Protected), 0, "protected Assets should be withdrawn");
        assertEq(silo0.getCollateralAssets(), 0, "protected Assets should be withdrawn");
    }

    function _userWithdrawing() internal {
        (address protectedShareToken, address collateralShareToken, address debtShareToken) =
            siloConfig.getShareTokens(address(silo0));

        // +/-1 are here because we underestimated for fractions in maxWithdraw function and in test we compensate for it

        assertEq(silo0.maxWithdraw(address(this)), 2e18 - 1, "available collateral #1");

        uint256 gotShares = _withdraw(address(this), 0.1e18, ISilo.CollateralType.Protected);
        assertEq(gotShares, 0.1e18 * SiloMathLib._DECIMALS_OFFSET_POW, "withdraw 0.1e18");
        assertEq(silo0.maxWithdraw(address(this)), 2e18 - 1, "available collateral #2");

        gotShares = _withdraw(address(this), 0.1e18, ISilo.CollateralType.Collateral);
        assertEq(gotShares, 0.1e18 * SiloMathLib._DECIMALS_OFFSET_POW, "withdraw 0.1e18");
        assertEq(silo0.maxWithdraw(address(this)), 1.9e18 - 1, "available collateral #3");

        gotShares = _withdraw(address(this), 123456781234567893, ISilo.CollateralType.Protected);
        assertEq(gotShares, 123456781234567893 * SiloMathLib._DECIMALS_OFFSET_POW, "withdraw 123456781234567893 P");
        assertEq(silo0.maxWithdraw(address(this)), 1.9e18 - 1, "available collateral #4");

        gotShares = _withdraw(address(this), 123456781234567893, ISilo.CollateralType.Collateral);
        assertEq(gotShares, 123456781234567893 * SiloMathLib._DECIMALS_OFFSET_POW, "withdraw 123456781234567893 C");
        assertEq(silo0.maxWithdraw(address(this)), 1.9e18 - 123456781234567893 - 1, "available collateral #5");

        gotShares = _withdraw(address(this), silo0.maxWithdraw(address(this)) + 1, ISilo.CollateralType.Collateral);
        assertEq(gotShares, (1.9e18 - 123456781234567893) * SiloMathLib._DECIMALS_OFFSET_POW, "max withdraw C");
        assertEq(silo0.maxWithdraw(address(this)), 0, "available collateral #6");

        gotShares = _withdraw(address(this), 1e18 - 0.1e18 - 123456781234567893, ISilo.CollateralType.Protected);
        assertEq(gotShares, 776543218765432107 * SiloMathLib._DECIMALS_OFFSET_POW, "withdraw all P");

        assertEq(IShareToken(debtShareToken).balanceOf(address(this)), 0, "debtShareToken");
        assertEq(IShareToken(protectedShareToken).balanceOf(address(this)), 0, "protectedShareToken stays the same");
        assertEq(IShareToken(collateralShareToken).balanceOf(address(this)), 0, "collateral shares are burned");
    }

    function _userWithdrawing_oneUser() internal {
        (address protectedShareToken, address collateralShareToken, address debtShareToken) =
            siloConfig.getShareTokens(address(silo0));

        assertEq(silo0.maxWithdraw(address(this)), 2e18 - 1, "available collateral #1");

        uint256 gotShares = _withdraw(address(this), 0.1e18, ISilo.CollateralType.Protected);
        assertEq(gotShares, 0.1e18 * SiloMathLib._DECIMALS_OFFSET_POW, "withdraw 0.1e18");
        assertEq(silo0.maxWithdraw(address(this)), 2e18 - 1, "available collateral #2");

        gotShares = _withdraw(address(this), 0.1e18, ISilo.CollateralType.Collateral);
        assertEq(gotShares, 0.1e18 * SiloMathLib._DECIMALS_OFFSET_POW, "withdraw 0.1e18");
        assertEq(silo0.maxWithdraw(address(this)), 1.9e18 - 1, "available collateral #3");

        gotShares = _withdraw(address(this), 123456781234567893, ISilo.CollateralType.Protected);
        assertEq(gotShares, 123456781234567893 * SiloMathLib._DECIMALS_OFFSET_POW, "withdraw 123456781234567893 P");
        assertEq(silo0.maxWithdraw(address(this)), 1.9e18 - 1, "available collateral #4");

        gotShares = _withdraw(address(this), 123456781234567893, ISilo.CollateralType.Collateral);
        assertEq(gotShares, 123456781234567893 * SiloMathLib._DECIMALS_OFFSET_POW, "withdraw 123456781234567893 C");
        assertEq(silo0.maxWithdraw(address(this)), 1.9e18 - 123456781234567893 - 1, "available collateral #5");

        gotShares = _withdraw(address(this), silo0.maxWithdraw(address(this)), ISilo.CollateralType.Collateral);
        assertEq(gotShares, (1.9e18 - 123456781234567893 - 1) * SiloMathLib._DECIMALS_OFFSET_POW, "max withdraw");
        assertEq(silo0.maxWithdraw(address(this)), 0, "available collateral #6");

        gotShares = _withdraw(address(this), 1e18 - 0.1e18 - 123456781234567893, ISilo.CollateralType.Protected);
        assertEq(gotShares, 776543218765432107 * SiloMathLib._DECIMALS_OFFSET_POW, "withdraw all P");

        assertEq(IShareToken(debtShareToken).balanceOf(address(this)), 0, "debtShareToken");
        assertEq(IShareToken(protectedShareToken).balanceOf(address(this)), 0, "protectedShareToken stays the same");
        assertEq(IShareToken(collateralShareToken).balanceOf(address(this)), 1e3, "collateral burned");
    }

    function _deposit(address _depositor, uint256 _amount, ISilo.CollateralType _type) internal {
        token0.mint(_depositor, _amount);
        vm.prank(_depositor);
        token0.approve(address(silo0), _amount);
        vm.prank(_depositor);
        silo0.deposit(_amount, _depositor, _type);
    }

    function _withdraw(address _depositor, uint256 _amount, ISilo.CollateralType _type)
        internal
        returns (uint256 assets)
    {
        vm.prank(_depositor);
        return silo0.withdraw(_amount, _depositor, _depositor, _type);
    }
}
