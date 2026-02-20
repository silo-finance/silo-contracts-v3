// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Strings} from "openzeppelin5/utils/Strings.sol";
import {Clones} from "openzeppelin5/proxy/Clones.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IInterestRateModelV2} from "silo-core/contracts/interfaces/IInterestRateModelV2.sol";
import {IInterestRateModelV2Config} from "silo-core/contracts/interfaces/IInterestRateModelV2Config.sol";
import {InterestRateModelV2Config} from "silo-core/contracts/interestRateModel/InterestRateModelV2Config.sol";
import {InterestRateModelV2Impl} from "./InterestRateModelV2Impl.sol";
import {InterestRateModelConfigs} from "../_common/InterestRateModelConfigs.sol";
import {RcompTestData} from "../data-readers/RcompTestData.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

// forge test -vv --ffi --mc InterestRateModelV2RcompTest
contract InterestRateModelV2RcompTest is RcompTestData, InterestRateModelConfigs {
    using SafeCast for uint256;
    using SafeCast for int256;

    InterestRateModelV2Impl immutable INTEREST_RATE_MODEL;

    uint256 constant DP = 10 ** 18;
    uint256 constant BASIS_POINTS = 10000;

    constructor() {
        INTEREST_RATE_MODEL = new InterestRateModelV2Impl();
    }

    /*
    forge test -vv --ffi --mt test_IRM_getConfig_notConnected
    */
    function test_IRM_getConfig_notConnected() public {
        address silo = address(this);

        vm.expectRevert();
        INTEREST_RATE_MODEL.getConfig(silo);
    }

    function test_IRM_getConfig_zero() public {
        address silo = address(this);
        address irmConfigAddress = makeAddr("irmConfigAddress");

        INTEREST_RATE_MODEL.initialize(irmConfigAddress);

        IInterestRateModelV2.Config memory emptyConfig;

        bytes memory encodedData = abi.encodeWithSelector(IInterestRateModelV2Config.getConfig.selector);
        vm.mockCall(irmConfigAddress, encodedData, abi.encode(emptyConfig));
        vm.expectCall(irmConfigAddress, encodedData);

        IInterestRateModelV2.Config memory fullConfig = INTEREST_RATE_MODEL.getConfig(silo);

        assertEq(keccak256(abi.encode(emptyConfig)), keccak256(abi.encode(fullConfig)), "empty config");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_IRM_getConfig_withData
    */
    function test_IRM_getConfig_withData() public {
        address silo = address(this);
        address irmConfigAddress = makeAddr("irmConfigAddress");

        INTEREST_RATE_MODEL.initialize(irmConfigAddress);

        bytes memory encodedData = abi.encodeWithSelector(IInterestRateModelV2Config.getConfig.selector);
        vm.mockCall(irmConfigAddress, encodedData, abi.encode(_defaultConfig()));
        vm.expectCall(irmConfigAddress, encodedData);

        IInterestRateModelV2.Config memory fullConfig = INTEREST_RATE_MODEL.getConfig(silo);

        assertEq(keccak256(abi.encode(_defaultConfig())), keccak256(abi.encode(fullConfig)), "config match");

        assertGt(fullConfig.beta, 0, "beta");
        assertGt(fullConfig.kcrit, 0, "kcrit");
        assertGt(fullConfig.ki, 0, "ki");
        assertGt(fullConfig.klin, 0, "klin");
        assertGt(fullConfig.klow, 0, "klow");
        assertGt(fullConfig.ucrit, 0, "ucrit");
        assertGt(fullConfig.ulow, 0, "ulow");
        assertGt(fullConfig.uopt, 0, "uopt");
        assertEq(fullConfig.ri, 10, "ri");
        assertEq(fullConfig.Tcrit, 1, "Tcrit");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_IRM_getSetup
    */
    function test_IRM_getSetup() public {
        address silo = address(this);
        address irmConfigAddress = makeAddr("irmConfigAddress");

        INTEREST_RATE_MODEL.initialize(irmConfigAddress);

        bytes memory encodedData = abi.encodeWithSelector(IInterestRateModelV2Config.getConfig.selector);
        vm.mockCall(irmConfigAddress, encodedData, abi.encode(_defaultConfig()));
        vm.expectCall(irmConfigAddress, encodedData);

        (int112 ri, int112 Tcrit, bool initialized) = INTEREST_RATE_MODEL.getSetup(silo);
        assertFalse(initialized, "not initialized");
        assertEq(ri, 0, "ri not initialized");
        assertEq(Tcrit, 0, "Tcrit not initialized");

        (ri, Tcrit, initialized) = INTEREST_RATE_MODEL.getSetup(silo);

        assertFalse(initialized, "not initialized yet");
        assertEq(ri, 0, "ri not initialized yet");
        assertEq(Tcrit, 0, "Tcrit not initialized yet");

        vm.prank(silo);
        INTEREST_RATE_MODEL.getCompoundInterestRateAndUpdate(0, 0, block.timestamp);

        (ri, Tcrit, initialized) = INTEREST_RATE_MODEL.getSetup(silo);

        assertTrue(initialized, "initialized");
        assertEq(ri, 10, "ri initialized");
        assertEq(Tcrit, 1, "Tcrit initialized");
    }

    function test_IRM_RcompData_Mock() public {
        RcompData[] memory data = _readDataFromJson();

        uint256 totalDepositsOverflows;
        uint256 totalBorrowAmountOverflows;

        for (uint256 i; i < data.length; i++) {
            RcompData memory testCase = data[i];

            IInterestRateModelV2.Config memory cfg = _toConfigStruct(testCase);
            address silo = address(i.toUint160());
            InterestRateModelV2Impl IRMv2Impl = _createIRM(silo, testCase);

            (uint256 rcomp, int256 ri, int256 Tcrit, bool overflow) = IRMv2Impl
                .calculateCompoundInterestRateWithOverflowDetection(
                cfg,
                testCase.input.totalDeposits,
                testCase.input.totalBorrowAmount,
                testCase.input.lastTransactionTime,
                testCase.input.currentTime
            );

            assertEq(overflow, testCase.expected.didOverflow == 1, _concatMsg(i, "didOverflow"));

            if (testCase.expected.compoundInterest == 0) {
                assertEq(rcomp, testCase.expected.compoundInterest, _concatMsg(i, "compoundInterest"));
            } else {
                uint256 diff = _diff(rcomp, testCase.expected.compoundInterest);

                // allow maximum of 0.25% (25bps) deviation between high precision test results and smart contracts output
                assertLe(diff, 25, _concatMsg(i, "[rcomp] allow maximum of 0.25% (25bps) "));
            }

            if (testCase.expected.newIntegratorState == 0) {
                assertEq(ri, testCase.expected.newIntegratorState, _concatMsg(i, "newIntegratorState"));
            } else {
                uint256 diff = _diff(ri, testCase.expected.newIntegratorState);

                // allow maximum of 0.25% (25bps) deviation between high precision test results and smart contracts output
                assertLe(diff, 25, _concatMsg(i, "[ri] allow maximum of 0.25% (25bps) "));
            }

            if (testCase.expected.newTcrit == 0) {
                assertEq(Tcrit, testCase.expected.newTcrit, _concatMsg(i, "newTcrit"));
            } else {
                uint256 diff = _diff(Tcrit, testCase.expected.newTcrit);

                // allow maximum of 0.25% (25bps) deviation between high precision test results and smart contracts output
                assertLe(diff, 25, _concatMsg(i, "[newTcrit] allow maximum of 0.25% (25bps) "));
            }

            ISilo.UtilizationData memory utilizationData = ISilo.UtilizationData(
                testCase.input.totalDeposits,
                testCase.input.totalBorrowAmount,
                uint64(testCase.input.lastTransactionTime)
            );

            if (testCase.input.totalDeposits != utilizationData.collateralAssets) {
                totalDepositsOverflows++;
                continue;
            }
            if (testCase.input.totalBorrowAmount != utilizationData.debtAssets) {
                totalBorrowAmountOverflows++;
                continue;
            }

            IRMv2Impl.mockSetup(silo, testCase.input.integratorState, testCase.input.Tcrit);

            bytes memory encodedData = abi.encodeWithSelector(ISilo.utilizationData.selector);
            vm.mockCall(silo, encodedData, abi.encode(utilizationData));
            vm.expectCall(silo, encodedData);

            uint256 compoundInterestRate = IRMv2Impl.getCompoundInterestRate(silo, testCase.input.currentTime);
            assertEq(compoundInterestRate, rcomp, _concatMsg(i, "getCompoundInterestRate()"));
        }

        emit log_named_uint("totalBorrowAmountOverflows", totalBorrowAmountOverflows);
        emit log_named_uint("totalDepositsOverflows", totalDepositsOverflows);
        emit log_named_uint("total cases", data.length);
    }

    // forge test -vv --ffi --mt test_IRM_RcompData_Update
    function test_IRM_RcompData_Update() public {
        RcompData[] memory data = _readDataFromJson();

        for (uint256 i; i < data.length; i++) {
            RcompData memory testCase = data[i];

            IInterestRateModelV2.Config memory cfg = _toConfigStruct(testCase);
            address silo = address(i.toUint160());
            InterestRateModelV2Impl IRMv2Impl = _createIRM(silo, testCase);

            (, int256 ri, int256 Tcrit,) = IRMv2Impl.calculateCompoundInterestRateWithOverflowDetection(
                cfg,
                testCase.input.totalDeposits,
                testCase.input.totalBorrowAmount,
                testCase.input.lastTransactionTime,
                testCase.input.currentTime
            );

            IRMv2Impl.mockSetup(silo, testCase.input.integratorState, testCase.input.Tcrit);

            vm.warp(testCase.input.currentTime);
            vm.prank(silo);
            IRMv2Impl.getCompoundInterestRateAndUpdate(
                testCase.input.totalDeposits, testCase.input.totalBorrowAmount, testCase.input.lastTransactionTime
            );

            (int112 storageRi, int112 storageTcrit, bool initialized) = IRMv2Impl.getSetup(silo);

            assertTrue(initialized);
            assertEq(storageRi, ri, _concatMsg(i, "storageRi"));
            assertEq(storageTcrit, Tcrit, _concatMsg(i, "storageTcrit"));
        }
    }

    function _createIRM(address _silo, RcompData memory _testCase)
        internal
        returns (InterestRateModelV2Impl IRMv2Impl)
    {
        IRMv2Impl = InterestRateModelV2Impl(Clones.clone(address(INTEREST_RATE_MODEL)));

        IInterestRateModelV2Config configAddress = new InterestRateModelV2Config(_toConfigStruct(_testCase));

        vm.prank(_silo);
        IRMv2Impl.initialize(address(configAddress));
    }

    function _diff(int256 _a, int256 _b) internal pure returns (uint256 diff) {
        int256 deviation = (_a * BASIS_POINTS.toInt256()) / _b;
        uint256 positiveDeviation = uint256(deviation < 0 ? -deviation : deviation);

        diff =
            positiveDeviation > BASIS_POINTS ? positiveDeviation - BASIS_POINTS : BASIS_POINTS - positiveDeviation;
    }

    function _diff(uint256 _a, uint256 _b) internal pure returns (uint256 diff) {
        uint256 positiveDeviation = (_a * BASIS_POINTS) / _b;
        diff =
            positiveDeviation > BASIS_POINTS ? positiveDeviation - BASIS_POINTS : BASIS_POINTS - positiveDeviation;
    }

    function _concatMsg(uint256 _i, string memory _msg) internal pure returns (string memory) {
        return string.concat("[", Strings.toString(_i), "] ", _msg);
    }
}
