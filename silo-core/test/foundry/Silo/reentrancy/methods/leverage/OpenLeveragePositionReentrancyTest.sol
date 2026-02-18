// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20Permit} from "openzeppelin5/token/ERC20/extensions/IERC20Permit.sol";
import {MessageHashUtils} from "openzeppelin5/utils/cryptography/MessageHashUtils.sol";
import {Vm} from "forge-std/Vm.sol";

import {LeverageUsingSiloFlashloanWithGeneralSwap} from
    "silo-core/contracts/leverage/LeverageUsingSiloFlashloanWithGeneralSwap.sol";
import {LeverageRouter} from "silo-core/contracts/leverage/LeverageRouter.sol";
import {ILeverageRouter} from "silo-core/contracts/interfaces/ILeverageRouter.sol";
import {ILeverageUsingSiloFlashloan} from "silo-core/contracts/interfaces/ILeverageUsingSiloFlashloan.sol";
import {IGeneralSwapModule} from "silo-core/contracts/interfaces/IGeneralSwapModule.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IERC20R} from "silo-core/contracts/interfaces/IERC20R.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {SwapRouterMock} from "silo-core/test/foundry/leverage/mocks/SwapRouterMock.sol";
import {TransientReentrancy} from "silo-core/contracts/hooks/_common/TransientReentrancy.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";
import {MaliciousToken} from "../../MaliciousToken.sol";

