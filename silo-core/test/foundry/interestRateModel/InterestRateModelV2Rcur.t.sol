// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Strings} from "openzeppelin5/utils/Strings.sol";
import {Clones} from "openzeppelin5/proxy/Clones.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {InterestRateModelV2Impl} from "./InterestRateModelV2Impl.sol";
import {InterestRateModelConfigs} from "../_common/InterestRateModelConfigs.sol";
import {RcurTestData} from "../data-readers/RcurTestData.sol";
import {IInterestRateModelV2} from "silo-core/contracts/interfaces/IInterestRateModelV2.sol";
import {IInterestRateModelV2Config} from "silo-core/contracts/interfaces/IInterestRateModelV2Config.sol";
import {InterestRateModelV2Config} from "silo-core/contracts/interestRateModel/InterestRateModelV2Config.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

// forge test -vv --mc InterestRateModelV2RcurTest
contract InterestRateModelV2RcurTest is RcurTestData, InterestRateModelConfigs {
    using SafeCast for uint256;

    InterestRateModelV2Impl immutable INTEREST_RATE_MODEL;

    uint256 constant DP = 10 ** 18;
    uint256 constant BASIS_POINTS = 10000;

    constructor() {
        INTEREST_RATE_MODEL = new InterestRateModelV2Impl();
    }

    /*
    forge test -vv --mt test_IRM_RcurData
    */
    function test_IRM_RcurData() public {
        RcurData[] memory data = _readDataFromJson();

        for (uint256 i; i < data.length; i++) {
            RcurData memory testCase = data[i];

            IInterestRateModelV2.Config memory cfg = _toConfigStruct(testCase);
            address silo = address(i.toUint160());
            InterestRateModelV2Impl IRMv2Impl = _createIRM(silo, testCase);

            uint256 rcur = IRMv2Impl.calculateCurrentInterestRate(
                cfg,
                testCase.input.totalDeposits,
                testCase.input.totalBorrowAmount,
                testCase.input.lastTransactionTime,
                testCase.input.currentTime
            );

            if (testCase.expected.currentAnnualInterest == 0) {
                assertEq(rcur, testCase.expected.currentAnnualInterest, _concatMsg(i, "currentAnnualInterest"));
            } else {
                uint256 deviation = (rcur * BASIS_POINTS) / testCase.expected.currentAnnualInterest;
                uint256 diff = deviation > BASIS_POINTS ? deviation - BASIS_POINTS : BASIS_POINTS - deviation;

                // allow maximum of 0.01% (1bps) deviation between high precision test results and smart contracts output
                assertLe(diff, 1, _concatMsg(i, "allow maximum of 0.01% (1bps) deviation"));
            }

            ISilo.UtilizationData memory utilizationData = ISilo.UtilizationData(
                testCase.input.totalDeposits,
                testCase.input.totalBorrowAmount,
                uint64(testCase.input.lastTransactionTime)
            );

            IRMv2Impl.mockSetup(silo, testCase.input.integratorState, testCase.input.Tcrit);

            bytes memory encodedData = abi.encodeWithSelector(ISilo.utilizationData.selector);
            vm.mockCall(silo, encodedData, abi.encode(utilizationData));
            vm.expectCall(silo, encodedData);

            uint256 mockedRcur = IRMv2Impl.getCurrentInterestRate(silo, testCase.input.currentTime);
            assertEq(mockedRcur, rcur, _concatMsg(i, "getCurrentInterestRate()"));

            bool overflow = IRMv2Impl.overflowDetected(silo, testCase.input.currentTime);
            assertEq(
                overflow,
                testCase.expected.didOverflow == 1,
                _concatMsg(i, "expect overflowDetected() = expected.didOverflow")
            );
        }
    }

    function _createIRM(address _silo, RcurData memory _testCase)
        internal
        returns (InterestRateModelV2Impl IRMv2Impl)
    {
        IRMv2Impl = InterestRateModelV2Impl(Clones.clone(address(INTEREST_RATE_MODEL)));

        IInterestRateModelV2Config configAddress = new InterestRateModelV2Config(_toConfigStruct(_testCase));

        vm.prank(_silo);
        IRMv2Impl.initialize(address(configAddress));
    }

    function _concatMsg(uint256 _i, string memory _msg) internal pure returns (string memory) {
        return string.concat("[", Strings.toString(_i), "] ", _msg);
    }
}
