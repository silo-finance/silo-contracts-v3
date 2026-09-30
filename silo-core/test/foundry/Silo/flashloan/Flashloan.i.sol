// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo, IERC3156FlashLender} from "silo-core/contracts/interfaces/ISilo.sol";
import {IERC3156FlashBorrower} from "silo-core/contracts/interfaces/IERC3156FlashBorrower.sol";
import {Silo} from "silo-core/contracts/Silo.sol";
import {Actions} from "silo-core/contracts/lib/Actions.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";
import {FlashLoanReceiverWithInvalidResponse} from "../../_mocks/FlashLoanReceiverWithInvalidResponse.sol";
import {Gas} from "../../gas/Gas.sol";

bytes32 constant FLASHLOAN_CALLBACK = keccak256("ERC3156FlashBorrower.onFlashLoan");

contract Hack1 {
    function bytesToUint256(bytes memory input) public pure returns (uint256 output) {
        assembly {
            output := mload(add(input, 32))
        }
    }

    function onFlashLoan(address _initiator, address, uint256, uint256, bytes calldata _data)
        external
        returns (bytes32)
    {
        uint256 option = bytesToUint256(_data);
        uint256 assets = 1e18;
        uint256 shares = 1e18;
        address receiver = address(this);

        option = option % 10;

        if (option == 0) {
            Silo(payable(msg.sender)).withdraw(assets, receiver, _initiator);
        } else if (option == 1) {
            Silo(payable(msg.sender)).redeem(shares, receiver, _initiator);
        } else if (option == 2) {
            Silo(payable(msg.sender)).withdraw(assets, receiver, _initiator, ISilo.CollateralType.Collateral);
        } else if (option == 3) {
            Silo(payable(msg.sender)).redeem(shares, receiver, _initiator, ISilo.CollateralType.Collateral);
        } else if (option == 4) {
            Silo(payable(msg.sender)).transitionCollateral(shares, _initiator, ISilo.CollateralType.Collateral);
        } else if (option == 5) {
            Silo(payable(msg.sender)).borrow(assets, receiver, _initiator);
        } else if (option == 6) {
            Silo(payable(msg.sender)).borrowShares(shares, receiver, _initiator);
        } else if (option == 7) {
            Silo(payable(msg.sender)).repay(assets, _initiator);
        } else if (option == 8) {
            Silo(payable(msg.sender)).repayShares(shares, _initiator);
        }

        return FLASHLOAN_CALLBACK;
    }
}

/*
    forge test -vv --ffi --mc FlashloanTest
*/
contract FlashloanTest is SiloLittleHelper, Test, Gas {
    ISiloConfig siloConfig;

    function setUp() public {
        siloConfig = _setUpLocalFixture();

        _depositForBorrow(8e18, address(1));

        _deposit(10e18, BORROWER);
        _deposit(1e18, BORROWER, ISilo.CollateralType.Protected);

        assertEq(token0.balanceOf(address(this)), 0);
        assertEq(token0.balanceOf(address(silo0)), 10e18 + 1e18);
        assertEq(token1.balanceOf(address(silo1)), 8e18);
    }

    /*
    forge test -vv --ffi --mt test_flashLoan_zeroAmount
    */
    function test_flashLoan_zeroAmount() public {
        vm.expectRevert(ISilo.ZeroAmount.selector);
        silo0.flashLoan(IERC3156FlashBorrower(address(this)), address(token0), 0, "");
    }

    /*
    forge test -vv --ffi --mt test_maxFlashLoan
    */
    function test_maxFlashLoan() public view {
        assertEq(silo0.maxFlashLoan(address(token1)), 0);
        assertEq(silo1.maxFlashLoan(address(token0)), 0);
        assertEq(silo0.maxFlashLoan(address(token0)), 10e18, "protected excluded");
        assertEq(silo1.maxFlashLoan(address(token1)), 8e18);
    }

    /*
    forge test -vv --ffi --mt test_flashFee
    */
    function test_flashFee() public {
        vm.expectRevert(ISilo.UnsupportedFlashloanToken.selector);
        silo0.flashFee(address(token1), 1e18);

        vm.expectRevert(ISilo.UnsupportedFlashloanToken.selector);
        silo1.flashFee(address(token0), 1e18);

        assertEq(silo0.flashFee(address(token0), 0), 0);
        assertEq(silo1.flashFee(address(token1), 0), 0);

        assertEq(silo0.flashFee(address(token0), 1e18), 0.01e18);
        assertEq(silo1.flashFee(address(token1), 1e18), 0.01e18);
    }

    /*
    forge test -vv --ffi --mt test_gas_flashLoan_FlashLoanNotPossible
    */
    function test_gas_flashLoan_FlashLoanNotPossible(bytes calldata _data) public {
        IERC3156FlashBorrower receiver = IERC3156FlashBorrower(makeAddr("IERC3156FlashBorrower"));
        uint256 amount = 10e18 + 1;

        vm.expectRevert(Actions.FlashLoanNotPossible.selector);
        silo0.flashLoan(receiver, address(token0), amount, _data);
    }

    /*
    forge test -vv --ffi --mt test_gas_flashLoan_pass
    */
    function test_gas_flashLoan_pass(bytes calldata _data) public {
        IERC3156FlashBorrower receiver = IERC3156FlashBorrower(makeAddr("IERC3156FlashBorrower"));
        uint256 amount = 1e18;
        uint256 fee = silo0.flashFee(address(token0), amount);

        token0.mint(address(receiver), fee);

        vm.prank(address(receiver));
        token0.approve(address(silo0), amount + fee);

        (uint256 daoAndDeployerRevenueBefore,,,,) = silo0.getSiloStorage();

        bytes memory data = abi.encodeWithSelector(
            IERC3156FlashBorrower.onFlashLoan.selector, address(this), address(token0), amount, fee, _data
        );

        vm.mockCall(address(receiver), data, abi.encode(FLASHLOAN_CALLBACK));
        vm.expectCall(address(receiver), data);

        vm.expectCall(address(token0), abi.encodeWithSelector(IERC20.transfer.selector, address(receiver), amount));
        vm.expectCall(
            address(token0),
            abi.encodeWithSelector(IERC20.transferFrom.selector, address(receiver), address(silo0), amount + fee)
        );

        _action(
            address(this),
            address(silo0),
            abi.encodeCall(IERC3156FlashLender.flashLoan, (receiver, address(token0), amount, _data)),
            "flashLoan gas",
            33900,
            3000
        );

        (uint256 daoAndDeployerRevenueAfter,,,,) = silo0.getSiloStorage();
        assertEq(daoAndDeployerRevenueAfter, daoAndDeployerRevenueBefore + fee);
    }

    /*
    forge test -vv --ffi --mt test_flashLoanInvalidResponse
    */
    function test_flashLoanInvalidResponse() public {
        bytes memory data;
        uint256 amount = 1e18;
        FlashLoanReceiverWithInvalidResponse receiver = new FlashLoanReceiverWithInvalidResponse();

        vm.expectRevert(ISilo.FlashloanFailed.selector);
        silo0.flashLoan(IERC3156FlashBorrower(address(receiver)), address(token0), amount, data);
    }
}
