// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {console2} from "forge-std/console2.sol";

import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

import {
    DynamicKinkModel, IDynamicKinkModel
} from "../../../../contracts/interestRateModel/kink/DynamicKinkModel.sol";
import {DynamicKinkModelFactory} from "../../../../contracts/interestRateModel/kink/DynamicKinkModelFactory.sol";

import {KinkRcompTestData} from "../../data-readers/KinkRcompTestData.sol";
import {KinkRcurTestData} from "../../data-readers/KinkRcurTestData.sol";

import {ISilo} from "../../../../contracts/interfaces/ISilo.sol";
import {DynamicKinkModelMock} from "./DynamicKinkModelMock.sol";

/* 
FOUNDRY_PROFILE=core_test forge test -vv --mc DynamicKinkModelJsonTest
*/
contract DynamicKinkModelJsonTest is KinkRcompTestData, KinkRcurTestData {
    using SafeCast for uint256;
    using SafeCast for int256;
    DynamicKinkModelFactory immutable FACTORY = new DynamicKinkModelFactory(new DynamicKinkModelMock());

    DynamicKinkModelMock immutable IRM;

    int256 constant _DP = 10 ** 18;
    uint32 constant _TIMELOCK = 0 days;
    int96 immutable _RCOMP_CAP_PER_SECOND;

    uint256 acceptableDiffPercentRcur = 6e9;
    mapping(uint256 id => uint256 aloowedDiffPercent) private _rcompDiffPercent;

    ISilo.UtilizationData public utilizationData;

    constructor() {
        DynamicKinkModel tmp = new DynamicKinkModel();

        _RCOMP_CAP_PER_SECOND = int96(tmp.RCOMP_CAP_PER_SECOND());

        IDynamicKinkModel.Config memory cfg;

        IDynamicKinkModel.ImmutableArgs memory immutableArgs =
            IDynamicKinkModel.ImmutableArgs({timelock: _TIMELOCK, rcompCap: int96(tmp.RCUR_CAP())});

        IRM = DynamicKinkModelMock(
            address(FACTORY.create(cfg, immutableArgs, address(this), address(this), bytes32(0)))
        );

        // 1e18 is 100%
        _rcompDiffPercent[5] = 69700005108;
        _rcompDiffPercent[7] = 25245061486;
        _rcompDiffPercent[31] = 20725920356;
        _rcompDiffPercent[33] = 29389012176;
        _rcompDiffPercent[40] = 13321877417;
        _rcompDiffPercent[66] = 43490728497;
        _rcompDiffPercent[79] = 81126849847;
        _rcompDiffPercent[111] = 11100763970;
        _rcompDiffPercent[127] = 198260773835;
        _rcompDiffPercent[131] = 46111172734;
        _rcompDiffPercent[152] = 16508187279;
        _rcompDiffPercent[182] = 10764316805;
        _rcompDiffPercent[189] = 136561505832;
        _rcompDiffPercent[211] = 11894349980;
        _rcompDiffPercent[221] = 15758917106;
        _rcompDiffPercent[289] = 14419032745;
        _rcompDiffPercent[291] = 15911114231;
    }

    /* 
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_kink_verifyConfig_empty
    */
    function test_kink_verifyConfig_empty() public view {
        IDynamicKinkModel.Config memory c;

        IRM.verifyConfig(c);
    }

    /* 
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_kink_rcur_json
    */
    function test_kink_rcur_json() public view {
        RcurData[] memory data = _readDataFromJsonRcur();

        for (uint256 i = 0; i < data.length; i++) {
            (IDynamicKinkModel.ModelState memory state, IDynamicKinkModel.Config memory c) = _toSetupRcur(data[i]);
            // _printRcur(data[i]);

            try IRM.currentInterestRate(
                c,
                state,
                data[i].input.lastTransactionTime,
                data[i].input.currentTime,
                data[i].input.lastUtilization,
                data[i].input.totalBorrowAmount
            ) returns (int256 rcur) {
                if (data[i].input.totalBorrowAmount == 0) {
                    assertEq(rcur, 0, "when no debt we always return early");
                    continue;
                }

                _assertCloseTo(
                    rcur,
                    data[i].expected.currentAnnualInterest,
                    data[i].id,
                    "rcur is not close to expected value",
                    acceptableDiffPercentRcur
                );
            } catch {
                revert(
                    string.concat(
                        "we should not revert in this tests, but case with ID ", vm.toString(data[i].id), " did"
                    )
                );
            }
        }
    }

    /* 
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_currentInterestRate_json -vv
    */
    function test_kink_currentInterestRate_json() public {
        RcurData[] memory data = _readDataFromJsonRcur();

        address silo = address(this);

        for (uint256 i; i < data.length; i++) {
            (IDynamicKinkModel.ModelState memory state, IDynamicKinkModel.Config memory c) = _toSetupRcur(data[i]);

            vm.warp(uint256(data[i].input.currentTime));
            _setUtilizationData(data[i]);
            IRM.mockState(c, state.k);

            // _printRcur(data[i]);

            uint256 rcur = IRM.getCurrentInterestRate(silo, uint256(data[i].input.currentTime));

            if (data[i].input.totalBorrowAmount == 0) {
                assertEq(rcur, 0, "[getCurrentInterestRate] when no debt we always return early");
                continue;
            }

            _assertCloseTo(
                rcur.toInt256(),
                data[i].expected.currentAnnualInterest,
                data[i].id,
                "[getCurrentInterestRate] rcur is not close to expected value",
                acceptableDiffPercentRcur
            );
        }
    }

    /* 
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_kink_rcomp_json
    */
    function test_kink_rcomp_json() public view {
        RcompData[] memory data = _readDataFromJsonRcomp();

        for (uint256 i; i < data.length; i++) {
            (IDynamicKinkModel.ModelState memory state, IDynamicKinkModel.Config memory c) = _toSetupRcomp(data[i]);
            // _printRcomp(data[i]);

            try IRM.compoundInterestRate(
                c,
                state,
                int256(_RCOMP_CAP_PER_SECOND),
                data[i].input.lastTransactionTime,
                data[i].input.currentTime,
                data[i].input.lastUtilization,
                data[i].input.totalBorrowAmount
            ) returns (int256 rcomp, int256 k) {
                if (data[i].input.totalBorrowAmount == 0) {
                    assertEq(rcomp, 0, "[compoundInterestRate] when no debt we always return early");
                    continue;
                }

                uint256 acceptableDiffPercent = _getAcceptableDiffPercent(data[i].id, _rcompDiffPercent);

                console2.log("rcomp expected", data[i].expected.compoundInterest);
                console2.log("     rcomp got", rcomp);

                console2.log("k expected", data[i].expected.newSlope);
                console2.log("     k got", k);

                _assertCloseTo(
                    rcomp,
                    data[i].expected.compoundInterest,
                    data[i].id,
                    "rcomp is not close to expected value",
                    acceptableDiffPercent
                );

                _assertCloseTo(k, data[i].expected.newSlope, data[i].id, "k is not close to expected value");

                assertEq(data[i].expected.didOverflow, 0, "didOverflow expect overflow");
            } catch {
                assertEq(
                    data[i].expected.didOverflow,
                    1,
                    string.concat(
                        "we should not revert in this tests, but case with ID ", vm.toString(data[i].id), " did"
                    )
                );
            }
        }
    }

    /* 
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_getCompoundInterestRate_json -vv 
    */
    function test_kink_getCompoundInterestRate_json() public {
        RcompData[] memory data = _readDataFromJsonRcomp();

        address silo = address(this);

        for (uint256 i; i < data.length; i++) {
            (IDynamicKinkModel.ModelState memory state, IDynamicKinkModel.Config memory c) = _toSetupRcomp(data[i]);

            vm.warp(uint256(data[i].input.currentTime));
            _setUtilizationData(data[i]);
            IRM.mockState(c, state.k);

            // _printRcomp(data[i]);

            uint256 rcomp = IRM.getCompoundInterestRate(silo, uint256(data[i].input.currentTime));

            if (data[i].input.totalBorrowAmount == 0) {
                assertEq(rcomp, 0, "[getCompoundInterestRate] when no debt we always return early");
                continue;
            }

            uint256 acceptableDiffPercent = _getAcceptableDiffPercent(data[i].id, _rcompDiffPercent);

            _assertCloseTo(
                rcomp.toInt256(),
                data[i].expected.compoundInterest,
                data[i].id,
                "[getCompoundInterestRate] rcomp is not close to expected value",
                acceptableDiffPercent
            );
        }
    }

    function _assertCloseTo(int256 _got, int256 _expected, uint256 _testId, string memory _msg) internal pure {
        _assertCloseTo(_got, _expected, _testId, _msg, 0);
    }

    function _assertCloseTo(
        int256 _got,
        int256 _expected,
        uint256 _testId,
        string memory _msg,
        uint256 _acceptableDiffPercent
    ) internal pure {
        if (_got == _expected) {
            return; // no need to check further
        }

        int256 diffPercent = _expected == 0 ? _DP : (_got - _expected) * _DP / _expected; // 18 decimal points

        if (diffPercent < 0) {
            diffPercent = -diffPercent; // absolute value
        }

        bool satisfied = diffPercent <= _acceptableDiffPercent.toInt256();

        string memory errorMessage = string.concat(
            "ID ",
            vm.toString(_testId),
            ": ",
            _msg,
            " relative error: ",
            vm.toString(diffPercent),
            " [%] larger than acceptable diff: ",
            vm.toString(_acceptableDiffPercent),
            " got: ",
            vm.toString(_got),
            " expected: ",
            vm.toString(_expected)
        );

        if (!satisfied) {
            console2.log("     got", _got);
            console2.log("expected", _expected);
            console2.log("           diff %", diffPercent);
            console2.log("acceptable diff %", _acceptableDiffPercent);
        }

        assertTrue(satisfied, errorMessage);
    }

    function _setUtilizationData(RcompData memory _data) internal {
        utilizationData = ISilo.UtilizationData({
            collateralAssets: _data.input.totalDeposits.toUint256(),
            debtAssets: _data.input.totalBorrowAmount.toUint256(),
            interestRateTimestamp: _data.input.lastTransactionTime.toUint256().toUint64()
        });
    }

    function _setUtilizationData(RcurData memory _data) internal {
        utilizationData = ISilo.UtilizationData({
            collateralAssets: _data.input.totalDeposits.toUint256(),
            debtAssets: _data.input.totalBorrowAmount.toUint256(),
            interestRateTimestamp: _data.input.lastTransactionTime.toUint256().toUint64()
        });
    }

    function _getAcceptableDiffPercent(uint256 _id, mapping(uint256 => uint256) storage _diffs)
        internal
        view
        returns (uint256 acceptableDiffPercent)
    {
        acceptableDiffPercent = _diffs[_id];

        if (acceptableDiffPercent == 0) {
            acceptableDiffPercent = 1e10; // default value for tiny differences
        }
    }
}
