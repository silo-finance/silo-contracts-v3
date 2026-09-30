// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin5/token/ERC20/utils/SafeERC20.sol";

import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";

import {Hook} from "silo-core/contracts/lib/Hook.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ICrossReentrancyGuard} from "silo-core/contracts/interfaces/ICrossReentrancyGuard.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {PartialLiquidation} from "silo-core/contracts/hooks/liquidation/PartialLiquidation.sol";

import {SiloConfigOverride} from "../../_common/fixtures/SiloFixture.sol";
import {SiloFixture} from "../../_common/fixtures/SiloFixture.sol";
import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";
import {MintableToken} from "../../_common/MintableToken.sol";

/*
FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mc TransitionCollateralReentrancyTest
*/
contract TransitionCollateralReentrancyTest is SiloLittleHelper, Test, PartialLiquidation {
    using Hook for uint256;
    using SafeERC20 for IERC20;

    bool afterActionExecuted;

    function setUp() public {
        SiloFixture siloFixture = new SiloFixture();
        SiloConfigOverride memory configOverride;

        token0 = new MintableToken(6);
        token1 = new MintableToken(7);
        configOverride.token0 = address(token0);
        configOverride.token1 = address(token1);
        configOverride.hookReceiver = address(this);
        configOverride.configName = SiloConfigsNames.SILO_LOCAL_DEPLOYER;

        (siloConfig, silo0, silo1,,,) = siloFixture.deploy_local(configOverride);
        partialLiquidation = this;

        silo0.updateHooks();
    }

    function initialize(ISiloConfig, bytes calldata) public override {}

    function hookReceiverConfig(address _silo)
        external
        view
        override
        returns (uint24 hooksBefore, uint24 hooksAfter)
    {
        hooksBefore = 0;
        hooksAfter = _silo == address(silo0) ? uint24(Hook.COLLATERAL_TOKEN | Hook.SHARE_TOKEN_TRANSFER) : 0;
    }

    function beforeAction(address, uint256, bytes calldata) external pure override {
        revert("not in use");
    }

    function afterAction(address _silo, uint256 _action, bytes calldata _input) external override {
        assertEq(_silo, address(silo0), "hook setup is only for silo0");
        assertTrue(
            _action.matchAction(Hook.COLLATERAL_TOKEN | Hook.SHARE_TOKEN_TRANSFER),
            "hook setup is only for share transfer"
        );

        Hook.AfterTokenTransfer memory input = Hook.afterTokenTransferDecode(_input);
        address borrower = input.sender;

        if (silo0.isSolvent(borrower)) return; // we want insolvent case

        token1.mint(address(this), 5);
        IERC20(token1).safeIncreaseAllowance(address(partialLiquidation), 5);

        afterActionExecuted = true;

        (uint256 collateralToLiquidate, uint256 debtToRepay,) = partialLiquidation.maxLiquidation(borrower);

        assertEq(collateralToLiquidate, 3, "collateralToLiquidate (5 - 2 underestimation)");
        assertEq(debtToRepay, 5, "debtToRepay");

        vm.expectRevert(ICrossReentrancyGuard.CrossReentrantCall.selector);
        partialLiquidation.liquidationCall(address(token0), address(token1), borrower, debtToRepay, false);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_transitionCollateral2protected_liquidationReverts
    */
    function test_transitionCollateral2protected_liquidationReverts() public {
        address borrower = makeAddr("borrower");
        _depositForBorrow(5, makeAddr("depositor"));
        uint256 depositedShares = _deposit(10, borrower);
        _borrow(5, borrower);

        vm.prank(borrower);
        silo0.transitionCollateral(depositedShares / 2, borrower, ISilo.CollateralType.Collateral);

        assertTrue(afterActionExecuted, "afterActionExecuted");
        assertTrue(silo0.isSolvent(borrower), "borrower is solvent after transition of collateral");

        (, ISiloConfig.ConfigData memory debt) = siloConfig.getConfigsForSolvency(borrower);

        assertTrue(silo0.isSolvent(borrower), "borrower is solvent after transition of collateral");
        assertTrue(debt.silo != address(0), "borrower has debt");
    }
}
