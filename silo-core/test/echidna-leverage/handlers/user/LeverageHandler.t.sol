// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Interfaces
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ILeverageUsingSiloFlashloan} from "silo-core/contracts/interfaces/ILeverageUsingSiloFlashloan.sol";
import {ILeverageRouter} from "silo-core/contracts/interfaces/ILeverageRouter.sol";

import {IERC3156FlashLender} from "silo-core/contracts/interfaces/IERC3156FlashLender.sol";
import {IGeneralSwapModule} from "silo-core/contracts/interfaces/IGeneralSwapModule.sol";
import {
    LeverageUsingSiloFlashloanWithGeneralSwap,
    LeverageUsingSiloFlashloan
} from "silo-core/contracts/leverage/LeverageUsingSiloFlashloanWithGeneralSwap.sol";
import {PausableWithAccessControl} from "common/utils/PausableWithAccessControl.sol";
import {RescueModule} from "silo-core/contracts/leverage/modules/RescueModule.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {Actor} from "silo-core/test/invariants/utils/Actor.sol";
import {ActorLeverage} from "silo-core/test/echidna-leverage/utils/ActorLeverage.sol";

// Libraries
import {console2} from "forge-std/console2.sol";

// Test Contracts
import {BaseHandlerLeverage} from "../../base/BaseHandlerLeverage.t.sol";
import {TestERC20} from "silo-core/test/invariants/utils/mocks/TestERC20.sol";
import {TestWETH} from "silo-core/test/echidna-leverage/utils/mocks/TestWETH.sol";
import {MockSiloOracle} from "silo-core/test/invariants/utils/mocks/MockSiloOracle.sol";

