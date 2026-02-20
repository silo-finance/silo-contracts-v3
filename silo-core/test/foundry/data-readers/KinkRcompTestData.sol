// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {IDynamicKinkModel} from "../../../contracts/interfaces/IDynamicKinkModel.sol";

contract KinkRcompTestData is Test {
    using SafeCast for int256;
    // must be in alphabetic order
    struct InputRcomp {
        int256 currentTime;
        int256 lastSlope;
        int256 lastTransactionTime;
        int256 lastUtilization;
        int256 totalBorrowAmount;
        int256 totalDeposits;
    }

    struct ConstantsRcomp {
        int256 alpha;
        int256 c1;
        int256 c2;
        int256 cminus;
        int256 cplus;
        int256 dmax;
        int256 kmax;
        int256 kmin;
        int256 rmin;
        int256 u1;
        int256 u2;
        int256 ucrit;
        int256 ulow;
    }

    struct ExpectedRcomp {
        int256 compoundInterest;
        int256 didOverflow;
        int256 newSlope;
    }

    struct RcompData {
        ConstantsRcomp constants;
        ExpectedRcomp expected;
        uint256 id;
        InputRcomp input;
    }

    function _readDataFromJsonRcomp() internal view returns (RcompData[] memory data) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/silo-core/test/foundry/data/KinkRcomptest.json");
        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory json = vm.readFile(path);

        data = abi.decode(vm.parseJson(json, string(abi.encodePacked(".tests"))), (RcompData[]));

        // for (uint i; i < data.length; i++) {
        //     _printRcomp(data[i]);
        // }
    }

    function _printRcomp(RcompData memory _data) internal {
        emit log_named_uint("\n------------------- ID#", _data.id);

        emit log_string("INPUT");
        emit log_named_int("currentTime", _data.input.currentTime);
        emit log_named_int("lastSlope", _data.input.lastSlope);
        emit log_named_int("lastTransactionTime", _data.input.lastTransactionTime);
        emit log_named_int("lastUtilization", _data.input.lastUtilization);
        emit log_named_int("totalBorrowAmount", _data.input.totalBorrowAmount);
        emit log_named_int("totalDeposits", _data.input.totalDeposits);

        emit log_string("Constants");
        emit log_named_int("alpha", _data.constants.alpha);
        emit log_named_int("c1", _data.constants.c1);
        emit log_named_int("c2", _data.constants.c2);
        emit log_named_int("cminus", _data.constants.cminus);
        emit log_named_int("cplus", _data.constants.cplus);
        emit log_named_int("dmax", _data.constants.dmax);
        emit log_named_int("kmax", _data.constants.kmax);
        emit log_named_int("kmin", _data.constants.kmin);
        emit log_named_int("rmin", _data.constants.rmin);
        emit log_named_int("u1", _data.constants.u1);
        emit log_named_int("u2", _data.constants.u2);
        emit log_named_int("ucrit", _data.constants.ucrit);
        emit log_named_int("ulow", _data.constants.ulow);

        emit log_string("Expected");
        emit log_named_int("compoundInterest", _data.expected.compoundInterest);
        emit log_named_int("didOverflow", _data.expected.didOverflow);
        emit log_named_int("newSlope", _data.expected.newSlope);
    }

    function _toSetupRcomp(RcompData memory _data)
        internal
        pure
        returns (IDynamicKinkModel.ModelState memory state, IDynamicKinkModel.Config memory c)
    {
        c.alpha = _data.constants.alpha;
        c.c1 = _data.constants.c1;
        c.c2 = _data.constants.c2;
        c.cminus = _data.constants.cminus;
        c.cplus = _data.constants.cplus;
        c.dmax = _data.constants.dmax;
        c.kmax = _data.constants.kmax.toInt96();
        c.kmin = _data.constants.kmin.toInt96();
        c.rmin = _data.constants.rmin;
        c.u1 = _data.constants.u1;
        c.u2 = _data.constants.u2;
        c.ucrit = _data.constants.ucrit;
        c.ulow = _data.constants.ulow;

        state.k = _data.input.lastSlope.toInt96();
    }
}
