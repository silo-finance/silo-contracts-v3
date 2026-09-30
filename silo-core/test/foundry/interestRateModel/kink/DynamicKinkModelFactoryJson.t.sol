// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {console2} from "forge-std/console2.sol";

import {IDynamicKinkModel} from "../../../../contracts/interestRateModel/kink/DynamicKinkModel.sol";

import {KinkDefaultConfigTestData} from "../../data-readers/KinkDefaultConfigTestData.sol";

import {KinkCommon} from "./KinkCommon.sol";

/* 
FOUNDRY_PROFILE=core_test forge test -vv --mc DynamicKinkModelFactoryJsonTest
*/
contract DynamicKinkModelFactoryJsonTest is KinkDefaultConfigTestData, KinkCommon {
    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_generateConfig_json -vv
    */
    function test_kink_generateConfig_json() public view {
        UserInputData[] memory data = _readUserInputDataFromJson();

        for (uint256 i; i < data.length; i++) {
            try FACTORY.generateConfig(data[i].input) returns (IDynamicKinkModel.Config memory c) {
                _compareConfigs(data[i].id, data[i].config, c);

                assertEq(
                    c.ulow, data[i].config.ulow, _makeMsg("ulow mismatch", data[i].id, c.ulow, data[i].config.ulow)
                );
                assertEq(c.u1, data[i].config.u1, _makeMsg("u1 mismatch", data[i].id, c.u1, data[i].config.u1));
                assertEq(c.u2, data[i].config.u2, _makeMsg("u2 mismatch", data[i].id, c.u2, data[i].config.u2));
                assertEq(
                    c.ucrit,
                    data[i].config.ucrit,
                    _makeMsg("ucrit mismatch", data[i].id, c.ucrit, data[i].config.ucrit)
                );
                assertEq(
                    c.rmin, data[i].config.rmin, _makeMsg("rmin mismatch", data[i].id, c.rmin, data[i].config.rmin)
                );
                assertEq(
                    c.kmin, data[i].config.kmin, _makeMsg("kmin mismatch", data[i].id, c.kmin, data[i].config.kmin)
                );
                assertEq(
                    c.kmax, data[i].config.kmax, _makeMsg("kmax mismatch", data[i].id, c.kmax, data[i].config.kmax)
                );

                _assertCloseTo(c.alpha, data[i].config.alpha, data[i].id, "alpha mismatch ID ", 33525423);

                _assertCloseTo(
                    c.cminus,
                    data[i].config.cminus,
                    data[i].id,
                    "cminus mismatch",
                    _acceptableDiff({
                        _value: data[i].config.cminus,
                        _1e3Limit: 0,
                        _1e6Limit: 0,
                        _1e9Limit: 0,
                        _limit: 0
                    })
                );

                _assertCloseTo(
                    c.cplus,
                    data[i].config.cplus,
                    data[i].id,
                    "cplus mismatch",
                    _acceptableDiff({
                        _value: data[i].config.cplus,
                        _1e3Limit: 0,
                        _1e6Limit: 0,
                        _1e9Limit: 0.000000083682925729e18,
                        _limit: 0.000000000008940065e18
                    })
                );

                assertEq(c.c1, data[i].config.c1, _makeMsg("c1 mismatch", data[i].id, c.c1, data[i].config.c1));
                assertEq(c.c2, data[i].config.c2, _makeMsg("c2 mismatch", data[i].id, c.c2, data[i].config.c2));
                assertEq(
                    c.dmax, data[i].config.dmax, _makeMsg("dmax mismatch", data[i].id, c.dmax, data[i].config.dmax)
                );
            } catch {
                if (data[i].success) {
                    revert(
                        string.concat(
                            "we should not revert in this tests, but case with ID ", vm.toString(data[i].id), " did"
                        )
                    );
                }
            }
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
        int256 _acceptableDiffPercent
    ) internal pure {
        if (_got == _expected) {
            return; // no need to check further
        }

        if (_got == 0 && _expected < 3) {
            return;
        }

        int256 diffPercent = _expected == 0 ? _DP : (_got - _expected) * _DP / _expected; // 18 decimal points

        if (diffPercent < 0) {
            diffPercent = -diffPercent; // absolute value
        }

        bool satisfied = diffPercent <= _acceptableDiffPercent;

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

    function _compareConfigs(
        uint256 _id,
        IDynamicKinkModel.Config memory _config1,
        IDynamicKinkModel.Config memory _config2
    ) internal pure {
        console2.log("--------------------------------");
        console2.log("config1 vs config2 for ID#", _id);
        console2.log("ulow #1", _config1.ulow);
        console2.log("ulow #2", _config2.ulow);
        console2.log("ulow match?", _config1.ulow == _config2.ulow ? "yes" : " >>> NO <<<");
        console2.log("u1 #1", _config1.u1);
        console2.log("u1 #2", _config2.u1);
        console2.log("u1 match?", _config1.u1 == _config2.u1 ? "yes" : " >>> NO <<<");
        console2.log("u2 #1", _config1.u2);
        console2.log("u2 #2", _config2.u2);
        console2.log("u2 match?", _config1.u2 == _config2.u2 ? "yes" : " >>> NO <<<");
        console2.log("ucrit #1", _config1.ucrit);
        console2.log("ucrit #2", _config2.ucrit);
        console2.log("ucrit match?", _config1.ucrit == _config2.ucrit ? "yes" : " >>> NO <<<");
        console2.log("rmin #1", _config1.rmin);
        console2.log("rmin #2", _config2.rmin);
        console2.log("rmin match?", _config1.rmin == _config2.rmin ? "yes" : " >>> NO <<<");
        console2.log("kmin #1", _config1.kmin);
        console2.log("kmin #2", _config2.kmin);
        console2.log("kmin match?", _config1.kmin == _config2.kmin ? "yes" : " >>> NO <<<");
        console2.log("kmax #1", _config1.kmax);
        console2.log("kmax #2", _config2.kmax);
        console2.log("kmax match?", _config1.kmax == _config2.kmax ? "yes" : " >>> NO <<<");
        console2.log("alpha #1", _config1.alpha);
        console2.log("alpha #2", _config2.alpha);
        console2.log("alpha match?", _config1.alpha == _config2.alpha ? "yes" : " >>> NO <<<");
        console2.log("cminus #1", _config1.cminus);
        console2.log("cminus #2", _config2.cminus);
        console2.log("cminus match?", _config1.cminus == _config2.cminus ? "yes" : " >>> NO <<<");
        console2.log("cplus #1", _config1.cplus);
        console2.log("cplus #2", _config2.cplus);
        console2.log("cplus match?", _config1.cplus == _config2.cplus ? "yes" : " >>> NO <<<");
        console2.log("c1 #1", _config1.c1);
        console2.log("c1 #2", _config2.c1);
        console2.log("c1 match?", _config1.c1 == _config2.c1 ? "yes" : " >>> NO <<<");
        console2.log("c2 #1", _config1.c2);
        console2.log("c2 #2", _config2.c2);
        console2.log("c2 match?", _config1.c2 == _config2.c2 ? "yes" : " >>> NO <<<");
        console2.log("dmax #1", _config1.dmax);
        console2.log("dmax #2", _config2.dmax);
        console2.log("dmax match?", _config1.dmax == _config2.dmax ? "yes" : " >>> NO <<<");
        console2.log("--------------------------------");
    }

    function _acceptableDiff(int256 _value, int256 _1e3Limit, int256 _1e6Limit, int256 _1e9Limit, int256 _limit)
        internal
        pure
        returns (int256)
    {
        if (_value < 1e3) {
            return _1e3Limit;
        } else if (_value < 1e6) {
            return _1e6Limit;
        } else if (_value < 1e9) {
            return _1e9Limit;
        } else {
            return _limit;
        }
    }

    function _makeMsg(string memory _msg, uint256 _id, int256 _got, int256 _expected)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            _msg, "[", vm.toString(_id), "] got: ", vm.toString(_got), " expected: ", vm.toString(_expected)
        );
    }
}
