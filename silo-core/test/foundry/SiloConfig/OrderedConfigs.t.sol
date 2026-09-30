// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ISiloConfig, SiloConfig} from "silo-core/contracts/SiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

// covered cases:
// - `withdraw`             no debt
// - `withdraw`             debt silo0  | debt not the same asset
// - `withdraw`             debt silo0  | debt same asset
// - `withdraw`             debt silo1  | debt not the same asset
// - `withdraw`             debt silo1  | debt same asset
// - `borrow`               not the same asset
// - `borrow`               the same asset
// - `getConfigsForSolvency`           no debt
// - `getConfigsForSolvency`           debt silo0  | not the same asset
// - `getConfigsForSolvency`           debt silo0  | the same asset
// - `getConfigsForSolvency`           debt silo1  | not the same asset
// - `getConfigsForSolvency`           debt silo1  | the same asset
//
// FOUNDRY_PROFILE=core_test forge test -vv --mc OrderedConfigsTest
contract OrderedConfigsTest is Test {
    address internal _siloUser = makeAddr("siloUser");
    address internal _wrongSilo = makeAddr("wrongSilo");
    address internal _silo0 = makeAddr("silo0");
    address internal _silo1 = makeAddr("silo1");
    address internal _hookReceiver = makeAddr("hookReceiver");

    ISiloConfig.ConfigData internal _configData0;
    ISiloConfig.ConfigData internal _configData1;

    SiloConfig internal _siloConfig;

    function setUp() public {
        _configData0.silo = _silo0;
        _configData0.token = makeAddr("token0");
        _configData0.collateralShareToken = makeAddr("collateralShareToken0");
        _configData0.protectedShareToken = makeAddr("protectedShareToken0");
        _configData0.debtShareToken = makeAddr("debtShareToken0");
        _configData0.hookReceiver = _hookReceiver;

        _configData1.silo = _silo1;
        _configData1.token = makeAddr("token1");
        _configData1.collateralShareToken = makeAddr("collateralShareToken1");
        _configData1.protectedShareToken = makeAddr("protectedShareToken1");
        _configData1.debtShareToken = makeAddr("debtShareToken1");
        _configData1.hookReceiver = _hookReceiver;

        _siloConfig = siloConfigDeploy(1, _configData0, _configData1);

        _mockAccrueInterestCalls(_configData0, _configData1);
        _mockShareTokensBalances(_siloUser, 0, 0);
    }

    function siloConfigDeploy(
        uint256 _siloId,
        ISiloConfig.ConfigData memory _configDataInput0,
        ISiloConfig.ConfigData memory _configDataInput1
    ) public returns (SiloConfig siloConfig) {
        vm.assume(_configDataInput0.silo != _wrongSilo);
        vm.assume(_configDataInput1.silo != _wrongSilo);
        vm.assume(_configDataInput0.silo != _configDataInput1.silo);
        vm.assume(_configDataInput0.daoFee < 0.5e18);
        vm.assume(_configDataInput0.deployerFee < 0.5e18);

        // when using assume, it reject too many inputs
        _configDataInput0.hookReceiver = _configDataInput1.hookReceiver;
        _configDataInput0.hookReceiver = _configDataInput1.hookReceiver;

        _configDataInput1.daoFee = _configDataInput0.daoFee;
        _configDataInput1.deployerFee = _configDataInput0.deployerFee;

        siloConfig = new SiloConfig(_siloId, _configDataInput0, _configDataInput1);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --mt testOrderedConfigsWithdrawNoDebt
    function testOrderedConfigsWithdrawNoDebt() public view {
        ISiloConfig.DepositConfig memory depositConfig;
        ISiloConfig.ConfigData memory collateralConfig;
        ISiloConfig.ConfigData memory debtConfig;

        (depositConfig, collateralConfig, debtConfig) = _siloConfig.getConfigsForWithdraw(_silo0, _siloUser);

        assertEq(depositConfig.silo, _silo0);
        assertEq(collateralConfig.silo, address(0));
        assertEq(debtConfig.silo, address(0));

        (depositConfig, collateralConfig, debtConfig) = _siloConfig.getConfigsForWithdraw(_silo1, _siloUser);

        assertEq(depositConfig.silo, _silo1);
        assertEq(collateralConfig.silo, address(0));
        assertEq(debtConfig.silo, address(0));
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --mt testOrderedConfigsWithdrawDebtSilo0NotSameAsset
    function testOrderedConfigsWithdrawDebtSilo0NotSameAsset() public {
        _mockShareTokensBalances(_siloUser, 1, 0);

        vm.prank(_silo0);
        _siloConfig.setOtherSiloAsCollateralSilo(_siloUser);

        ISiloConfig.DepositConfig memory depositConfig;
        ISiloConfig.ConfigData memory collateralConfig;
        ISiloConfig.ConfigData memory debtConfig;

        (depositConfig, collateralConfig, debtConfig) = _siloConfig.getConfigsForWithdraw(_silo0, _siloUser);

        assertEq(depositConfig.silo, _silo0);
        assertEq(collateralConfig.silo, _silo1);
        assertEq(debtConfig.silo, _silo0);
        _assertForSilo0DebtSilo0NotSameAsset(collateralConfig, debtConfig);

        (depositConfig, collateralConfig, debtConfig) = _siloConfig.getConfigsForWithdraw(_silo1, _siloUser);

        assertEq(depositConfig.silo, _silo1);
        assertEq(collateralConfig.silo, _silo1);
        assertEq(debtConfig.silo, _silo0);
        _assertForSilo1DebtSilo0NotSameAsset(collateralConfig, debtConfig);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --mt testOrderedConfigsWithdrawDebtSilo1NotSameAsset
    function testOrderedConfigsWithdrawDebtSilo1NotSameAsset() public {
        _mockShareTokensBalances(_siloUser, 0, 1);

        vm.prank(_silo1);
        _siloConfig.setOtherSiloAsCollateralSilo(_siloUser);

        ISiloConfig.DepositConfig memory depositConfig;
        ISiloConfig.ConfigData memory collateralConfig;
        ISiloConfig.ConfigData memory debtConfig;

        (depositConfig, collateralConfig, debtConfig) = _siloConfig.getConfigsForWithdraw(_silo0, _siloUser);

        assertEq(depositConfig.silo, _silo0);
        assertEq(collateralConfig.silo, _silo0);
        assertEq(debtConfig.silo, _silo1);
        _assertForSilo0DebtSilo1NotSameAsset(collateralConfig, debtConfig);

        (depositConfig, collateralConfig, debtConfig) = _siloConfig.getConfigsForWithdraw(_silo1, _siloUser);

        assertEq(depositConfig.silo, _silo1);
        assertEq(collateralConfig.silo, _silo0);
        assertEq(debtConfig.silo, _silo1);
        _assertForSilo1DebtSilo1NotSameAsset(collateralConfig, debtConfig);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --mt testOrderedConfigsBorrowNoDebtNotSameAsset
    function testOrderedConfigsBorrowNoDebtNotSameAsset() public view {
        ISiloConfig.ConfigData memory collateralConfig;
        ISiloConfig.ConfigData memory debtConfig;

        (collateralConfig, debtConfig) = _siloConfig.getConfigsForBorrow({_debtSilo: _silo0});

        assertEq(collateralConfig.silo, _silo1);
        assertEq(debtConfig.silo, _silo0);

        (collateralConfig, debtConfig) = _siloConfig.getConfigsForBorrow({_debtSilo: _silo1});

        assertEq(collateralConfig.silo, _silo0);
        assertEq(debtConfig.silo, _silo1);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --mt testGetConfigsNoDebt
    function testGetConfigsNoDebt() public view {
        ISiloConfig.ConfigData memory collateralConfig;
        ISiloConfig.ConfigData memory debtConfig;

        (collateralConfig, debtConfig) = _siloConfig.getConfigsForSolvency(_siloUser);

        assertEq(collateralConfig.silo, address(0));
        assertEq(debtConfig.silo, address(0));
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --mt testGetConfigsDebtSilo0NotSameAsset
    function testGetConfigsDebtSilo0NotSameAsset() public {
        _mockShareTokensBalances(_siloUser, 1, 0);

        vm.prank(_silo0);
        _siloConfig.setOtherSiloAsCollateralSilo(_siloUser);

        ISiloConfig.ConfigData memory collateralConfig;
        ISiloConfig.ConfigData memory debtConfig;

        (collateralConfig, debtConfig) = _siloConfig.getConfigsForSolvency(_siloUser);

        assertEq(collateralConfig.silo, _silo1);
        assertEq(debtConfig.silo, _silo0);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --mt testGetConfigsDebtSil1NotSameAsset
    function testGetConfigsDebtSil1NotSameAsset() public {
        _mockShareTokensBalances(_siloUser, 0, 1);

        vm.prank(_silo1);
        _siloConfig.setOtherSiloAsCollateralSilo(_siloUser);

        ISiloConfig.ConfigData memory collateralConfig;
        ISiloConfig.ConfigData memory debtConfig;

        (collateralConfig, debtConfig) = _siloConfig.getConfigsForSolvency(_siloUser);

        assertEq(collateralConfig.silo, _silo0);
        assertEq(debtConfig.silo, _silo1);
    }
    
    function _assertForSilo0DebtSilo1NotSameAsset(
        ISiloConfig.ConfigData memory collateral,
        ISiloConfig.ConfigData memory debt
    ) internal view {
        assertTrue(debt.silo != address(0), "debtPresent true");
        assertTrue(debt.silo != collateral.silo, "sameAsset false");
        assertTrue(debt.silo != _silo0, "debtInSilo0 false");
    }

    function _assertForSilo1DebtSilo1NotSameAsset(
        ISiloConfig.ConfigData memory collateral,
        ISiloConfig.ConfigData memory debt
    ) internal view {
        _assertForSilo0DebtSilo1NotSameAsset(collateral, debt);
    }

    function _assertForSilo0DebtSilo0SameAsset(
        ISiloConfig.ConfigData memory collateral,
        ISiloConfig.ConfigData memory debt
    ) internal view {
        assertTrue(debt.silo != address(0), "debtPresent true");
        assertTrue(debt.silo == collateral.silo, "sameAsset true");
        assertTrue(debt.silo == _silo0, "debtInSilo0 true");
    }

    function _assertForSilo1DebtSilo0SameAsset(
        ISiloConfig.ConfigData memory collateral,
        ISiloConfig.ConfigData memory debt
    ) internal view {
        _assertForSilo0DebtSilo0SameAsset(collateral, debt);
    }

    function _assertForSilo0DebtSilo0NotSameAsset(
        ISiloConfig.ConfigData memory collateral,
        ISiloConfig.ConfigData memory debt
    ) internal view {
        assertTrue(debt.silo != address(0), "debtPresent true");
        assertTrue(debt.silo != collateral.silo, "sameAsset false");
        assertTrue(debt.silo == _silo0, "debtInSilo0 true");
    }

    function _assertForSilo1DebtSilo0NotSameAsset(
        ISiloConfig.ConfigData memory collateral,
        ISiloConfig.ConfigData memory debt
    ) internal view {
        _assertForSilo0DebtSilo0NotSameAsset(collateral, debt);
    }

    function _mockAccrueInterestCalls(
        ISiloConfig.ConfigData memory _configDataInput0,
        ISiloConfig.ConfigData memory _configDataInput1
    ) internal {
        vm.mockCall(
            _silo0,
            abi.encodeCall(
                ISilo.accrueInterestForConfig,
                (_configDataInput0.interestRateModel, _configDataInput0.daoFee, _configDataInput0.deployerFee)
            ),
            abi.encode(true)
        );

        vm.mockCall(
            _silo1,
            abi.encodeCall(
                ISilo.accrueInterestForConfig,
                (_configDataInput1.interestRateModel, _configDataInput1.daoFee, _configDataInput1.deployerFee)
            ),
            abi.encode(true)
        );
    }

    function _mockShareTokensBalances(address _user, uint256 _balance0, uint256 _balance1) internal {
        vm.mockCall(_configData0.debtShareToken, abi.encodeCall(IERC20.balanceOf, _user), abi.encode(_balance0));

        vm.mockCall(_configData1.debtShareToken, abi.encodeCall(IERC20.balanceOf, _user), abi.encode(_balance1));
    }
}
