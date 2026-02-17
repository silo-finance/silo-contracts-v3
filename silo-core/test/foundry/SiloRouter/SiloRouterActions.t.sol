// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {IERC20Errors} from "openzeppelin5/interfaces/draft-IERC6093.sol";
import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";
import {Ownable} from "openzeppelin5/access/Ownable.sol";
import {Pausable} from "openzeppelin5/utils/Pausable.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin5-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {SiloRouterV2Deploy} from "silo-core/deploy/SiloRouterV2Deploy.s.sol";
import {SiloRouterV2} from "silo-core/contracts/silo-router/SiloRouterV2.sol";
import {SiloDeployments, SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloRouterV2} from "silo-core/contracts/interfaces/ISiloRouterV2.sol";
import {SiloRouterV2Implementation} from "silo-core/contracts/silo-router/SiloRouterV2Implementation.sol";
import {IWrappedNativeToken} from "silo-core/contracts/interfaces/IWrappedNativeToken.sol";
import {ShareTokenDecimalsPowLib} from "../_common/ShareTokenDecimalsPowLib.sol";

// solhint-disable function-max-lines

// FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc SiloRouterV2ActionsTest
contract SiloRouterV2ActionsTest is IntegrationTest {
    using ShareTokenDecimalsPowLib for uint256;

    uint256 internal constant _FORKING_BLOCK_NUMBER = 5222185;
    uint256 internal constant _S_BALANCE = 10e18;
    uint256 internal constant _TOKEN0_AMOUNT = 100e18;
    uint256 internal constant _TOKEN1_AMOUNT = 100e6;

    address public silo0;
    address public silo1;
    address public token0; // S
    address public token1; // WETH

    address public depositor = makeAddr("Depositor");
    address public borrower = makeAddr("Borrower");

    IWrappedNativeToken public nativeToken = IWrappedNativeToken(0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38);

    address public wsWhale = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public wethWhale = 0x431e81E5dfB5A24541b5Ff8762bDEF3f32F96354;

    address public collateralToken0;
    address public protectedToken0;
    address public debtToken0;

    address public collateralToken1;
    address public protectedToken1;
    address public debtToken1;

    SiloRouterV2 public router;
    address public routerOwner;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_SONIC"), _FORKING_BLOCK_NUMBER);

        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        routerOwner = vm.addr(deployerPrivateKey);

        SiloRouterV2Deploy deploy = new SiloRouterV2Deploy();
        deploy.disableDeploymentsSync();

        router = deploy.run();

        address siloConfig = 0x9603Af53dC37F4BB6386f358A51a04fA8f599101; // S/ETH

        (silo0, silo1) = ISiloConfig(siloConfig).getSilos();

        token0 = ISiloConfig(siloConfig).getAssetForSilo(silo0);
        token1 = ISiloConfig(siloConfig).getAssetForSilo(silo1);

        (protectedToken0, collateralToken0, debtToken0) = ISiloConfig(siloConfig).getShareTokens(silo0);
        (protectedToken1, collateralToken1, debtToken1) = ISiloConfig(siloConfig).getShareTokens(silo1);

        vm.prank(wsWhale);
        IERC20(token0).transfer(depositor, _TOKEN0_AMOUNT);

        vm.prank(wsWhale);
        IERC20(token0).transfer(borrower, _TOKEN0_AMOUNT);

        vm.prank(depositor);
        IERC20(token0).approve(address(router), type(uint256).max);

        vm.prank(depositor);
        IERC20(token1).approve(address(router), type(uint256).max);

        vm.prank(borrower);
        IERC20(token0).approve(address(router), type(uint256).max);

        vm.label(siloConfig, "siloConfig");
        vm.label(silo0, "silo0");
        vm.label(silo1, "silo1");
        vm.label(collateralToken0, "collateralToken0");
        vm.label(protectedToken0, "protectedToken0");
        vm.label(debtToken0, "debtToken0");
        vm.label(collateralToken1, "collateralToken1");
        vm.label(protectedToken1, "protectedToken1");
        vm.label(debtToken1, "debtToken1");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_siloRouterV2_pause_unpause
    function test_siloRouterV2_pause_unpause() public {
        assertFalse(router.paused(), "Router should not be paused");

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));

        router.pause();

        vm.prank(routerOwner);
        router.pause();
        assertTrue(router.paused(), "Router should be paused");

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));

        router.unpause();

        vm.prank(routerOwner);
        router.unpause();
        assertFalse(router.paused(), "Router should not be paused");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_siloRouterV2_wrapAndTransfer_nativeToken
    function test_siloRouterV2_wrapAndTransfer_nativeToken() public {
        address receiver = makeAddr("Receiver");

        vm.prank(wsWhale);
        nativeToken.withdraw(_S_BALANCE);

        assertEq(nativeToken.balanceOf(receiver), 0, "Receiver should not have any native tokens");

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(SiloRouterV2Implementation.wrap, (IWrappedNativeToken(nativeToken), _S_BALANCE));
        data[1] = abi.encodeCall(SiloRouterV2Implementation.transfer, (nativeToken, receiver, _S_BALANCE));

        vm.prank(wsWhale);
        router.multicall{value: _S_BALANCE}(data);

        assertEq(nativeToken.balanceOf(receiver), _S_BALANCE, "Receiver should have native tokens");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_siloRouterV2_unwrapAndTransfer_nativeToken
    function test_siloRouterV2_unwrapAndTransfer_nativeToken() public {
        assertEq(wsWhale.balance, 0, "Account should not have any native tokens");

        vm.prank(wsWhale);
        IERC20(nativeToken).approve(address(router), _S_BALANCE);

        address receiver = makeAddr("Receiver");

        bytes[] memory data = new bytes[](3);

        data[0] = abi.encodeCall(
            SiloRouterV2Implementation.transferFrom, (IWrappedNativeToken(nativeToken), address(router), _S_BALANCE)
        );
        data[1] = abi.encodeCall(SiloRouterV2Implementation.unwrap, (IWrappedNativeToken(nativeToken), _S_BALANCE));
        data[2] = abi.encodeCall(SiloRouterV2Implementation.sendValue, (payable(receiver), _S_BALANCE));

        vm.prank(wsWhale);
        router.multicall(data);

        assertEq(receiver.balance, _S_BALANCE, "Account should have native tokens");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_siloRouterV2_unwrapAndSendAll_nativeToken
    function test_siloRouterV2_unwrapAndSendAll_nativeToken() public {
        assertEq(wsWhale.balance, 0, "Account should not have any native tokens");

        uint256 someAmount = _S_BALANCE + 1;

        vm.prank(wsWhale);
        nativeToken.transfer(address(router), someAmount);

        address receiver = makeAddr("Receiver");

        assertEq(nativeToken.balanceOf(address(router)), someAmount, "Router should have native tokens");

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(SiloRouterV2Implementation.unwrapAll, (IWrappedNativeToken(nativeToken)));
        data[1] = abi.encodeCall(SiloRouterV2Implementation.sendValueAll, (payable(receiver)));

        vm.prank(wsWhale);
        router.multicall(data);

        assertEq(receiver.balance, someAmount, "Account should have native tokens");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_siloRouterV2_approve
    function test_siloRouterV2_approve() public {
        assertEq(nativeToken.allowance(address(router), address(this)), 0, "Router should not have any allowance");

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(
            SiloRouterV2Implementation.approve, (IERC20(nativeToken), address(this), type(uint256).max)
        );

        vm.prank(wsWhale);
        router.multicall(data);

        assertEq(
            nativeToken.allowance(address(router), address(this)),
            type(uint256).max,
            "Router should have max allowance"
        );
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_siloRouterV2_transfer
    function test_siloRouterV2_transfer() public {
        assertEq(nativeToken.balanceOf(address(this)), 0, "Account should not have any native tokens");

        vm.prank(wsWhale);
        nativeToken.transfer(address(router), _S_BALANCE);

        address anyAddress = makeAddr("AnyAddress");

        bytes[] memory data = new bytes[](1);
        data[0] =
            abi.encodeCall(SiloRouterV2Implementation.transfer, (IERC20(nativeToken), address(this), _S_BALANCE));

        vm.prank(anyAddress);
        router.multicall(data);

        assertEq(nativeToken.balanceOf(address(this)), _S_BALANCE, "Account should have native tokens");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_siloRouterV2_transferFrom
    function test_siloRouterV2_transferFrom() public {
        assertEq(nativeToken.balanceOf(address(this)), 0, "Account should not have any native tokens");

        vm.prank(wsWhale);
        IERC20(nativeToken).approve(address(router), _S_BALANCE);

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(
            SiloRouterV2Implementation.transferFrom, (IERC20(nativeToken), address(this), _S_BALANCE)
        );

        vm.prank(wsWhale);
        router.multicall(data);

        assertEq(nativeToken.balanceOf(address(this)), _S_BALANCE, "Account should have native tokens");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_siloRouterV2_depositFlow
    function test_siloRouterV2_depositFlow() public {
        assertEq(IERC20(collateralToken0).balanceOf(depositor), 0, "Account should not have any collateral tokens");

        bytes[] memory data = new bytes[](3);
        data[0] =
            abi.encodeCall(SiloRouterV2Implementation.transferFrom, (IERC20(token0), address(router), _S_BALANCE));
        data[1] = abi.encodeCall(SiloRouterV2Implementation.approve, (IERC20(token0), address(silo0), _S_BALANCE));
        data[2] = abi.encodeCall(
            SiloRouterV2Implementation.deposit, (ISilo(silo0), _S_BALANCE, ISilo.CollateralType.Collateral)
        );

        vm.prank(depositor);
        router.multicall(data);

        assertNotEq(IERC20(collateralToken0).balanceOf(depositor), 0, "Account should have collateral tokens");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_siloRouterV2_depositNativeFlow
    function test_siloRouterV2_depositNativeFlow() public {
        assertEq(IERC20(collateralToken0).balanceOf(depositor), 0, "Account should not have any collateral tokens");

        vm.prank(depositor);
        nativeToken.withdraw(_S_BALANCE);

        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeCall(SiloRouterV2Implementation.wrap, (IWrappedNativeToken(nativeToken), _S_BALANCE));
        data[1] = abi.encodeCall(SiloRouterV2Implementation.approve, (IERC20(token0), address(silo0), _S_BALANCE));
        data[2] = abi.encodeCall(
            SiloRouterV2Implementation.deposit, (ISilo(silo0), _S_BALANCE, ISilo.CollateralType.Collateral)
        );

        vm.prank(depositor);
        router.multicall{value: _S_BALANCE}(data);

        assertNotEq(IERC20(collateralToken0).balanceOf(depositor), 0, "Account should have collateral tokens");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_siloRouterV2_withdrawFlow
    function test_siloRouterV2_withdrawFlow() public {
        uint256 depositorBalance = IERC20(token0).balanceOf(depositor);

        vm.prank(depositor);
        IERC20(token0).approve(address(silo0), _S_BALANCE);

        vm.prank(depositor);
        ISilo(silo0).deposit(_S_BALANCE, depositor);

        assertNotEq(IERC20(collateralToken0).balanceOf(depositor), 0, "Account should have collateral tokens");

        vm.prank(depositor);
        IERC20(collateralToken0).approve(address(router), type(uint256).max);

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(
            SiloRouterV2Implementation.withdraw,
            (ISilo(silo0), _S_BALANCE - 1, depositor, ISilo.CollateralType.Collateral)
        );

        vm.prank(depositor);
        router.multicall(data);

        assertEq(IERC20(collateralToken0).balanceOf(depositor), 999, "Account should not have deposit"); // rounding error
        assertEq(IERC20(token0).balanceOf(depositor), depositorBalance - 1, "Account should have tokens");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_siloRouterV2_withdrawNativeAndUnwrapFlow
    function test_siloRouterV2_withdrawNativeAndUnwrapFlow() public {
        vm.prank(depositor);
        IERC20(token0).approve(address(silo0), _S_BALANCE);

        vm.prank(depositor);
        ISilo(silo0).deposit(_S_BALANCE, depositor);

        assertNotEq(IERC20(collateralToken0).balanceOf(depositor), 0, "Account should have collateral tokens");

        vm.prank(depositor);
        IERC20(collateralToken0).approve(address(router), type(uint256).max);

        uint256 toWithdraw = _S_BALANCE - 1;

        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeCall(
            SiloRouterV2Implementation.withdraw,
            (ISilo(silo0), toWithdraw, address(router), ISilo.CollateralType.Collateral)
        );
        data[1] = abi.encodeCall(SiloRouterV2Implementation.unwrap, (IWrappedNativeToken(nativeToken), toWithdraw));
        data[2] = abi.encodeCall(SiloRouterV2Implementation.sendValue, (payable(depositor), toWithdraw));

        vm.prank(depositor);
        router.multicall(data);

        assertEq(IERC20(collateralToken0).balanceOf(depositor), 999, "Account should not have deposit"); // rounding error
        assertEq(depositor.balance, toWithdraw, "Account should have tokens");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_siloRouterV2_withdrawAllFlow
    function test_siloRouterV2_withdrawAllFlow() public {
        uint256 depositorBalance = IERC20(token0).balanceOf(depositor);

        vm.prank(depositor);
        IERC20(token0).approve(address(silo0), _S_BALANCE);

        vm.prank(depositor);
        ISilo(silo0).deposit(_S_BALANCE, depositor);

        assertEq(depositor.balance, 0, "Account should not have any native tokens");
        assertNotEq(IERC20(collateralToken0).balanceOf(depositor), 0, "Account should have collateral tokens");

        vm.prank(depositor);
        IERC20(collateralToken0).approve(address(router), type(uint256).max);

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(
            SiloRouterV2Implementation.withdrawAll, (ISilo(silo0), depositor, ISilo.CollateralType.Collateral)
        );

        vm.prank(depositor);
        router.multicall(data);

        assertEq(IERC20(collateralToken0).balanceOf(depositor), 0, "Account should not have deposit");
        assertEq(IERC20(token0).balanceOf(depositor), depositorBalance - 1, "Account should have tokens");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_siloRouterV2_withdrawAllAndUnwrapFlow
    function test_siloRouterV2_withdrawAllAndUnwrapFlow() public {
        vm.prank(depositor);
        IERC20(token0).approve(address(silo0), _S_BALANCE);

        vm.prank(depositor);
        ISilo(silo0).deposit(_S_BALANCE, depositor);

        assertEq(depositor.balance, 0, "Account should not have any native tokens");
        assertNotEq(IERC20(collateralToken0).balanceOf(depositor), 0, "Account should have collateral tokens");

        vm.prank(depositor);
        IERC20(collateralToken0).approve(address(router), type(uint256).max);

        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeCall(
            SiloRouterV2Implementation.withdrawAll, (ISilo(silo0), address(router), ISilo.CollateralType.Collateral)
        );
        data[1] = abi.encodeCall(SiloRouterV2Implementation.unwrapAll, (IWrappedNativeToken(nativeToken)));
        data[2] = abi.encodeCall(SiloRouterV2Implementation.sendValueAll, (payable(depositor)));

        vm.prank(depositor);
        router.multicall(data);

        assertEq(depositor.balance, _S_BALANCE - 1, "Account should have native tokens");
        assertEq(IERC20(collateralToken0).balanceOf(depositor), 0, "Account should not have collateral tokens");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_siloRouterV2_borrowFlow
    function test_siloRouterV2_borrowFlow() public {
        vm.prank(borrower);
        IERC20(token0).approve(address(silo0), _TOKEN0_AMOUNT);

        vm.prank(borrower);
        ISilo(silo0).deposit(_TOKEN0_AMOUNT, borrower);

        uint256 borrowAmount = ISilo(silo1).maxBorrow(borrower);

        assertEq(IERC20(debtToken1).balanceOf(borrower), 0, "Account should not have any debt tokens");

        vm.prank(borrower);
        IERC20(debtToken1).approve(address(router), type(uint256).max);

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(SiloRouterV2Implementation.borrow, (ISilo(silo1), borrowAmount, address(borrower)));

        vm.prank(borrower);
        router.multicall(data);

        assertNotEq(IERC20(debtToken1).balanceOf(borrower), 0, "Account should have debt tokens");
        assertEq(IERC20(token1).balanceOf(borrower), borrowAmount, "Account should have tokens");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_siloRouterV2_borrowNativeAndUnwrapFlow
    function test_siloRouterV2_borrowNativeAndUnwrapFlow() public {
        vm.prank(wethWhale);
        IERC20(token1).transfer(borrower, _TOKEN1_AMOUNT);

        vm.prank(borrower);
        IERC20(token1).approve(address(silo1), _TOKEN1_AMOUNT);

        vm.prank(borrower);
        ISilo(silo1).deposit(_TOKEN1_AMOUNT, borrower);

        assertEq(IERC20(debtToken0).balanceOf(borrower), 0, "Account should not have any debt tokens");

        vm.prank(borrower);
        IERC20(debtToken0).approve(address(router), type(uint256).max);

        uint256 borrowAmount = ISilo(silo0).maxBorrow(borrower);

        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeCall(SiloRouterV2Implementation.borrow, (ISilo(silo0), borrowAmount, address(router)));
        data[1] =
            abi.encodeCall(SiloRouterV2Implementation.unwrap, (IWrappedNativeToken(nativeToken), borrowAmount));
        data[2] = abi.encodeCall(SiloRouterV2Implementation.sendValue, (payable(borrower), borrowAmount));

        vm.prank(borrower);
        router.multicall(data);

        assertNotEq(IERC20(debtToken0).balanceOf(borrower), 0, "Account should have debt tokens");
        assertEq(borrower.balance, borrowAmount, "Account should have tokens");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_siloRouterV2_repayFlow
    function test_siloRouterV2_repayFlow() public {
        vm.prank(wethWhale);
        IERC20(token1).transfer(borrower, _TOKEN1_AMOUNT);

        vm.prank(borrower);
        IERC20(token1).approve(address(silo1), _TOKEN1_AMOUNT);

        vm.prank(borrower);
        ISilo(silo1).deposit(_TOKEN1_AMOUNT, borrower);

        assertEq(IERC20(debtToken0).balanceOf(borrower), 0, "Account should not have any debt tokens");

        uint256 borrowAmount = ISilo(silo0).maxBorrow(borrower);

        vm.prank(borrower);
        ISilo(silo0).borrow(borrowAmount, borrower, borrower);

        uint256 debtBalanceBefore = IERC20(debtToken0).balanceOf(borrower);

        assertNotEq(debtBalanceBefore, 0, "Account should have debt tokens");
        assertEq(borrower.balance, 0, "Account should not have any native tokens");

        uint256 repayAmount = ISilo(silo0).previewRepay(borrowAmount) / 2;

        vm.prank(borrower);
        IERC20(token0).approve(address(router), type(uint256).max);

        bytes[] memory data = new bytes[](3);
        data[0] =
            abi.encodeCall(SiloRouterV2Implementation.transferFrom, (IERC20(token0), address(router), repayAmount));
        data[1] =
            abi.encodeCall(SiloRouterV2Implementation.approve, (IERC20(token0), address(silo0), type(uint256).max));
        data[2] = abi.encodeCall(SiloRouterV2Implementation.repay, (ISilo(silo0), repayAmount));

        vm.prank(borrower);
        router.multicall(data);

        assertLt(IERC20(debtToken0).balanceOf(borrower), debtBalanceBefore, "Account should have less debt tokens");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_siloRouterV2_repayNativeWrapFlow
    function test_siloRouterV2_repayNativeWrapFlow() public {
        vm.prank(wethWhale);
        IERC20(token1).transfer(borrower, _TOKEN1_AMOUNT);

        vm.prank(borrower);
        IERC20(token1).approve(address(silo1), _TOKEN1_AMOUNT);

        vm.prank(borrower);
        ISilo(silo1).deposit(_TOKEN1_AMOUNT, borrower);

        assertEq(IERC20(debtToken0).balanceOf(borrower), 0, "Account should not have any debt tokens");

        uint256 borrowAmount = ISilo(silo0).maxBorrow(borrower);

        vm.prank(borrower);
        ISilo(silo0).borrow(borrowAmount, borrower, borrower);

        uint256 debtBalanceBefore = IERC20(debtToken0).balanceOf(borrower);

        assertNotEq(debtBalanceBefore, 0, "Account should have debt tokens");
        assertEq(borrower.balance, 0, "Account should not have any native tokens");

        uint256 repayAmount = ISilo(silo0).previewRepay(borrowAmount) / 2;

        vm.prank(borrower);
        nativeToken.withdraw(repayAmount);

        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeCall(SiloRouterV2Implementation.wrap, (IWrappedNativeToken(nativeToken), repayAmount));
        data[1] = abi.encodeCall(SiloRouterV2Implementation.approve, (IERC20(token0), address(silo0), repayAmount));
        data[2] = abi.encodeCall(SiloRouterV2Implementation.repay, (ISilo(silo0), repayAmount));

        vm.prank(borrower);
        router.multicall{value: repayAmount}(data);

        assertLt(IERC20(debtToken0).balanceOf(borrower), debtBalanceBefore, "Account should have less debt tokens");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_siloRouterV2_repayAllFlow
    function test_siloRouterV2_repayAllFlow() public {
        vm.prank(wethWhale);
        IERC20(token1).transfer(borrower, _TOKEN1_AMOUNT);

        vm.prank(borrower);
        IERC20(token1).approve(address(silo1), _TOKEN1_AMOUNT);

        vm.prank(borrower);
        ISilo(silo1).deposit(_TOKEN1_AMOUNT, borrower);

        assertEq(IERC20(debtToken0).balanceOf(borrower), 0, "Account should not have any debt tokens");

        uint256 borrowAmount = ISilo(silo0).maxBorrow(borrower);

        vm.prank(borrower);
        ISilo(silo0).borrow(borrowAmount, borrower, borrower);

        uint256 debtBalanceBefore = IERC20(debtToken0).balanceOf(borrower);

        assertNotEq(debtBalanceBefore, 0, "Account should have debt tokens");
        assertEq(borrower.balance, 0, "Account should not have any native tokens");

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(SiloRouterV2Implementation.repayAll, (ISilo(silo0)));

        vm.prank(borrower);
        router.multicall(data);

        assertEq(IERC20(debtToken0).balanceOf(borrower), 0, "Account should not have any debt tokens");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_siloRouterV2_repayAllNativeFlow
    function test_siloRouterV2_repayAllNativeFlow() public {
        vm.prank(wethWhale);
        IERC20(token1).transfer(borrower, _TOKEN1_AMOUNT);

        vm.prank(borrower);
        IERC20(token1).approve(address(silo1), _TOKEN1_AMOUNT);

        vm.prank(borrower);
        ISilo(silo1).deposit(_TOKEN1_AMOUNT, borrower);

        assertEq(IERC20(debtToken0).balanceOf(borrower), 0, "Account should not have any debt tokens");

        uint256 borrowAmount = ISilo(silo0).maxBorrow(borrower);

        vm.prank(borrower);
        ISilo(silo0).borrow(borrowAmount, borrower, borrower);

        uint256 debtBalanceBefore = IERC20(debtToken0).balanceOf(borrower);

        assertNotEq(debtBalanceBefore, 0, "Account should have debt tokens");
        assertEq(borrower.balance, 0, "Account should not have any native tokens");

        uint256 repayAmount = ISilo(silo0).maxRepay(borrower);
        repayAmount += repayAmount * 3 / 100; // add 3% buffer

        vm.prank(wsWhale);
        nativeToken.withdraw(repayAmount);

        vm.prank(wsWhale);
        payable(borrower).transfer(repayAmount);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeCall(
            SiloRouterV2Implementation.repayAllNative, (IWrappedNativeToken(nativeToken), ISilo(silo0))
        );
        data[1] = abi.encodeCall(SiloRouterV2Implementation.sendValueAll, (payable(borrower)));

        vm.prank(borrower);
        router.multicall{value: repayAmount}(data);

        assertEq(IERC20(debtToken0).balanceOf(borrower), 0, "Account should not have any debt tokens");
        assertEq(address(router).balance, 0, "Router should not have any native tokens");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_siloRouterV2_pause_allActions_viaMulticall
    function test_siloRouterV2_pause_allActions_viaMulticall() public {
        vm.prank(routerOwner);
        router.pause();
        assertTrue(router.paused(), "Router should be paused");

        bytes[] memory data = new bytes[](1);

        // testing multicall with pause with a few actions calls
        data[0] = abi.encodeCall(SiloRouterV2Implementation.wrap, (IWrappedNativeToken(nativeToken), 1));
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        router.multicall(data);

        data[0] = abi.encodeCall(SiloRouterV2Implementation.unwrap, (IWrappedNativeToken(nativeToken), 1));
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        router.multicall(data);

        // un existing action
        data[0] = abi.encodeCall(Ownable.owner, ());
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        router.multicall(data);

        vm.prank(wsWhale);
        nativeToken.withdraw(_S_BALANCE);

        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        vm.prank(wsWhale);
        payable(router).transfer(_S_BALANCE);
    }

    /// @dev only to test reentrancy
    function transfer(address, uint256) external {
        bytes[] memory data = new bytes[](1);
        // un existing action
        data[0] = abi.encodeCall(Ownable.owner, ());
        router.multicall(data);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_siloRouterV2_multicall_reentrancy
    function test_siloRouterV2_multicall_reentrancy() public {
        bytes[] memory data = new bytes[](1);

        // testing multicall with pause with a few actions calls
        data[0] = abi.encodeCall(SiloRouterV2Implementation.transfer, (IERC20(address(this)), address(0), 0));
        vm.expectRevert(abi.encodeWithSelector(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector));
        router.multicall(data);
    }
}