contract OpenLeveragePositionReentrancyTest is MethodReentrancyTest {
    SwapRouterMock public swap = new SwapRouterMock();

    Vm.Wallet public wallet = vm.createWallet("User");

    bytes32 internal constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function callMethod() external virtual {
        _openLeverage();
    }

    function verifyReentrancy() external virtual {
        address user = wallet.addr;

        (
            ILeverageUsingSiloFlashloan.FlashArgs memory flashArgs,
            ILeverageUsingSiloFlashloan.DepositArgs memory depositArgs,
            IGeneralSwapModule.SwapArgs memory swapArgs
        ) = _prepareLeverageArgs(0, 0);

        // Execute leverage position opening
        LeverageRouter router = _getLeverageRouter();

        vm.prank(user);
        vm.expectRevert(TransientReentrancy.ReentrancyGuardReentrantCall.selector);
        router.openLeveragePosition(flashArgs, abi.encode(swapArgs), depositArgs);
    }

    function methodDescription() external pure virtual returns (string memory description) {
        description = "openLeveragePosition((address,uint256),bytes,(address,uint256,uint8))";
    }

    function _getLeverage() internal view returns (LeverageUsingSiloFlashloanWithGeneralSwap) {
        ILeverageRouter leverageRouter = ILeverageRouter(TestStateLib.leverageRouter());
        return LeverageUsingSiloFlashloanWithGeneralSwap(leverageRouter.LEVERAGE_IMPLEMENTATION());
    }

    function _getLeverageRouter() internal view returns (LeverageRouter) {
        return LeverageRouter(TestStateLib.leverageRouter());
    }

    function _openLeverage() internal {
        address user = makeAddr("User");
        uint256 depositAmount = 0.1e18;
        uint256 flashloanAmount = depositAmount * 1.08e18 / 1e18;

        _depositLiquidity();
        _mintUserTokensAndApprove(user, depositAmount, flashloanAmount, swap, true);

        // Prepare leverage arguments
        (
            ILeverageUsingSiloFlashloan.FlashArgs memory flashArgs,
            ILeverageUsingSiloFlashloan.DepositArgs memory depositArgs,
            IGeneralSwapModule.SwapArgs memory swapArgs
        ) = _prepareLeverageArgs(flashloanAmount, depositAmount);

        // mock the swap: debt token -> collateral token, price is 1:1, lt's mock some fee
        swap.setSwap(TestStateLib.token0(), flashloanAmount, TestStateLib.token1(), flashloanAmount * 99 / 100);

        TestStateLib.enableLeverageReentrancy();

        // Execute leverage position opening
        LeverageRouter router = _getLeverageRouter();

        vm.prank(user);
        router.openLeveragePosition(flashArgs, abi.encode(swapArgs), depositArgs);

        TestStateLib.disableLeverageReentrancy();
    }

    function _depositLiquidity() internal {
        address liquidityProvider = makeAddr("LiquidityProvider");
        uint256 liquidityAmount = 100e18;

        ISilo silo0 = TestStateLib.silo0();
        address token0 = TestStateLib.token0();

        TestStateLib.disableReentrancy();

        MaliciousToken(token0).mint(liquidityProvider, liquidityAmount);

        vm.prank(liquidityProvider);
        MaliciousToken(token0).approve(address(silo0), liquidityAmount);

        vm.prank(liquidityProvider);
        silo0.deposit(liquidityAmount, liquidityProvider, ISilo.CollateralType.Collateral);

        TestStateLib.enableReentrancy();
    }

    function _mintUserTokensAndApprove(
        address _user,
        uint256 _depositAmount,
        uint256 _flashloanAmount,
        SwapRouterMock, /*_swap*/
        bool _approveAssets
    ) internal {
        // Get user's leverage contract from router
        LeverageRouter router = _getLeverageRouter();
        address userLeverageContract = router.predictUserLeverageContract(_user);

        // Mint tokens for user. Silo reentrancy test is disabled.
        TestStateLib.disableReentrancy();

        MaliciousToken(TestStateLib.token1()).mint(_user, _depositAmount);

        vm.startPrank(_user);

        if (_approveAssets) {
            // Approve user's leverage contract to pull deposit tokens
            MaliciousToken(TestStateLib.token1()).approve(userLeverageContract, _depositAmount);
        }

        // Get debt share token from silo0
        ISiloConfig config = TestStateLib.silo0().config();
        (,, address debtShareToken) = config.getShareTokens(address(TestStateLib.silo0()));

        uint256 debtReceiveApproval = router.calculateDebtReceiveApproval(TestStateLib.silo0(), _flashloanAmount);

        IERC20R(debtShareToken).setReceiveApproval(userLeverageContract, debtReceiveApproval);

        vm.stopPrank();
    }

    function _generatePermit(address _token)
        internal
        view
        returns (ILeverageUsingSiloFlashloan.Permit memory permit)
    {
        uint256 nonce = IERC20Permit(_token).nonces(wallet.addr);

        permit = ILeverageUsingSiloFlashloan.Permit({
            value: 1000e18,
            deadline: block.timestamp + 1000,
            v: 0,
            r: "",
            s: ""
        });

        // Get user's leverage contract for the permit
        LeverageRouter router = _getLeverageRouter();
        address userLeverageContract = router.predictUserLeverageContract(wallet.addr);

        (permit.v, permit.r, permit.s) = _createPermit({
            _signer: wallet.addr,
            _signerPrivateKey: wallet.privateKey,
            _spender: userLeverageContract,
            _value: permit.value,
            _nonce: nonce,
            _deadline: permit.deadline,
            _token: _token
        });
    }

    function _createPermit(
        address _signer,
        uint256 _signerPrivateKey,
        address _spender,
        uint256 _value,
        uint256 _nonce,
        uint256 _deadline,
        address _token
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(abi.encode(_PERMIT_TYPEHASH, _signer, _spender, _value, _nonce, _deadline));

        bytes32 domainSeparator = IERC20Permit(_token).DOMAIN_SEPARATOR();
        bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);

        (v, r, s) = vm.sign(_signerPrivateKey, digest);
    }

    function _prepareLeverageArgs(uint256 _flashloanAmount, uint256 _depositAmount)
        internal
        view
        returns (
            ILeverageUsingSiloFlashloan.FlashArgs memory flashArgs,
            ILeverageUsingSiloFlashloan.DepositArgs memory depositArgs,
            IGeneralSwapModule.SwapArgs memory swapArgs
        )
    {
        // Prepare leverage arguments
        flashArgs = ILeverageUsingSiloFlashloan.FlashArgs({
            flashloanTarget: address(TestStateLib.silo0()),
            amount: _flashloanAmount
        });

        depositArgs = ILeverageUsingSiloFlashloan.DepositArgs({
            silo: TestStateLib.silo1(),
            amount: _depositAmount,
            collateralType: ISilo.CollateralType.Collateral
        });

        // Mock swap module arguments
        swapArgs = IGeneralSwapModule.SwapArgs({
            buyToken: TestStateLib.token1(),
            sellToken: TestStateLib.token0(),
            allowanceTarget: address(swap),
            exchangeProxy: address(swap),
            swapCallData: "mocked swap data"
        });
    }
}