/// @title LeverageHandler
/// @notice Handler test contract for a set of actions
contract LeverageHandler is BaseHandlerLeverage {
    function rescueTokens(IERC20 _token, uint8 _i) external payable setupRandomActor(_i) {
        RescueModule rescueModule = RescueModule(leverageRouter.predictUserLeverageContract(targetActor));

        _before();

        actor.proxy(address(rescueModule), abi.encodeWithSelector(RescueModule.rescueTokens.selector, _token));

        _after();

        assertEq(
            _token.balanceOf(address(rescueModule)), 0, "after rescue (success of fail) there should be 0 tokens"
        );
    }

    function swapModuleDonation(uint256 _t) external {
        _donation(address(_swapModuleAddress()), _t);
    }

    function siloLeverageImplementationDonation(uint256 _t) external {
        _donation(leverageRouter.LEVERAGE_IMPLEMENTATION(), _t);
    }

    function revenueModelDonation(uint256 _t) external {
        _donation(address(_userLeverageContract(targetActor)), _t);
    }

    function siloLeverageDonation(uint256 _t) external {
        _donation(address(leverageRouter), _t);
    }

    function setLeverageFee(uint256 _fee) external setupRandomActor(0) {
        address owner = leverageRouter.getRoleMember(leverageRouter.DEFAULT_ADMIN_ROLE(), 1);
        assertEq(owner, targetActor, "[setLeverageFee] sanity check actor#0 is an owner#1");

        uint256 cap = leverageRouter.MAX_LEVERAGE_FEE();
        uint256 fee = leverageRouter.leverageFee();

        (bool success,) = actor.proxy(
            address(leverageRouter), abi.encodeWithSelector(ILeverageRouter.setLeverageFee.selector, _fee % cap)
        );

        if (!success) assertEq(fee, leverageRouter.leverageFee(), "when fail, fee is not changed");
    }

    function togglePauseRouter() external setupRandomActor(0) {
        bool paused = leverageRouter.paused();

        bytes4 selector =
            paused ? PausableWithAccessControl.unpause.selector : PausableWithAccessControl.pause.selector;
        actor.proxy(address(leverageRouter), abi.encodeWithSelector(selector));

        assertTrue(paused != leverageRouter.paused(), "pause/unpause should toggle state");
    }

    function onFlashLoan(
        address _initiator,
        uint256 _flashloanAmount,
        uint256 _flashloanFee,
        bytes calldata _data,
        RandomGenerator calldata _random
    ) external payable setupRandomActor(_random.i) {
        LeverageUsingSiloFlashloan leverage = _userLeverageContract(targetActor);
        if (address(leverage) == address(0)) return;

        address silo = _getRandomSilo(_random.j);
        address _borrowToken = ISilo(silo).asset();

        (bool success,) = actor.proxy(
            address(leverage),
            abi.encodeWithSelector(
                LeverageUsingSiloFlashloan.onFlashLoan.selector,
                _initiator,
                _borrowToken,
                _flashloanAmount,
                _flashloanFee,
                _data
            )
        );

        assertFalse(success, "[onFlashLoan] direct call on onFlashLoan should always revert");
    }

    function openLeveragePosition(
        uint64 _depositPercent,
        uint64 _flashloanPercent,
        RandomGenerator calldata _random
    ) external payable setupRandomActor(_random.i) {
        if (_userWhoOnlyApprove() == targetActor) {
            return;
        }

        uint256 _PRECISION = 1e18;

        // it allows to set 110%, so we do not exclude cases when user pick value that is too high
        _flashloanPercent = _flashloanPercent % 1.1e18;
        _depositPercent = _depositPercent % 1.1e18;

        console2.log("targetActor", targetActor, address(actor));

        address silo = _getRandomSilo(_random.j);

        ILeverageUsingSiloFlashloan.FlashArgs memory flashArgs;
        ILeverageUsingSiloFlashloan.DepositArgs memory depositArgs;
        IGeneralSwapModule.SwapArgs memory swapArgs;

        address otherSilo = _getOtherSilo(silo);
        uint256 maxFlashloan = IERC3156FlashLender(otherSilo).maxFlashLoan(ISilo(otherSilo).asset());

        flashArgs = ILeverageUsingSiloFlashloan.FlashArgs({
            amount: maxFlashloan * _flashloanPercent / _PRECISION,
            flashloanTarget: otherSilo
        });

        address depositAsset = ISilo(silo).asset();
        uint256 depositAmount = IERC20(depositAsset).balanceOf(targetActor) * _depositPercent / _PRECISION;

        depositArgs = ILeverageUsingSiloFlashloan.DepositArgs({
            amount: depositAmount,
            collateralType: ISilo.CollateralType(_random.k % 2),
            silo: ISilo(silo)
        });

        swapArgs = IGeneralSwapModule.SwapArgs({
            buyToken: depositAsset,
            sellToken: ISilo(flashArgs.flashloanTarget).asset(),
            allowanceTarget: address(swapRouterMock),
            exchangeProxy: address(swapRouterMock),
            swapCallData: "mocked swap data"
        });

        uint256 amountOut = _quote(flashArgs.amount, swapArgs.sellToken) * 995 / 1000;
        console2.log("amountOut", amountOut);
        // swap with 0.5% slippage
        swapRouterMock.setSwap(swapArgs.sellToken, flashArgs.amount, swapArgs.buyToken, amountOut);

        uint256 beforeDebt = ISilo(flashArgs.flashloanTarget).maxRepay(targetActor);

        _before();

        (bool success,) = actor.proxy(
            address(leverageRouter),
            abi.encodeWithSelector(
                ILeverageRouter.openLeveragePosition.selector, flashArgs, abi.encode(swapArgs), depositArgs
            ),
            msg.value != 0 ? depositAmount : 0 // we need to keep msg.value in sync with depositArgs.amount
        );

        _after();

        _assert_userLEverageIsPausedWhenRouterIsPaused(success);

        uint256 afterDebt = ISilo(flashArgs.flashloanTarget).maxRepay(targetActor);

        if (success) {
            assert_UserLeverageContractInstancesAreUnique();
            assert_PredictUserLeverageContractIsUnique();
            assert_PredictUserLeverageContractIsEqualToDeployed();

            assertGt(
                ISilo(flashArgs.flashloanTarget).maxRepay(targetActor),
                beforeDebt,
                "[openLeveragePosition] borrower should have additional debt created by leverage"
            );
        } else {
            assertEq(beforeDebt, afterDebt, "[openLeveragePosition] when leverage fail, debt does not change");
        }
    }

    function closeLeveragePosition(RandomGenerator calldata _random) external setupRandomActor(_random.i) {
        if (_userWhoOnlyApprove() == targetActor) {
            return;
        }

        address silo = _getRandomSilo(_random.j);

        ILeverageUsingSiloFlashloan.CloseLeverageArgs memory closeArgs;
        IGeneralSwapModule.SwapArgs memory swapArgs;

        closeArgs = ILeverageUsingSiloFlashloan.CloseLeverageArgs({
            flashloanTarget: _getOtherSilo(silo),
            siloWithCollateral: ISilo(silo),
            collateralType: ISilo.CollateralType(_random.k % 2)
        });

        uint256 flashAmount = ISilo(closeArgs.flashloanTarget).maxRepay(targetActor);

        if (flashAmount == 0) {
            return;
        }

        // we need to count for slippage, so we have to take higher amount in
        uint256 amountIn = flashAmount * (100 + (_random.j % 5)) / 100;

        // omount out with some random slippage
        uint256 amountOut =
            _quote(amountIn, ISilo(closeArgs.flashloanTarget).asset()) * (1000 - (_random.k % 50)) / 1000;

        swapArgs = IGeneralSwapModule.SwapArgs({
            buyToken: ISilo(closeArgs.flashloanTarget).asset(),
            sellToken: ISilo(closeArgs.siloWithCollateral).asset(),
            allowanceTarget: address(swapRouterMock),
            exchangeProxy: address(swapRouterMock),
            swapCallData: "mocked swap data"
        });

        swapRouterMock.setSwap(swapArgs.sellToken, amountIn, swapArgs.buyToken, amountOut);

        _before();

        (bool success,) = actor.proxy(
            address(leverageRouter),
            abi.encodeWithSelector(ILeverageRouter.closeLeveragePosition.selector, abi.encode(swapArgs), closeArgs)
        );

        _after();

        _assert_userLEverageIsPausedWhenRouterIsPaused(success);

        if (success) {
            assert_UserLeverageContractInstancesAreUnique();
            assert_PredictUserLeverageContractIsUnique();
            assert_PredictUserLeverageContractIsEqualToDeployed();

            assertEq(ISilo(closeArgs.flashloanTarget).maxRepay(targetActor), 0, "borrower should have no debt");
        }
    }

    function _assert_userLEverageIsPausedWhenRouterIsPaused(bool _txSuccessful) internal {
        if (!leverageRouter.paused()) {
            return;
        }

        assertFalse(_txSuccessful, "tx MUST be reverted when router is paused");
    }

    function echidna_UserLeverageContractInstancesAreUnique() public returns (bool) {
        assert_UserLeverageContractInstancesAreUnique();

        return true;
    }

    function assert_UserLeverageContractInstancesAreUnique() public {
        for (uint256 i; i + 1 < actorAddresses.length; i++) {
            for (uint256 j = i + 1; j < actorAddresses.length; j++) {
                _userLeverageContractInstancesAreUnique(actorAddresses[i], actorAddresses[j]);
            }
        }
    }

    function _userLeverageContractInstancesAreUnique(address _actorA, address _actorB) internal {
        if (_actorA == _actorB) return;

        address actorALeverageContract = address(leverageRouter.userLeverageContract(_actorA));
        if (actorALeverageContract == address(0)) return;
        address actorBLeverageContract = address(leverageRouter.userLeverageContract(_actorB));
        if (actorBLeverageContract == address(0)) return;

        assertTrue(
            actorALeverageContract != actorBLeverageContract,
            "actorA != actorB <=> userLeverageContract(actorA) != userLeverageContract(actorB)"
        );
    }

    function echidna_PredictUserLeverageContractIsUnique() public returns (bool) {
        assert_PredictUserLeverageContractIsUnique();

        return true;
    }

    function assert_PredictUserLeverageContractIsUnique() public {
        for (uint256 i; i + 1 < actorAddresses.length; i++) {
            for (uint256 j = i + 1; j < actorAddresses.length; j++) {
                _predictUserLeverageContractIsUnique(actorAddresses[i], actorAddresses[j]);
            }
        }
    }

    function _predictUserLeverageContractIsUnique(address _actorA, address _actorB) internal {
        if (_actorA == _actorB) return;

        address actorAPredictLeverageContract = address(leverageRouter.predictUserLeverageContract(_actorA));
        address actorBPredictLeverageContract = address(leverageRouter.predictUserLeverageContract(_actorB));

        assertTrue(
            actorAPredictLeverageContract != address(0), "predictUserLeverageContract(actorA) != 0, sanity check"
        );

        assertTrue(
            actorBPredictLeverageContract != address(0), "predictUserLeverageContract(actorB) != 0, sanity check"
        );

        assertTrue(
            actorAPredictLeverageContract != actorBPredictLeverageContract,
            "actorA != actorB <=> predictUserLeverageContract(actorA) != predictUserLeverageContract(actorB)"
        );
    }

    function echidna_PredictUserLeverageContractIsEqualToDeployed() public returns (bool) {
        assert_PredictUserLeverageContractIsEqualToDeployed();

        return true;
    }

    function assert_PredictUserLeverageContractIsEqualToDeployed() public {
        for (uint256 i; i < actorAddresses.length; i++) {
            address user = actorAddresses[i];
            address userLeverageContract = address(leverageRouter.userLeverageContract(user));
            if (userLeverageContract == address(0)) continue;

            address userPredictLeverageContract = address(leverageRouter.predictUserLeverageContract(user));

            assertEq(
                userLeverageContract,
                userPredictLeverageContract,
                "predictUserLeverageContract(user) == userLeverageContract(user), userLeverageContract != 0"
            );
        }
    }

    function assert_AllowanceDoesNotChangedForUserWhoOnlyApprove() public {
        address user = _userWhoOnlyApprove();
        address userLeverage = address(_userPredictedLeverageContract(user));

        assertEq(_asset0.allowance(user, userLeverage), type(uint256).max, "approval0 must stay");
        assertEq(_asset1.allowance(user, userLeverage), type(uint256).max, "approval1 must stay");
    }

    function echidna_AllowanceDoesNotChangedForUserWhoOnlyApprove() public returns (bool) {
        assert_AllowanceDoesNotChangedForUserWhoOnlyApprove();

        return true;
    }

    function _userWhoOnlyApprove() internal view returns (address) {
        // this user only approve leverage and we expect approval did not changed
        return actorAddresses[0];
    }

    function _donation(address _target, uint256 _randomToken) internal {
        if (_target == address(0)) return;

        if (_randomToken == 0) {
            payable(_target).transfer(1e18);

            assertGt(_target.balance, 0, "[_donation] expect ETH to be send");
        } else {
            TestERC20 token = _randomToken % 2 == 0 ? _asset0 : _asset1;
            token.mint(_target, 1e18);

            assertGt(token.balanceOf(_target), 0, "[_donation] expect tokens to be send");
        }
    }

    function _userLeverageContract(address _user)
        internal
        view
        returns (LeverageUsingSiloFlashloanWithGeneralSwap)
    {
        return LeverageUsingSiloFlashloanWithGeneralSwap(address(leverageRouter.userLeverageContract(_user)));
    }

    function _userPredictedLeverageContract(address _user)
        internal
        view
        returns (LeverageUsingSiloFlashloanWithGeneralSwap)
    {
        return LeverageUsingSiloFlashloanWithGeneralSwap(address(leverageRouter.predictUserLeverageContract(_user)));
    }

    function _swapModuleAddress() internal view returns (IGeneralSwapModule swapModule) {
        return LeverageUsingSiloFlashloanWithGeneralSwap(leverageRouter.LEVERAGE_IMPLEMENTATION()).SWAP_MODULE();
    }

    function _quote(uint256 _amount, address _baseToken) internal view returns (uint256 amountOut) {
        MockSiloOracle oracle = MockSiloOracle(address(_asset0) == _baseToken ? oracle0 : oracle1);
        amountOut = oracle.quote(_amount, _baseToken);
    }
}
