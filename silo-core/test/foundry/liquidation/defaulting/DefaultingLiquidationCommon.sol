// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";

import {Math} from "openzeppelin5/utils/math/Math.sol";
import {Ownable} from "openzeppelin5/access/Ownable.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IPartialLiquidation} from "silo-core/contracts/interfaces/IPartialLiquidation.sol";
import {IPartialLiquidationByDefaulting} from "silo-core/contracts/interfaces/IPartialLiquidationByDefaulting.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISiloIncentivesController} from "silo-core/contracts/incentives/interfaces/ISiloIncentivesController.sol";
import {IGaugeHookReceiver} from "silo-core/contracts/interfaces/IGaugeHookReceiver.sol";
import {SiloIncentivesControllerCompatible} from
    "silo-core/contracts/incentives/SiloIncentivesControllerCompatible.sol";

import {SiloConfigOverride, SiloFixture} from "../../_common/fixtures/SiloFixture.sol";
import {MintableToken} from "silo-core/test/foundry/_common/MintableToken.sol";
import {SiloLensLib} from "silo-core/contracts/lib/SiloLensLib.sol";
import {DefaultingSiloLogic} from "silo-core/contracts/hooks/defaulting/DefaultingSiloLogic.sol";
import {Whitelist} from "silo-core/contracts/hooks/_common/Whitelist.sol";

import {DummyOracle} from "silo-core/test/foundry/_common/DummyOracle.sol";
import {DefaultingLiquidationAsserts} from "./common/DefaultingLiquidationAsserts.sol";
import {RevertLib} from "silo-core/contracts/lib/RevertLib.sol";
import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

