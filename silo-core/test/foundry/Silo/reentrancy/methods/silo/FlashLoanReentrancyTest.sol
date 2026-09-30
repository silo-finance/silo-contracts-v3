// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {IERC3156FlashBorrower} from "silo-core/contracts/interfaces/IERC3156FlashBorrower.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {TestStateLib} from "../../TestState.sol";
import {MaliciousToken} from "../../MaliciousToken.sol";

contract FlashLoanReentrancyTest is MethodReentrancyTest {
    bytes32 public constant FLASHLOAN_CALLBACK = keccak256("ERC3156FlashBorrower.onFlashLoan");

    // For the flash loan tests
    function onFlashLoan(address, address _token, uint256 _amount, uint256 _fee, bytes calldata)
        external
        returns (bytes32)
    {
        IERC20(_token).approve(msg.sender, _amount + _fee);
        return FLASHLOAN_CALLBACK;
    }

    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert"));
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external {
        // no reentrancy test as flashLoan allows to reenter
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "flashLoan(address,address,uint256,bytes)";
    }

    function _ensureItWillNotRevert() internal {
        MaliciousToken token = MaliciousToken(TestStateLib.token0());
        ISilo silo = TestStateLib.silo0();
        uint256 amount = 100e18;
        uint256 flashLoanAmount = 1e18;
        bytes memory data;

        uint256 snapshotId = vm.snapshotState();

        TestStateLib.disableReentrancy();

        token.mint(address(silo), amount);
        token.mint(address(this), amount); // to cover the flash loan fee

        // no reentrancy test as flashLoan allows to reenter
        silo.flashLoan(IERC3156FlashBorrower(address(this)), address(token), flashLoanAmount, data);

        vm.revertToState(snapshotId);
    }
}
