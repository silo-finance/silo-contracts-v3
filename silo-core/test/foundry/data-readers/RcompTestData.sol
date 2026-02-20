// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IInterestRateModelV2} from "../../../contracts/interfaces/IInterestRateModelV2.sol";

contract RcompTestData is Test {
    // must be in alphabetic order
    struct Input {
        int112 Tcrit;
        uint256 currentTime;
        int112 integratorState;
        uint256 lastTransactionTime;
        uint256 lastUtilization;
        uint256 totalBorrowAmount;
        uint256 totalDeposits;
    }

    struct Constants {
        uint256 amountMax;
        int256 beta;
        int256 kcrit;
        int256 ki;
        int256 klin;
        int256 klow;
        int256 ucrit;
        int256 ulow;
        int256 uopt;
        uint256 xMax;
    }

    struct Expected {
        uint256 compoundInterest;
        uint256 didCap;
        uint256 didOverflow;
        int256 newIntegratorState;
        int256 newTcrit;
    }

    struct RcompData {
        Constants constants;
        Expected expected;
        uint256 id;
        Input input;
    }

    function _readDataFromJson() internal view returns (RcompData[] memory) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/silo-core/test/foundry/data/Rcomptest.json");
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory json = vm.readFile(path);

        return abi.decode(vm.parseJson(json, string(abi.encodePacked("."))), (RcompData[]));
    }

    function _print(RcompData memory _data) internal {
        emit log_named_uint("ID#", _data.id);

        emit log_string("INPUT");
        emit log_named_int("Tcrit", _data.input.Tcrit);
        emit log_named_uint("currentTime", _data.input.currentTime);
        emit log_named_int("integratorState", _data.input.integratorState);
        emit log_named_uint("lastTransactionTime", _data.input.lastTransactionTime);
        emit log_named_uint("lastUtilization", _data.input.lastUtilization);
        emit log_named_uint("totalBorrowAmount", _data.input.totalBorrowAmount);
        emit log_named_uint("totalDeposits", _data.input.totalDeposits);

        emit log_string("Constants");
        emit log_named_uint("amountMax", _data.constants.amountMax);
        emit log_named_int("beta", _data.constants.beta);
        emit log_named_int("kcrit", _data.constants.kcrit);
        emit log_named_int("ki", _data.constants.ki);
        emit log_named_int("klin", _data.constants.klin);
        emit log_named_int("klow", _data.constants.klow);
        emit log_named_int("ucrit", _data.constants.ucrit);
        emit log_named_int("ulow", _data.constants.ulow);
        emit log_named_int("uopt", _data.constants.uopt);
        emit log_named_uint("xMax", _data.constants.xMax);

        emit log_string("Expected");
        emit log_named_uint("compoundInterest", _data.expected.compoundInterest);
        emit log_named_uint("didCap", _data.expected.didCap);
        emit log_named_uint("didOverflow", _data.expected.didOverflow);
        emit log_named_int("newIntegratorState", _data.expected.newIntegratorState);
        emit log_named_int("newTcrit", _data.expected.newTcrit);
    }

    function _toConfigStruct(RcompData memory _data)
        internal
        pure
        returns (IInterestRateModelV2.Config memory cfg)
    {
        cfg.uopt = _data.constants.uopt;
        cfg.ucrit = _data.constants.ucrit;
        cfg.ulow = _data.constants.ulow;
        cfg.ki = _data.constants.ki;
        cfg.kcrit = _data.constants.kcrit;
        cfg.klow = _data.constants.klow;
        cfg.klin = _data.constants.klin;
        cfg.ri = _data.input.integratorState;
        cfg.Tcrit = _data.input.Tcrit;
        cfg.beta = _data.constants.beta;
    }
}