/*
- anything with decimals? don't think so, we only transfer shares
- fees should be able to withdraw always? no, we might need liquidity or repay
- input is often limited to ~uint48 because of `immediate distribution overflow`


FOUNDRY_PROFILE=core_test forge test --ffi --mc DefaultingLiquidationBorrowable -vv

*/
abstract contract DefaultingLiquidationCommon is DefaultingLiquidationAsserts {
    using SafeCast for int256;

    using SiloLensLib for ISilo;

    function setUp() public virtual {
        token0 = new MintableToken(18);
        token1 = new MintableToken(18);

        oracle0 = new DummyOracle(1e18, address(token1)); // 1:1 price

        token0.setOnDemand(true);
        token1.setOnDemand(true);

        SiloConfigOverride memory overrides;
        overrides.token0 = address(token0);
        overrides.token1 = address(token1);
        overrides.solvencyOracle0 = address(oracle0);
        overrides.maxLtvOracle0 = address(oracle0);
        overrides.configName = _useConfigName();

        SiloFixture siloFixture = new SiloFixture();

        address hook;
        (siloConfig, silo0, silo1,,, hook) = siloFixture.deploy_local(overrides);

        partialLiquidation = IPartialLiquidation(hook);
        defaulting = IPartialLiquidationByDefaulting(hook);

        (address collateralAsset, address debtAsset) = _getTokens();
        (ISilo collateralSilo, ISilo debtSilo) = _getSilos();

        assertEq(collateralSilo.asset(), collateralAsset, "[crosscheck] asset must much silo asset");
        assertEq(debtSilo.asset(), debtAsset, "[crosscheck] asset must much silo asset");

        vm.label(address(this), "TESTER");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_setup -vv
    */
    function test_defaulting_setup() public {
        _addLiquidity(2);

        // minimal collateral to create position is 2
        assertTrue(
            _createPosition({_borrower: borrower, _collateral: 0, _protected: 2, _maxOut: true}),
            "create position failed"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_happyPath -vv
    */
    function test_defaulting_happyPath_oneBorrower() public virtual;

    function test_defaulting_happyPath_twoBorrowers() public virtual;

    /*
    - borrower deposit 1e18 assets, 50% collateral, 50% protected
    - price is 1.02e18 at begin and the drop to 1e18, so at the moment of liquidation is 1:1 so we can easily use collateral/debt
    */
    function _defaulting_happyPath(bool _withOtherBorrower)
        internal
        returns (
            UserState memory borrowerCollateralBefore,
            UserState memory borrowerDebtBefore,
            SiloState memory collateralSiloBefore,
            SiloState memory debtSiloBefore,
            uint256 collateralToLiquidate,
            uint256 debtToRepay
        )
    {
        (ISilo collateralSilo, ISilo debtSilo) = _getSilos();

        _createIncentiveController();

        uint256 assets = 1e18;
        _addLiquidity(assets);

        _setCollateralPrice(1.02e18);

        address protectedUser = makeAddr("protectedUser");
        vm.prank(protectedUser);
        debtSilo.deposit(assets, protectedUser, ISilo.CollateralType.Protected);
        depositors.push(protectedUser);

        bool success;

        if (_withOtherBorrower) {
            success = _createPosition({
                _borrower: makeAddr("otherBorrower"),
                _collateral: assets / 2,
                _protected: assets / 2,
                _maxOut: false
            });
            vm.assume(success);
            _addLiquidity(assets);
        }

        success =
            _createPosition({_borrower: borrower, _collateral: assets / 2, _protected: assets / 2, _maxOut: true});
        assertTrue(success, "create position failed");

        // DO NOT REMOVE LIQUIDITY, we need to check how much provider looses

        _setCollateralPrice(1e18); // 2% down

        do {
            vm.warp(block.timestamp + 2 hours);
        } while (!_defaultingPossible(borrower));

        _printLtv(borrower);

        debtSilo.accrueInterest();
        (uint256 revenue, uint256 revenueFractions) = _printRevenue(debtSilo);
        assertTrue(revenue > 0 || revenueFractions > 0, "we need case with fees");

        borrowerCollateralBefore = _getUserState(collateralSilo, borrower);
        borrowerDebtBefore = _getUserState(debtSilo, borrower);
        collateralSiloBefore = _getSiloState(collateralSilo);
        debtSiloBefore = _getSiloState(debtSilo);

        console2.log("maxRepay borrower:", debtSilo.maxRepay(borrower));
        console2.log("maxRepay other borrower:", debtSilo.maxRepay(makeAddr("otherBorrower")));

        (collateralToLiquidate, debtToRepay) = defaulting.liquidationCallByDefaulting(borrower);
        console2.log("AFTER DEFAULTING what happened?");

        _assertProtectedRatioDidNotchanged();

        console2.log("maxRepay borrower:", debtSilo.maxRepay(borrower));
        console2.log("maxRepay other borrower:", debtSilo.maxRepay(makeAddr("otherBorrower")));

        token0.setOnDemand(false);
        token1.setOnDemand(false);

        assertTrue(silo0.isSolvent(borrower), "borrower is solvent");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_neverReverts_badDebt_fuzz -vv --fuzz-runs 3333
    locally: 3s
    */
    function test_defaulting_neverReverts_badDebt_fuzz(uint32 _collateral, uint32 _protected, uint32 _warp) public {
        _defaulting_neverReverts_badDebt({
            _borrower: borrower,
            _collateral: _collateral,
            _protected: _protected,
            _warp: _warp
        });
    }

    /*
    when we use high amoutst, only immediate distrobution can overflow
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_ImmediateDistributionOverflows -vv --mc DefaultingLiquidationBorrowable0Test
    locally: 2s
    */
    function test_defaulting_ImmediateDistributionOverflows_fuzz(uint256 _collateral, uint32 _warp) public {
        _defaulting_ImmediateDistributionOverflows(_collateral, _warp);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_ImmediateDistributionOverflows_uint104_fuzz -vv
    */
    function test_defaulting_ImmediateDistributionOverflows_uint104_fuzz(uint32 _warp) public {
        // goal is to test change uint104 -> uint256 and have fized big value to test
        _defaulting_ImmediateDistributionOverflows(2 ** 128, _warp);
    }

    function _defaulting_ImmediateDistributionOverflows(uint256 _collateral, uint32 _warp) internal {
        vm.assume(_collateral <= type(uint256).max / SiloMathLib._DECIMALS_OFFSET_POW);

        _addLiquidity(_collateral);

        bool success = _createPosition({_borrower: borrower, _collateral: _collateral, _protected: 0, _maxOut: true});

        vm.assume(success);

        // this will help with high interest
        _removeLiquidity();

        _moveUntillDefaultingPossible(borrower, 0.01e18, 1 days);

        vm.warp(block.timestamp + _warp);

        _createIncentiveController();

        token0.setOnDemand(false);
        token1.setOnDemand(false);

        (uint256 collateralToLiquidate,,) = IPartialLiquidation(address(defaulting)).maxLiquidation(borrower);

        try defaulting.getKeeperAndLenderSharesSplit(collateralToLiquidate, ISilo.CollateralType.Collateral) {
            // ok
        } catch {
            // exclude case when we overflow on split match
            vm.assume(false);
        }

        try defaulting.liquidationCallByDefaulting(borrower) {
            // ok
        } catch (bytes memory e) {
            if (_isControllerOverflowing(e)) {
                console2.log("immediate distribution overflow, accepted, but exlude this case");
                vm.assume(false);
            } else {
                RevertLib.revertBytes(e, "executeDefaulting failed");
            }
        }
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_neverReverts_badDebt_withOtherBorrowers_fuzz -vv --fuzz-runs 3333
    locally: 6s
    */
    function test_defaulting_neverReverts_badDebt_withOtherBorrowers_fuzz(
        uint32 _collateral,
        uint32 _protected,
        uint32 _warp
    ) public {
        _addLiquidity(Math.max(_collateral, _protected));

        address otherBorrower = makeAddr("otherBorrower");

        bool success = _createPosition({
            _borrower: otherBorrower,
            _collateral: _collateral,
            _protected: _protected,
            _maxOut: false
        });

        vm.assume(success);

        (,, IShareToken debtShareToken) = _getBorrowerShareTokens(otherBorrower);
        (, ISilo debtSilo) = _getSilos();

        uint256 debtBalanceBefore = debtShareToken.balanceOf(otherBorrower);

        _defaulting_neverReverts_badDebt({
            _borrower: borrower,
            _collateral: _collateral,
            _protected: _protected,
            _warp: _warp
        });

        assertEq(
            debtBalanceBefore,
            debtShareToken.balanceOf(otherBorrower),
            "other borrower debt should be the same before and after defaulting"
        );

        MintableToken(debtSilo.asset()).setOnDemand(true);

        debtSilo.repayShares(debtBalanceBefore, otherBorrower);
        assertEq(debtShareToken.balanceOf(otherBorrower), 0, "other borrower should be able fully repay");

        _assertEveryoneCanExitFromSilo(silo0, true);
        _assertEveryoneCanExitFromSilo(silo1, true);
    }

    function _defaulting_neverReverts_badDebt(
        address _borrower,
        uint256 _collateral,
        uint256 _protected,
        uint32 _warp
    ) internal {
        _addLiquidity(Math.max(_collateral, _protected));

        bool success =
            _createPosition({_borrower: _borrower, _collateral: _collateral, _protected: _protected, _maxOut: true});

        vm.assume(success);

        // this will help with high interest
        _removeLiquidity();

        uint256 price = 1e18;

        do {
            price -= 0.01e18; // drop price by 1%
            _setCollateralPrice(price);
            vm.warp(block.timestamp + 1 days);
        } while (silo0.getLtv(_borrower) < 1e18);

        vm.warp(block.timestamp + _warp);

        _printLtv(_borrower);
        assertTrue(_defaultingPossible(_borrower), "it should be possible always when bad debt");

        _createIncentiveController();

        _printBalances(silo0, _borrower);
        _printBalances(silo1, _borrower);

        console2.log("\tdefaulting.liquidationCallByDefaulting(_borrower)");

        _printMaxLiquidation(_borrower);

        vm.assume(silo0.getLtv(_borrower) >= 1e18); // position should be in bad debt state

        token0.setOnDemand(false);
        token1.setOnDemand(false);

        defaulting.liquidationCallByDefaulting(_borrower);

        _assertProtectedRatioDidNotchanged();

        _printBalances(silo0, _borrower);
        _printBalances(silo1, _borrower);

        _printLtv(_borrower);

        assertEq(silo0.getLtv(_borrower), 0, "position should be removed");

        _assertNoShareTokens({
            _silo: silo0,
            _user: _borrower,
            _allowForDust: true,
            _msg: "position should be removed on silo0"
        });

        _assertNoShareTokens({
            _silo: silo1,
            _user: _borrower,
            _allowForDust: true,
            _msg: "position should be removed on silo1"
        });

        // we can not assert for silo exit, because defaulting will make share value lower,
        // so there might be users who can not withdraw because convertion to assets will give 0
        // _exitSilo();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_neverReverts_insolvency_fuzz -vv
    locally: 57s on silo0
    */
    function test_defaulting_neverReverts_insolvency_long_fuzz(uint32 _collateral, uint32 _protected) public {
        _defaulting_neverReverts_insolvency({_borrower: borrower, _collateral: _collateral, _protected: _protected});
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_neverReverts_insolvency_withOtherBorrowers_fuzz -vv
    locally: 63s
    */
    function test_defaulting_neverReverts_insolvency_withOtherBorrowers_long_fuzz(uint32 _collateral, uint32 _protected)
        public
    {
        _addLiquidity(Math.max(_collateral, _protected));
        address otherBorrower = makeAddr("otherBorrower");

        bool success = _createPosition({
            _borrower: otherBorrower,
            _collateral: _collateral,
            _protected: _protected,
            _maxOut: false
        });

        vm.assume(success);

        (,, IShareToken debtShareToken) = _getBorrowerShareTokens(otherBorrower);
        (, ISilo debtSilo) = _getSilos();

        uint256 debtBalanceBefore = debtShareToken.balanceOf(otherBorrower);

        _defaulting_neverReverts_insolvency({_borrower: borrower, _collateral: _collateral, _protected: _protected});

        assertEq(
            debtBalanceBefore,
            debtShareToken.balanceOf(otherBorrower),
            "other borrower debt shares should be the same before and after defaulting"
        );

        MintableToken(debtSilo.asset()).setOnDemand(true);

        debtSilo.repayShares(debtBalanceBefore, otherBorrower);
        assertEq(debtShareToken.balanceOf(otherBorrower), 0, "other borrower should be able fully repay");

        uint256 debtBalance = debtShareToken.balanceOf(borrower);

        if (debtBalance != 0) {
            debtSilo.repayShares(debtShareToken.balanceOf(borrower), borrower);
        }

        _assertEveryoneCanExitFromSilo(silo0, true);
        _assertEveryoneCanExitFromSilo(silo1, true);
    }

    function _defaulting_neverReverts_insolvency(address _borrower, uint256 _collateral, uint256 _protected)
        internal
    {
        _addLiquidity(Math.max(_collateral, _protected));

        bool success =
            _createPosition({_borrower: _borrower, _collateral: _collateral, _protected: _protected, _maxOut: true});

        vm.assume(success);

        // this will help with high interest
        _removeLiquidity();

        _printLtv(_borrower);

        uint256 price = 1e18;

        do {
            price -= 0.001e18; // drop price litle by little, to not create bad debt instantly
            _setCollateralPrice(price);
            vm.warp(block.timestamp + 12 hours);
        } while (!_defaultingPossible(_borrower));

        _createIncentiveController();

        _printBalances(silo0, _borrower);
        _printBalances(silo1, _borrower);

        console2.log("\tdefaulting.liquidationCallByDefaulting(_borrower)");

        _printMaxLiquidation(_borrower);

        vm.assume(!silo0.isSolvent(_borrower)); // position should be insolvent
        vm.assume(silo0.getLtv(_borrower) < 1e18); // position should not be in bad debt state

        token0.setOnDemand(false);
        token1.setOnDemand(false);

        defaulting.liquidationCallByDefaulting(_borrower);

        _printBalances(silo0, _borrower);
        _printBalances(silo1, _borrower);

        _printLtv(_borrower);

        _assertProtectedRatioDidNotchanged();

        // we can not assert for silo exit, because defaulting will make share value lower,
        // so there might be users who can not withdraw because convertion to assets will give 0
        //_exitSilo();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_when_0collateral_oneBorrower_fuzz -vv
    locally: 4s
    */
    function test_defaulting_when_0collateral_oneBorrower_fuzz(uint96 _collateral, uint96 _protected) public {
        _setCollateralPrice(1.3e18); // we need high price at begin for this test, because we need to end up wit 1:1
        _addLiquidity(uint256(_collateral) + _protected);

        (ISilo collateralSilo, ISilo debtSilo) = _getSilos();

        bool success =
            _createPosition({_borrower: borrower, _collateral: _collateral, _protected: _protected, _maxOut: true});
        vm.assume(success);

        // this will help with interest
        _removeLiquidity();
        assertLe(debtSilo.getLiquidity(), 1, "liquidity should be ~0");

        console2.log("AFTER REMOVE LIQUIDITY");

        _setCollateralPrice(1e18);

        do {
            vm.warp(block.timestamp + 10 days);
            // 1.01 because when we do normal liquidation it can be no debt after that
        } while (silo0.getLtv(borrower) < 1.01e18);

        // we need case, where we do not oveflow on interest, so we can apply interest
        // vm.assume(debtSilo.maxRepay(borrower) > repayBefore);
        debtSilo.accrueInterest();
        (uint256 revenue, uint256 revenueFractions) = _printRevenue(debtSilo);
        assertTrue(revenue > 0 || revenueFractions > 0, "we need case with fees");

        // first do normal liquidation with sTokens, to remove whole collateral,
        // price is set 1:1 so we can use collateral as max debt
        (IShareToken collateralShareToken, IShareToken protectedShareToken, IShareToken debtShareToken) =
            _getBorrowerShareTokens(borrower);
        uint256 collateralPreview =
            collateralSilo.previewRedeem(collateralShareToken.balanceOf(borrower), ISilo.CollateralType.Collateral);
        uint256 protectedPreview =
            collateralSilo.previewRedeem(protectedShareToken.balanceOf(borrower), ISilo.CollateralType.Protected);
        (address collateralToken, address debtToken) = _getTokens();

        // we need to create 0 collateral, +2 should cover full collateral and price is 1:1 so we can use as maxDebt
        try partialLiquidation.liquidationCall(
            collateralToken, debtToken, borrower, collateralPreview + protectedPreview + 2, true
        ) {
            // nothing to do
        } catch (bytes memory data) {
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes4 errorType = bytes4(data);
            bytes4 returnZeroShares = bytes4(keccak256(abi.encodePacked("ReturnZeroShares()")));

            // skipping case, when we can not liquidate tiny debt because of ReturnZeroShares error on repay
            if (errorType == returnZeroShares) {
                vm.assume(false);
            } else {
                RevertLib.revertBytes(data, "liquidationCall failed");
            }
        }

        _wipeOutCollateralShares(collateralShareToken, borrower);

        depositors.push(address(this)); // liquidator got shares
        console2.log("AFTER NORMAL LIQUIDATION");

        assertEq(collateralShareToken.balanceOf(borrower), 0, "collateral shares must be 0");
        assertEq(protectedShareToken.balanceOf(borrower), 0, "protected shares must be 0");
        vm.assume(debtShareToken.balanceOf(borrower) != 0); //  we need bad debt

        assertTrue(_defaultingPossible(borrower), "defaulting should be possible even without collateral");

        _createIncentiveController();

        token0.setOnDemand(false);
        token1.setOnDemand(false);

        defaulting.liquidationCallByDefaulting(borrower);
        console2.log("AFTER DEFAULTING");

        _assertProtectedRatioDidNotchanged();

        // NOTE: turns out, even with bad debt collateral not neccessarly is reset

        _printLtv(borrower);

        assertEq(silo0.getLtv(borrower), 0, "position should be removed");

        _assertNoWithdrawableFees(collateralSilo);
        _assertWithdrawableFees(debtSilo);

        // borrower is fully liquidated, so we can exit from both silos
        _assertEveryoneCanExitFromSilo(debtSilo, true);
        // we need to allow for dust, because liquidaor got dust after defaulting
        _assertEveryoneCanExitFromSilo(collateralSilo, true);

        _assertTotalSharesZeroOnlyGauge(collateralSilo);
        _assertTotalSharesZeroOnlyGauge(debtSilo);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_when_0collateral_otherBorrower_wipeOutShares_fuzz -vv
    locally: 5s
    */
    function test_defaulting_when_0collateral_otherBorrower_wipeOutShares_fuzz(uint96 _collateral, uint96 _protected)
        public
    {
        _defaulting_when_0collateral_otherBorrower({
            _collateral: _collateral,
            _protected: _protected,
            _wipeOutShares: true
        });
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_when_0collateral_otherBorrower_withDustShares_fuzz -vv
    locally: 5s
    */
    function test_defaulting_when_0collateral_otherBorrower_withDustShares_fuzz(uint96 _collateral, uint96 _protected)
        public
    {
        _defaulting_when_0collateral_otherBorrower({
            _collateral: _collateral,
            _protected: _protected,
            _wipeOutShares: false
        });
    }

    function _defaulting_when_0collateral_otherBorrower(uint96 _collateral, uint96 _protected, bool _wipeOutShares)
        internal
    {
        _addLiquidity(uint256(_collateral) + _protected);

        _setCollateralPrice(1.3e18); // we need high price at begin for this test, because we need to end up wit 1:1

        bool success = _createPosition({
            _borrower: makeAddr("otherBorrower"),
            _collateral: _collateral / 3,
            _protected: uint96(uint256(_protected) * 2 / 3),
            _maxOut: false
        });
        vm.assume(success);

        (ISilo collateralSilo, ISilo debtSilo) = _getSilos();

        success = _createPosition({
            _borrower: borrower,
            _collateral: uint96(uint256(_collateral) * 2 / 3),
            _protected: _protected / 3,
            _maxOut: true
        });
        vm.assume(success);

        (IShareToken collateralShareToken, IShareToken protectedShareToken, IShareToken debtShareToken) =
            _getBorrowerShareTokens(borrower);

        // this will help with interest
        _removeLiquidity();

        console2.log("AFTER REMOVE LIQUIDITY");

        _setCollateralPrice(1e18);

        do {
            vm.warp(block.timestamp + 10 days);
            // 1.01 because when we do normal liquidation it can be no debt after that
        } while (silo0.getLtv(borrower) < 1.01e18);

        // we need case, where we do not oveflow on interest, so we can apply interest
        // vm.assume(debtSilo.maxRepay(borrower) > repayBefore);
        debtSilo.accrueInterest();
        (uint256 revenue, uint256 revenueFractions) = _printRevenue(debtSilo);
        assertTrue(revenue > 0 || revenueFractions > 0, "we need case with fees");

        // this repay should make other liquidation not reset total assets, so everyone can exit
        debtSilo.repayShares(debtShareToken.balanceOf(makeAddr("otherBorrower")), makeAddr("otherBorrower"));
        console2.log("AFTER otherBorrower REPAY");

        // first do normal liquidation with sTokens, to remove whole collateral,
        // price is set 1:1 so we can use collateral as max debt
        uint256 collateralPreview =
            collateralSilo.previewRedeem(collateralShareToken.balanceOf(borrower), ISilo.CollateralType.Collateral);
        uint256 protectedPreview =
            collateralSilo.previewRedeem(protectedShareToken.balanceOf(borrower), ISilo.CollateralType.Protected);
        (address collateralToken, address debtToken) = _getTokens();

        // we need to create 0 collateral, price is 1:1 so we can use collateral as maxDebt,
        // it might be not possible to liquidate tiny debt because of ReturnZeroShares error on repay
        try partialLiquidation.liquidationCall(
            collateralToken, debtToken, borrower, collateralPreview + protectedPreview, true
        ) {
            // nothing to do
        } catch (bytes memory data) {
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes4 errorType = bytes4(data);
            bytes4 returnZeroShares = bytes4(keccak256(abi.encodePacked("ReturnZeroShares()")));
            if (errorType == returnZeroShares) {
                vm.assume(false);
            } else {
                RevertLib.revertBytes(data, "liquidationCall failed");
            }

            // skipping case, when we can not liquidate tiny debt because of ReturnZeroShares error on repay
            vm.assume(false);
        }

        depositors.push(address(this)); // liquidator got shares

        console2.log("ratio", collateralSilo.convertToShares(1));

        if (_wipeOutShares) {
            _wipeOutCollateralShares(collateralShareToken, borrower);
        }

        assertEq(
            collateralSilo.previewRedeem(collateralShareToken.balanceOf(borrower)), 0, "collateral assets must be 0"
        );

        assertEq(protectedShareToken.balanceOf(borrower), 0, "protected shares must be 0");
        vm.assume(debtShareToken.balanceOf(borrower) != 0); // we need bad debt

        console2.log("-------------------------------- AFTER NORMAL LIQUIDATION --------------------------------");

        assertTrue(_defaultingPossible(borrower), "defaulting should be possible even without collateral");

        _createIncentiveController();

        token0.setOnDemand(false);
        token1.setOnDemand(false);

        defaulting.liquidationCallByDefaulting(borrower);
        console2.log("-------------------------------- AFTER DEFAULTING --------------------------------");

        _assertProtectedRatioDidNotchanged();

        _assertNoWithdrawableFees(collateralSilo);
        _assertWithdrawableFees(debtSilo);

        // borrower is fully liquidated
        _assertEveryoneCanExitFromSilo(debtSilo, true);
        _assertEveryoneCanExitFromSilo(collateralSilo, true);

        // we can not asseth total collateral shares to be 0,
        // because after defaulting, we can create dust shares for depositors
        uint256 gaugeProtected = protectedShareToken.balanceOf(address(gauge));
        console2.log("gaugeProtected", gaugeProtected);

        assertEq(
            protectedShareToken.totalSupply(),
            gaugeProtected,
            "protected share token should have only gauge protected"
        );

        _assertTotalSharesZero(debtSilo);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_twice_0collateral -vv
    */
    function test_defaulting_twice_0collateral_fuzz(uint48 _collateral, uint48 _protected) public {
        _createIncentiveController();

        _addLiquidity(uint256(_collateral) + _protected);

        (ISilo collateralSilo, ISilo debtSilo) = _getSilos();

        bool success =
            _createPosition({_borrower: borrower, _collateral: _collateral, _protected: _protected, _maxOut: true});
        vm.assume(success);

        (, IShareToken protectedShareToken, IShareToken debtShareToken) = _getBorrowerShareTokens(borrower);

        uint256 balance = collateralSilo.balanceOf(borrower);

        // remove collateral
        
        if (balance != 0) {
            vm.prank(address(partialLiquidation));
            IShareToken(address(collateralSilo)).forwardTransferFromNoChecks(borrower, address(this), balance);
        }

        balance = protectedShareToken.balanceOf(borrower);
        if (balance != 0) {
            vm.prank(address(partialLiquidation));
            protectedShareToken.forwardTransferFromNoChecks(borrower, address(this), balance);
        }

        depositors.push(address(this)); // we got shares

        _assertNoRedeemable(
            collateralSilo, borrower, ISilo.CollateralType.Collateral, false, "collateral assets must be 0"
        );
        assertEq(protectedShareToken.balanceOf(borrower), 0, "protected shares must be 0");
        vm.assume(debtShareToken.balanceOf(borrower) != 0); // we need bad debt

        console2.log("AFTER DEFAULTING #1");
        _assertProtectedRatioDidNotchanged();

        assertTrue(_defaultingPossible(borrower), "defaulting should be possible even without collateral");

        defaulting.liquidationCallByDefaulting(borrower);
        console2.log("AFTER DEFAULTING #2");
        _assertProtectedRatioDidNotchanged();

        _assertNoWithdrawableFees(collateralSilo);
        // fees can be zero out after defaulting, so we can not assert that
        // _assertWithdrawableFees(debtSilo);

        _printLtv(borrower);

        _printBalances(silo0, borrower);
        _printBalances(silo1, makeAddr("lpProvider"));

        assertEq(silo0.getLtv(borrower), 0, "position should be removed");

        _assertNoShareTokens(
            collateralSilo, borrower, true, "position should be removed on collateralSilo (dust allowed)"
        );
        _assertNoShareTokens(debtSilo, borrower, false, "position should be removed on debtSilo");

        token0.setOnDemand(true);
        token1.setOnDemand(true);

        collateralSilo.deposit(1e18, makeAddr("anyUser"));
        debtSilo.deposit(2, makeAddr("anyUser2"));
        depositors.push(makeAddr("anyUser"));
        depositors.push(makeAddr("anyUser2"));
        depositors.push(address(this));

        // borrower is fully liquidated
        _assertEveryoneCanExitFromSilo(debtSilo, true);
        _assertEveryoneCanExitFromSilo(collateralSilo, true);

        // we can not assert zero shares ath the end, because
        // few defaulting can cause non-withdawable share dust
        // _assertTotalSharesZeroOnlyGauge(collateralSilo);
        // _assertTotalSharesZeroOnlyGauge(debtSilo);
    }

    /*
    everyone should be able to withdraw protected after defaulting liquidation
    echidna candidate

    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_protectedCanBeFullyWithdrawn_ -vv --fuzz-runs 8888
    locally: 22s
    */
    function test_defaulting_protectedCanBeFullyWithdrawn_long_fuzz(
        uint24[] memory _protectedDeposits,
        uint64 _initialPrice,
        uint64 _changePrice,
        uint32 _warp,
        uint96 _collateral,
        uint96 _protected
    ) public {
        (, ISilo debtSilo) = _getSilos();

        for (uint256 i; i < _protectedDeposits.length; i++) {
            address user = makeAddr(string.concat("user", vm.toString(i + 1)));
            vm.prank(user);
            debtSilo.deposit(Math.max(_protectedDeposits[i], 1), user, ISilo.CollateralType.Protected);
        }

        _setCollateralPrice(_initialPrice);
        _addLiquidity(Math.max(_collateral, _protected));

        bool success =
            _createPosition({_borrower: borrower, _collateral: _collateral, _protected: _protected, _maxOut: true});
        vm.assume(success);

        assertGt(silo0.getLtv(borrower), 0, "double check that user does have position");

        _removeLiquidity();

        _setCollateralPrice(_changePrice);

        vm.warp(block.timestamp + _warp);

        _createIncentiveController();

        token0.setOnDemand(false);
        token1.setOnDemand(false);

        try defaulting.liquidationCallByDefaulting(borrower) {
            // nothing to do
        } catch {
            // does not matter what happened, user should be able to withdraw protected
        }

        for (uint256 i; i < _protectedDeposits.length; i++) {
            address user = makeAddr(string.concat("user", vm.toString(i + 1)));
            vm.prank(user);
            debtSilo.withdraw(Math.max(_protectedDeposits[i], 1), user, user, ISilo.CollateralType.Protected);
        }
    }

    /*
    if _defaultingPossible() we never revert otherwise we do revert

    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_whenDefaultingPossibleTxDoesNotRevert_badDebt_fuzz -vv --fuzz-runs 2222
    locally: 2s
    */
    function test_whenDefaultingPossibleTxDoesNotRevert_badDebt_fuzz(
        uint64 _dropPricePercentage,
        uint32 _warp,
        uint48 _collateral,
        uint48 _protected
    ) public {
        _whenDefaultingPossibleTxDoesNotRevert({
            _dropPricePercentage: _dropPricePercentage,
            _warp: _warp,
            _collateral: _collateral,
            _protected: _protected,
            _badDebtCasesOnly: true
        });
    }

    /*
    if _defaultingPossible() we never revert otherwise we do revert

    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_whenDefaultingPossibleTxDoesNotRevert_notBadDebt_fuzz -vv --fuzz-runs 8888
    locally: 12s
    */
    function test_whenDefaultingPossibleTxDoesNotRevert_notBadDebt_fuzz(
        uint64 _dropPricePercentage,
        uint32 _warp,
        uint48 _collateral,
        uint48 _protected
    ) public {
        _addLiquidity(Math.max(_collateral, _protected));

        bool success = _createPosition({
            _borrower: makeAddr("borrower2"),
            _collateral: uint256(_collateral) * 10,
            _protected: uint256(_protected) * 10,
            _maxOut: false
        });

        vm.assume(success);

        _whenDefaultingPossibleTxDoesNotRevert({
            _dropPricePercentage: _dropPricePercentage,
            _warp: _warp,
            _collateral: _collateral,
            _protected: _protected,
            _badDebtCasesOnly: false
        });
    }

    function _whenDefaultingPossibleTxDoesNotRevert(
        uint64 _dropPricePercentage,
        uint32 _warp,
        uint48 _collateral,
        uint48 _protected,
        bool _badDebtCasesOnly
    ) internal {
        uint64 initialPrice = 1e18;
        uint256 changePrice = _calculateNewPrice(initialPrice, -int64(0.001e18 + (_dropPricePercentage % 0.1e18)));

        changePrice = 0.2e18;

        _addLiquidity(Math.max(_collateral, _protected));

        bool success = _createPosition({
            _borrower: borrower,
            _collateral: _collateral,
            _protected: _protected,
            _maxOut: _badDebtCasesOnly
        });

        vm.assume(success);
        bool throwing;

        if (_badDebtCasesOnly) {
            _removeLiquidity();
            _setCollateralPrice(changePrice);
            (throwing,) = _isOracleThrowing(borrower);
            vm.assume(!throwing);
            vm.warp(block.timestamp + _warp);
        } else {
            vm.assume(_printLtv(borrower) < 1e18);
        }

        console2.log("AFTER WARP AND PRICE CHANGE");

        _moveUntillDefaultingPossible(borrower, 0.001e18, 1 hours);

        // if oracle is throwing, we can not test anything
        (throwing,) = _isOracleThrowing(borrower);
        vm.assume(!throwing);

        _createIncentiveController();

        if (_badDebtCasesOnly) {
            vm.assume(_printLtv(borrower) >= 1e18);
        } else {
            vm.assume(_printLtv(borrower) < 1e18);
        }

        token0.setOnDemand(false);
        token1.setOnDemand(false);

        defaulting.liquidationCallByDefaulting(borrower);
        _assertProtectedRatioDidNotchanged();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_bothLiquidationsResultsMatch_insolvent_fuzz -vv --fuzz-runs 500

    use uint64 for collateral and protected because fuzzing was trouble to find cases, 
    reason is incentive uint104 cap

    use only 100 runs because fuzzing for this one is demanding
    */
    /// forge-config: core_test.fuzz.runs = 10
    function test_bothLiquidationsResultsMatch_insolvent_fuzz_limit(
        uint64 _priceDropPercentage,
        uint32 _warp,
        uint48 _collateral,
        uint48 _protected
    ) public virtual {
        vm.assume(_priceDropPercentage > 0.0005e18);

        // 0.5% to 20% price drop cap
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 dropPercentage = int256(uint256(_priceDropPercentage) % 0.2e18);

        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 targetPrice = _calculateNewPrice(uint64(oracle0.price()), -int64(dropPercentage));

        _addLiquidity(Math.max(_collateral, _protected));
        bool success =
            _createPosition({_borrower: borrower, _collateral: _collateral, _protected: _protected, _maxOut: false});

        vm.assume(success);

        // this will help with interest
        _removeLiquidity();
        _setCollateralPrice(targetPrice);
        vm.warp(block.timestamp + _warp);

        // if oracle is throwing, we can not test anything
        (bool throwing,) = _isOracleThrowing(borrower);
        vm.assume(!throwing);

        console2.log("AFTER WARP AND PRICE CHANGE");
        _printLtv(borrower);

        _createIncentiveController();

        _moveUntillDefaultingPossible(borrower, 0.0001e18, 1 hours);

        uint256 ltv = _printLtv(borrower);
        vm.assume(ltv < 1e18); // we dont want bad debt, in bad debt we reset position

        uint256 snapshot = vm.snapshotState();
        console2.log("snapshot taken", snapshot);

        _executeMaxLiquidation(borrower);
        console2.log("regular liquidation done");
        UserState memory userState0 = _getUserState(silo0, borrower);
        UserState memory userState1 = _getUserState(silo1, borrower);

        vm.revertToState(snapshot);
        console2.log("snapshot reverted");

        _executeDefaulting(borrower);
        console2.log("defaulting liquidation done");
        UserState memory userStateAfter0 = _getUserState(silo0, borrower);
        UserState memory userStateAfter1 = _getUserState(silo1, borrower);

        assertEq(userState0.debtShares, userStateAfter0.debtShares, "debt0 shares should be the same");
        assertEq(userState0.protectedShares, userStateAfter0.protectedShares, "protected0 shares should be the same");
        assertEq(
            userState0.colalteralShares, userStateAfter0.colalteralShares, "collateral0 shares should be the same"
        );

        assertEq(userState1.debtShares, userStateAfter1.debtShares, "debt1 shares should be the same");
        assertEq(userState1.protectedShares, userStateAfter1.protectedShares, "protected1 shares should be the same");
        assertEq(
            userState1.colalteralShares, userStateAfter1.colalteralShares, "collateral1 shares should be the same"
        );

        _printLtv(borrower);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_delegatecall_whenRepayReverts -vv
    */
    function test_defaulting_delegatecall_whenRepayReverts() public {
        _addLiquidity(1e18);
        bool success = _createPosition({_borrower: borrower, _collateral: 1e18, _protected: 10, _maxOut: true});
        vm.assume(success);

        _moveUntillDefaultingPossible(borrower, 0.001e18, 1 days);

        uint256 ltv = _printLtv(borrower);

        assertTrue(_defaultingPossible(borrower), "explect not solvent ready for defaulting");

        _createIncentiveController();

        (, ISilo debtSilo) = _getSilos();
        (,, IShareToken debtShareToken) = _getBorrowerShareTokens(borrower);
        uint256 debtBalanceBefore = debtShareToken.balanceOf(borrower);

        // mock revert inside repay process to test if whole tx reverts
        vm.mockCallRevert(
            address(siloConfig),
            abi.encodeWithSelector(ISiloConfig.getDebtShareTokenAndAsset.selector, address(debtSilo)),
            abi.encode("repayDidNotWork")
        );

        vm.expectRevert("repayDidNotWork");
        defaulting.liquidationCallByDefaulting(borrower);

        assertEq(ltv, silo0.getLtv(borrower), "ltv should be unchanged because no liquidation happened");
        assertEq(debtBalanceBefore, debtShareToken.balanceOf(borrower), "debt balance should be the same");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_delegatecall_whenDecuctReverts -vv
    */
    function test_defaulting_delegatecall_whenDecuctReverts() public {
        _addLiquidity(1e18);
        bool success = _createPosition({_borrower: borrower, _collateral: 1e18, _protected: 1e18, _maxOut: true});
        vm.assume(success);

        _setCollateralPrice(0.01e18);

        uint256 ltv = _printLtv(borrower);

        assertTrue(ltv > 1e18, "we need bad debt so we can use max repay for mocking call");

        _createIncentiveController();

        (, ISilo debtSilo) = _getSilos();
        (,, IShareToken debtShareToken) = _getBorrowerShareTokens(borrower);
        uint256 debtBalanceBefore = debtShareToken.balanceOf(borrower);

        uint256 maxRepay = debtSilo.maxRepay(borrower);
        console2.log("debtSilo.maxRepay(borrower)", maxRepay);

        // mock revert inside collateral reduction process to test if whole tx reverts
        bytes memory deductDefaultedDebtFromCollateralCalldata =
            abi.encodeWithSelector(DefaultingSiloLogic.deductDefaultedDebtFromCollateral.selector, maxRepay);

        bytes memory callOnBehalfOfSiloCalldata = abi.encodeWithSelector(
            ISilo.callOnBehalfOfSilo.selector,
            address(defaulting.LIQUIDATION_LOGIC()),
            0,
            ISilo.CallType.Delegatecall,
            deductDefaultedDebtFromCollateralCalldata
        );

        vm.mockCallRevert(address(debtSilo), callOnBehalfOfSiloCalldata, abi.encode("deductDidNotWork"));

        vm.expectRevert("deductDidNotWork");
        defaulting.liquidationCallByDefaulting(borrower);

        assertEq(ltv, silo0.getLtv(borrower), "ltv should be unchanged because no liquidation happened");
        assertEq(debtBalanceBefore, debtShareToken.balanceOf(borrower), "debt balance should be the same");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_getKeeperAndLenderSharesSplit_fuzz -vv --fuzz-runs 2345

    we should never generate more shares than borrower has, rounding check
    */
    function test_defaulting_getKeeperAndLenderSharesSplit_fuzz(uint32 _collateral, uint32 _protected, uint32 _warp)
        public
    {
        _setCollateralPrice(1.05e18);

        _addLiquidity(Math.max(_collateral, _protected));

        bool success =
            _createPosition({_borrower: borrower, _collateral: _collateral, _protected: _protected, _maxOut: false});

        vm.assume(success);

        _removeLiquidity();

        vm.warp(block.timestamp + _warp);

        uint256 price = 1e18;
        _setCollateralPrice(price);

        _moveUntillDefaultingPossible(borrower, 0.001e18, 1 hours);

        (IShareToken collateralShareToken, IShareToken protectedShareToken,) = _getBorrowerShareTokens(borrower);

        uint256 collateralSharesBefore = collateralShareToken.balanceOf(borrower);
        uint256 protectedSharesBefore = protectedShareToken.balanceOf(borrower);

        address lpProvider = makeAddr("lpProvider");

        assertEq(
            collateralShareToken.balanceOf(lpProvider),
            0,
            "lpProvider should have 0 collateral shares before liquidation"
        );
        assertEq(
            protectedShareToken.balanceOf(lpProvider),
            0,
            "lpProvider should have 0 protected shares before liquidation"
        );

        _printBalances(silo0, borrower);
        _printBalances(silo1, borrower);

        _printBalances(silo0, lpProvider);
        _printBalances(silo1, lpProvider);

        _createIncentiveController();

        token0.setOnDemand(false);
        token1.setOnDemand(false);

        defaulting.liquidationCallByDefaulting(borrower);

        console2.log("AFTER LIQUIDATION");

        vm.prank(lpProvider);
        gauge.claimRewards(lpProvider);

        uint256 collateralRewards = collateralShareToken.balanceOf(lpProvider);
        uint256 protectedRewards = protectedShareToken.balanceOf(lpProvider);

        assertLe(collateralShareToken.balanceOf(address(gauge)), 1, "gauge should have ~0 collateral shares");
        assertLe(protectedShareToken.balanceOf(address(gauge)), 1, "gauge should have ~0 protected shares");

        uint256 keeperCollateralShares = collateralShareToken.balanceOf(address(this));
        uint256 keeperProtectedShares = protectedShareToken.balanceOf(address(this));

        if (_protected == 0) {
            assertEq(protectedRewards, 0, "no protected rewards if no protected deposit");
            assertEq(keeperProtectedShares, 0, "keeper should have 0 protected shares");
        } else {
            assertGt(protectedRewards, 0, "protected rewards are always somethig after liquidation");

            if (keeperProtectedShares == 0) {
                assertLe(protectedRewards, protectedSharesBefore, "rewards are always le, because of NO fee");
            } else {
                assertLt(protectedRewards, protectedSharesBefore, "protected rewards are always less, because of fee");
            }
        }

        if (_collateral == 0) {
            assertEq(collateralRewards, 0, "no collateral rewards if no collateral deposit");
            assertEq(keeperCollateralShares, 0, "keeper should have 0 collateral shares");
        } else {
            if (_protected == 0) {
                assertGt(collateralRewards, 0, "collateral rewards are always somethig");
            } else {
                // collaterar rewards depends if protected were enough or not
            }

            if (keeperCollateralShares == 0) {
                assertLe(collateralRewards, collateralSharesBefore, "rewards are always le, because of NO fee");
            } else {
                assertLt(collateralRewards, collateralSharesBefore, "rewards are always less, because of fee");
            }
        }
    }

    /*
    incentive distribution: 
    - does everyone can claim? its shares so even 1 wei should be claimable

    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_incentiveDistribution_everyoneCanClaim_badDebt -vv
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_incentiveDistribution_everyoneCanClaim_badDebt -vv --mc DefaultingLiquidationBorrowable1Test
    locally: 10s
    */
    function test_incentiveDistribution_everyoneCanClaim_badDebt_fuzz(uint48 _collateral, uint48 _protected) public {
        // (uint48 _collateral, uint48 _protected) = (17829408, 331553767526);
        _incentiveDistribution_everyoneCanClaim(_collateral, _protected, true);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_incentiveDistribution_everyoneCanClaim_insolvent -vv
    locally: 55s
    */
    function test_incentiveDistribution_everyoneCanClaim_insolvent_long_fuzz(uint64 _collateral, uint64 _protected) public {
        _incentiveDistribution_everyoneCanClaim(_collateral, _protected, false);
    }

    function _incentiveDistribution_everyoneCanClaim(uint256 _collateral, uint256 _protected, bool _badDebt) public {
        (ISilo collateralSilo, ISilo debtSilo) = _getSilos();

        uint256 shares1 = debtSilo.deposit(1, makeAddr("lpProvider1"));
        debtSilo.deposit(1, makeAddr("lpProvider3"), ISilo.CollateralType.Protected);

        _createIncentiveController();

        uint256 shares2 = debtSilo.deposit(Math.max(_collateral, 1), makeAddr("lpProvider2"));
        debtSilo.deposit(Math.max(_protected, 1), makeAddr("lpProvider4"), ISilo.CollateralType.Protected);

        depositors.push(makeAddr("lpProvider1"));
        depositors.push(makeAddr("lpProvider2"));
        depositors.push(makeAddr("lpProvider3"));
        depositors.push(makeAddr("lpProvider4"));

        console2.log("ratio", collateralSilo.convertToShares(1));

        bool success =
            _createPosition({_borrower: borrower, _collateral: _collateral, _protected: _protected, _maxOut: true});
        vm.assume(success);

        console2.log("borrower colateral share balance just after creation", collateralSilo.balanceOf(borrower));
        console2.log("ratio", collateralSilo.convertToShares(1));

        token0.setOnDemand(false);
        token1.setOnDemand(false);

        if (_badDebt) {
            _moveUntillBadDebt(borrower, 0.005e18, 24 hours);
        } else {
            _moveUntillDefaultingPossible(borrower, 0.001e18, 1 hours);
        }

        (IShareToken collateralShareToken, IShareToken protectedShareToken,) = _getBorrowerShareTokens(borrower);

        console2.log("borrower colateral share balance", collateralSilo.balanceOf(borrower));

        defaulting.liquidationCallByDefaulting(borrower);

        uint256 collateralRewards = collateralShareToken.balanceOf(address(gauge));
        uint256 protectedRewards = protectedShareToken.balanceOf(address(gauge));

        console2.log("gauge2 collateralbalance", collateralRewards);
        console2.log("gauge2 protected balance", protectedRewards);

        vm.prank(makeAddr("lpProvider1"));
        gauge.claimRewards(makeAddr("lpProvider1"));
        vm.prank(makeAddr("lpProvider2"));
        gauge.claimRewards(makeAddr("lpProvider2"));
        vm.prank(makeAddr("lpProvider3"));
        gauge.claimRewards(makeAddr("lpProvider3"));
        vm.prank(makeAddr("lpProvider4"));
        gauge.claimRewards(makeAddr("lpProvider4"));

        uint256 oneWeiRewardsCollateral = shares1 * collateralRewards / debtSilo.totalSupply();
        uint256 oneWeiRewardsProtected = shares1 * protectedRewards / debtSilo.totalSupply();

        console2.log("1 wei shares", collateralShareToken.balanceOf(makeAddr("lpProvider1")));
        console2.log("lpProvider2 shares", collateralShareToken.balanceOf(makeAddr("lpProvider2")));

        console2.log("oneWeiRewardsCollateral", shares1 * collateralRewards / debtSilo.totalSupply());
        console2.log("oneWeiRewardsProtected", shares1 * protectedRewards / debtSilo.totalSupply());

        if (_protected != 0) {
            if (oneWeiRewardsProtected != 0) {
                assertGt(
                    protectedShareToken.balanceOf(makeAddr("lpProvider1")),
                    0,
                    "[lpProvider1] expect protected rewards"
                );
            } else {
                assertEq(
                    protectedShareToken.balanceOf(makeAddr("lpProvider1")),
                    0,
                    "[lpProvider1] 1 wei should not generate protected rewards"
                );
            }

            if (shares2 * protectedRewards / debtSilo.totalSupply() != 0) {
                assertGt(
                    protectedShareToken.balanceOf(makeAddr("lpProvider2")),
                    0,
                    "[lpProvider2] expect protected rewards based on math"
                );
            }
        }

        if (_badDebt && _collateral != 0) {
            if (oneWeiRewardsCollateral != 0) {
                assertGt(
                    collateralShareToken.balanceOf(makeAddr("lpProvider1")),
                    0,
                    "[lpProvider1] expect collateral rewards"
                );
            } else {
                assertEq(
                    collateralShareToken.balanceOf(makeAddr("lpProvider1")),
                    0,
                    "[lpProvider1] 1 wei should not generate collateral rewards"
                );
            }

            /// Defaulting liquidation can leave dust shares behind, because math uses assets,
            /// and dust shares can not be transtalet to assets, that's why we can not expect collateral rewards always
            // assertGt(
            //     collateralShareToken.balanceOf(makeAddr("lpProvider2")),
            //     0,
            //     "[lpProvider2] expect collateral rewards always"
            // );
        } else {
            // we dont know for sure if collateral rewards were distributed
        }

        assertEq(
            protectedShareToken.balanceOf(makeAddr("lpProvider3")),
            0,
            "[lpProvider3] protected deposit is not rewarded (protected)"
        );

        assertEq(
            protectedShareToken.balanceOf(makeAddr("lpProvider4")),
            0,
            "[lpProvider4] protected deposit is not rewarded (protected)"
        );

        assertEq(
            collateralShareToken.balanceOf(makeAddr("lpProvider3")),
            0,
            "[lpProvider3] protected deposit is not rewarded (collateral)"
        );

        assertEq(
            collateralShareToken.balanceOf(makeAddr("lpProvider4")),
            0,
            "[lpProvider4] protected deposit is not rewarded (collateral)"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_incentiveDistribution_defaultingIsProRata_badDebt -vv
    */
    function test_incentiveDistribution_defaultingIsProRata_badDebt_fuzz(uint64 _collateral, uint64 _protected) public {
        _incentiveDistribution_defaultingIsProRata(_collateral, _protected, true);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_incentiveDistribution_defaultingIsProRata_insolvent -vv
    locally: 10s
    */
    function test_incentiveDistribution_defaultingIsProRata_insolvent_fuzz(uint64 _collateral, uint64 _protected) public {
        _incentiveDistribution_defaultingIsProRata(_collateral, _protected, false);
    }

    /*
    bad debt scenario: everybody can exit with the same loss
    */
    function _incentiveDistribution_defaultingIsProRata(uint256 _collateral, uint256 _protected, bool _badDebt)
        internal
    {
        (, ISilo debtSilo) = _getSilos();

        uint256 shares1 = debtSilo.deposit(1e18, makeAddr("lpProvider1"));
        uint256 shares2 = debtSilo.deposit(0.5e18, makeAddr("lpProvider2"));

        uint256 totalSupplyBefore = debtSilo.totalSupply();

        _createIncentiveController();

        bool success =
            _createPosition({_borrower: borrower, _collateral: _collateral, _protected: _protected, _maxOut: true});

        vm.assume(success);

        if (_badDebt) {
            _moveUntillBadDebt(borrower, 0.005e18, 24 hours);
        } else {
            _moveUntillDefaultingPossible(borrower, 0.001e18, 1 hours);
        }

        (IShareToken collateralShareToken, IShareToken protectedShareToken,) = _getBorrowerShareTokens(borrower);

        defaulting.liquidationCallByDefaulting(borrower);

        debtSilo.deposit(10e18, makeAddr("lpProvider3"));

        uint256 collateralRewards = collateralShareToken.balanceOf(address(gauge));
        uint256 protectedRewards = protectedShareToken.balanceOf(address(gauge));

        vm.prank(makeAddr("lpProvider1"));
        gauge.claimRewards(makeAddr("lpProvider1"));
        vm.prank(makeAddr("lpProvider2"));
        gauge.claimRewards(makeAddr("lpProvider2"));
        vm.prank(makeAddr("lpProvider3"));
        gauge.claimRewards(makeAddr("lpProvider3"));

        assertEq(
            protectedShareToken.balanceOf(makeAddr("lpProvider1")),
            shares1 * protectedRewards / totalSupplyBefore,
            "[lpProvider1] protected rewards are pro rata"
        );

        assertEq(
            protectedShareToken.balanceOf(makeAddr("lpProvider2")),
            shares2 * protectedRewards / totalSupplyBefore,
            "[lpProvider2] protected rewards are pro rata"
        );

        assertEq(
            protectedShareToken.balanceOf(makeAddr("lpProvider3")),
            0,
            "[lpProvider3] no protected rewards because deposit after liquidation"
        );

        assertEq(
            collateralShareToken.balanceOf(makeAddr("lpProvider1")),
            shares1 * collateralRewards / totalSupplyBefore,
            "[lpProvider1] collateral rewards are pro rata"
        );

        assertEq(
            collateralShareToken.balanceOf(makeAddr("lpProvider2")),
            shares2 * collateralRewards / totalSupplyBefore,
            "[lpProvider2] collateral rewards are pro rata"
        );

        assertEq(
            collateralShareToken.balanceOf(makeAddr("lpProvider3")),
            0,
            "[lpProvider3] no collateral rewards because deposit after liquidation"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_incentiveDistribution_twoRewardsReceivers -vv
    locally: 40s
    */
    function test_incentiveDistribution_twoRewardsReceivers_long_fuzz(uint64 _collateral, uint64 _protected) public {
        // (uint64 _collateral, uint64 _protected) = (27125091, 30817190);
        vm.assume(uint256(_collateral) + _protected > 0);

        (, ISilo debtSilo) = _getSilos();
        uint256 shares1 = debtSilo.deposit(Math.max(_collateral, _protected), makeAddr("lpProvider1"));

        _createIncentiveController();

        bool success =
            _createPosition({_borrower: borrower, _collateral: _collateral, _protected: _protected, _maxOut: true});

        vm.assume(success);

        (IShareToken collateralShareToken, IShareToken protectedShareToken,) = _getBorrowerShareTokens(borrower);
        string[] memory programNames = new string[](2);
        programNames[0] = _getProgramNameForAddress(address(collateralShareToken));
        programNames[1] = _getProgramNameForAddress(address(protectedShareToken));

        console2.log("programNames[0]", programNames[0]);
        console2.logBytes32(_getProgramIdForAddress(address(collateralShareToken)));
        console2.log("programNames[1]", programNames[1]);
        console2.logBytes32(_getProgramIdForAddress(address(protectedShareToken)));

        _moveUntillDefaultingPossible(borrower, 0.001e18, 1 hours);

        vm.assume(_tryDefaulting(borrower));

        uint256 collateralRewards1 = collateralShareToken.balanceOf(address(gauge));
        uint256 protectedRewards1 = protectedShareToken.balanceOf(address(gauge));

        assertGt(collateralRewards1 + protectedRewards1, 0, "expect ANY rewards from first liquidation");
        uint256 lpPrivider1Assets = debtSilo.previewRedeem(shares1);

        // 20% to cover fees, +1 to not generate zero input
        debtSilo.deposit(lpPrivider1Assets * 12 / 10 + 1, makeAddr("lpProvider2"));
        console2.log("lpPrivider1Assets + 20%", lpPrivider1Assets);

        vm.startPrank(makeAddr("lpProvider1"));
        try debtSilo.redeem(shares1, makeAddr("lpProvider1"), makeAddr("lpProvider1")) {
            // nothing to do
        } catch {
            // we need be able to redeem, so lpProvider1 exit
            vm.assume(false);
        }
        vm.stopPrank();

        success = _createPosition({
            _borrower: makeAddr("borrower2"),
            _collateral: _collateral,
            _protected: _protected,
            _maxOut: true
        });
        console2.log("success", success);

        vm.assume(success);

        uint256 rewardsBalanceCollateral1 = gauge.getRewardsBalance(makeAddr("lpProvider1"), programNames[0]);
        uint256 rewardsBalanceProtected1 = gauge.getRewardsBalance(makeAddr("lpProvider1"), programNames[1]);

        assertGt(rewardsBalanceCollateral1 + rewardsBalanceProtected1, 0, "[lpProvider1] has claimable rewards");

        vm.prank(makeAddr("lpProvider1"));
        gauge.claimRewards(makeAddr("lpProvider1"));

        _moveUntillDefaultingPossible(makeAddr("borrower2"), 0.001e18, 1 hours);

        vm.assume(_tryDefaulting(makeAddr("borrower2")));

        uint256 collateralRewards2 = collateralShareToken.balanceOf(address(gauge));
        uint256 protectedRewards2 = protectedShareToken.balanceOf(address(gauge));

        assertGt(collateralRewards2 + protectedRewards2, 0, "expect ANY rewards from second liquidation");

        vm.warp(block.timestamp + 1 hours);

        console2.log("block.timestamp", block.timestamp);

        uint256 rewardsBalanceCollateral2 = gauge.getRewardsBalance(makeAddr("lpProvider2"), programNames[0]);
        uint256 rewardsBalanceProtected2 = gauge.getRewardsBalance(makeAddr("lpProvider2"), programNames[1]);

        assertEq(
            gauge.getRewardsBalance(makeAddr("lpProvider1"), programNames[0]),
            0,
            "[lpProvider1] no collateral rewards after redeem all collateral"
        );

        assertEq(
            gauge.getRewardsBalance(makeAddr("lpProvider1"), programNames[1]),
            0,
            "[lpProvider1] no protected rewards after redeem all collateral"
        );

        assertGt(rewardsBalanceCollateral2 + rewardsBalanceProtected2, 0, "[lpProvider2] has claimable rewards");

        vm.prank(makeAddr("lpProvider2"));
        gauge.claimRewards(makeAddr("lpProvider2"));

        assertLe(
            collateralRewards1 - collateralShareToken.balanceOf(makeAddr("lpProvider1")),
            1,
            "[lpProvider1] collateral rewards from first liquidation"
        );

        assertLe(
            protectedRewards1 - protectedShareToken.balanceOf(makeAddr("lpProvider1")),
            1,
            "[lpProvider1] protected rewards from first liquidation"
        );

        assertLe(
            collateralRewards2 - collateralShareToken.balanceOf(makeAddr("lpProvider2")),
            2, // 1 leftover from first + 1 from second liquidation
            "[lpProvider2] collateral rewards from second liquidation"
        );

        assertLe(
            protectedRewards2 - protectedShareToken.balanceOf(makeAddr("lpProvider2")),
            2, // 1 leftover from first + 1 from second liquidation
            "[lpProvider2] protected rewards from second liquidation"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_incentiveDistribution_gaugeManagement -vv
    */
    function test_incentiveDistribution_gaugeManagement_noWarp() public virtual;

    function test_incentiveDistribution_gaugeManagement_warp() public virtual;

    function _incentiveDistribution_gaugeManagement(bool _warp)
        internal
        returns (
            ISiloIncentivesController gauge2,
            ISiloIncentivesController gauge3,
            IShareToken borrowerCollateralShareToken,
            IShareToken borrowerProtectedShareToken
        )
    {
        uint64 _collateral = 10e18;

        ISiloIncentivesController gauge1 = _createIncentiveController();
        if (_warp) vm.warp(block.timestamp + 1 hours);

        (, ISilo debtSilo) = _getSilos();
        uint256 shares1 = debtSilo.deposit(_collateral, makeAddr("lpProvider1"));
        if (_warp) vm.warp(block.timestamp + 1 hours);

        _removeIncentiveController();
        if (_warp) vm.warp(block.timestamp + 1 hours);

        uint256 shares2 = debtSilo.deposit(_collateral, makeAddr("lpProvider2"));
        assertEq(shares1, shares2, "we should get same shares, because no interest yet");
        if (_warp) vm.warp(block.timestamp + 1 hours);

        // it will stay not liquidated
        bool success = _createPosition({_borrower: borrower, _collateral: 1e5, _protected: 1e5, _maxOut: true});
        (borrowerCollateralShareToken, borrowerProtectedShareToken,) = _getBorrowerShareTokens(borrower);

        console2.log("protected shares borrower=", borrowerProtectedShareToken.balanceOf(borrower));
        assertTrue(success, "create position should succeed");
        if (_warp) vm.warp(block.timestamp + 1 hours);

        gauge2 = _createIncentiveController();
        if (_warp) vm.warp(block.timestamp + 1 hours);

        success = _createPosition({_borrower: makeAddr("borrower2"), _collateral: 1e18, _protected: 0, _maxOut: true});
        assertTrue(success, "create position2 should succeed");
        if (_warp) vm.warp(block.timestamp + 1 hours);

        _moveUntillDefaultingPossible(makeAddr("borrower2"), 0.001e18, 1 hours);

        success =
            _createPosition({_borrower: makeAddr("borrower3"), _collateral: 0, _protected: 0.1e18, _maxOut: true});
        assertTrue(success, "create position3 should succeed");
        if (_warp) vm.warp(block.timestamp + 1 hours);

        vm.prank(makeAddr("keeper2"));
        defaulting.liquidationCallByDefaulting(makeAddr("borrower2"));

        assertEq(borrowerProtectedShareToken.balanceOf(address(gauge2)), 0, "gauge2 should have no protected rewards");

        if (_warp) vm.warp(block.timestamp + 1 hours);

        _removeIncentiveController();
        gauge3 = _createIncentiveController();
        if (_warp) vm.warp(block.timestamp + 1 hours);

        _moveUntillDefaultingPossible(makeAddr("borrower3"), 0.001e18, 1 hours);
        _printLtv(makeAddr("borrower3"));
        console2.log("max repay", debtSilo.maxRepay(makeAddr("borrower3")));
        console2.log("protected shares=", borrowerProtectedShareToken.balanceOf(makeAddr("borrower3")));
        vm.prank(makeAddr("keeper3"));
        defaulting.liquidationCallByDefaulting(makeAddr("borrower3"));
        _printLtv(makeAddr("borrower3"));

        // common checkes

        assertEq(
            borrowerCollateralShareToken.balanceOf(address(gauge1)), 0, "gauge1 should have NO collateral rewards"
        );
        assertEq(borrowerProtectedShareToken.balanceOf(address(gauge1)), 0, "gauge1 should have NO protected rewards");

        assertEq(
            borrowerCollateralShareToken.balanceOf(address(gauge3)), 0, "gauge3 should have NO collateral rewards"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_defaulting_onlyAllowedOrPublic -vv
    */
    function test_defaulting_onlyAllowedOrPublic() public {
        Whitelist whitelist = Whitelist(address(defaulting));
        bytes32 role = whitelist.ALLOWED_ROLE();
        address allowed = makeAddr("allowed");

        vm.prank(Ownable(address(defaulting)).owner());
        whitelist.grantRole(role, allowed);

        vm.expectRevert(Whitelist.OnlyAllowedRole.selector);
        defaulting.liquidationCallByDefaulting(address(2));

        vm.prank(allowed);
        vm.expectRevert(IPartialLiquidation.UserIsSolvent.selector);
        defaulting.liquidationCallByDefaulting(address(2));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_createIncentiveController_forWrongToken_reverts -vv
    */
    function test_createIncentiveController_forWrongToken_reverts() public {
        (ISilo collateralSilo, ISilo debtSilo) = _getSilos();
        ISiloIncentivesController gauge =
            new SiloIncentivesControllerCompatible(address(this), address(defaulting), address(collateralSilo));

        address owner = Ownable(address(defaulting)).owner();

        vm.prank(owner);
        IGaugeHookReceiver(address(defaulting)).setGauge(gauge, IShareToken(address(collateralSilo)));

        vm.expectRevert(IPartialLiquidationByDefaulting.NoControllerForCollateral.selector);
        defaulting.validateControllerForCollateral(address(debtSilo));
    }
}
