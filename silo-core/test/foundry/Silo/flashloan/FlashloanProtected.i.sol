// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IERC3156FlashBorrower} from "silo-core/contracts/interfaces/IERC3156FlashBorrower.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

bytes32 constant FLASHLOAN_CALLBACK = keccak256("ERC3156FlashBorrower.onFlashLoan");

address constant USER = address(0x12345);
address constant BORROWER = address(0xabcde);

contract HackProtected is Test {
    function bytesToUint256(bytes memory input) public pure returns (uint256 output) {
        assembly {
            output := mload(add(input, 32))
        }
    }

    function onFlashLoan(address, address _token, uint256, uint256, bytes calldata) external returns (bytes32) {
        ISilo silo = ISilo(msg.sender);

        assertGe(IERC20(_token).balanceOf(address(silo)), 1e18, "protected deposit left in silo");

        assertEq(silo.maxWithdraw(address(this)), 1e18 - 1, "contract must have assets to withdraw (-1 for underestimation)");

        silo.withdraw(1, address(this), address(this));

        return FLASHLOAN_CALLBACK;
    }
}

/*
    forge test -vv --ffi --mc FlashloanProtectedTest
*/
contract FlashloanProtectedTest is SiloLittleHelper, Test {
    function setUp() public {
        _setUpLocalFixture();

        _deposit(1e18, USER);
        _deposit(1e18, USER, ISilo.CollateralType.Protected);

        token0.setOnDemand(true);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_flashLoanProtected
    */
    function test_flashLoanProtected() public {
        HackProtected receiver = new HackProtected();

        _deposit(1e18, address(receiver));

        uint256 maxFlashloan = silo0.maxFlashLoan(address(token0));
        emit log_named_decimal_uint("maxFlashloan", maxFlashloan, 18);

        vm.expectRevert(ISilo.ProtectedProtection.selector);
        silo0.flashLoan(IERC3156FlashBorrower(address(receiver)), address(token0), maxFlashloan, "");

        // contr example, this flashloan should pass, because we flashloan 1 wei less
        silo0.flashLoan(IERC3156FlashBorrower(address(receiver)), address(token0), maxFlashloan - 1, "");

        assertEq(
            token0.balanceOf(address(silo0)),
            uint256(1e18) * 3 + uint256(2e18 - 1) * 0.01e18 / 1e18 - 1,
            "protected deposit is in silo, balance is: 3 deposits + flashloan fee - 1wei withdraw"
        );
    }
}
