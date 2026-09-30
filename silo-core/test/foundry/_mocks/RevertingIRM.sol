// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IInterestRateModel} from "silo-core/contracts/interfaces/IInterestRateModel.sol";
import {Overflows} from "silo-core/test/foundry/Silo/overflow/TryCatchTest.t.sol";

contract RevertingIRM is IInterestRateModel, Overflows {
    enum RevertReasons {
        StandardRevert,
        ZeroDiv,
        Underflow,
        Overflow,
        CustomError
    }

    RevertReasons public revertReason;

    constructor(RevertReasons _revertReason) {
        revertReason = _revertReason;
    }

    function initialize(address _irmConfig) external {}

    function getCompoundInterestRateAndUpdate(uint256, uint256, uint256) external view returns (uint256) {
        _revert();
        return 0;
    }

    function getCompoundInterestRate(address, uint256) external view returns (uint256) {
        _revert();
        return 0;
    }

    function getCurrentInterestRate(address, uint256) external view returns (uint256) {
        _revert();
        return 0;
    }

    function decimals() external pure returns (uint256) {
        return 18;
    }

    function _revert() internal view {
        if (revertReason == RevertReasons.ZeroDiv) {
            zeroDiv();
        } else if (revertReason == RevertReasons.Underflow) {
            underflow();
        } else if (revertReason == RevertReasons.Overflow) {
            overflow();
        } else if (revertReason == RevertReasons.CustomError) {
            customError();
        } else {
            standardRevert();
        }
    }
}
