// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {IDynamicKinkModel} from "../../../contracts/interfaces/IDynamicKinkModel.sol";

contract KinkDefaultConfigTestData is Test {
    using SafeCast for int256;
    using SafeCast for uint256;
    // variable names must be in alphabetic order:
    struct Input {
        uint256 R100max;
        uint256 Rcritmax;
        uint256 Rcritmin;
        uint256 Rmin;
        uint256 T1;
        uint256 T2;
        uint256 Tcrit;
        uint256 Tlow;
        uint256 Tmin;
        uint256 u1;
        uint256 u2;
        uint256 ucrit;
        uint256 ulow;
    }

    // variable names must be in alphabetic order
    struct Config {
        uint256 alpha;
        uint256 c1;
        uint256 c2;
        uint256 cminus;
        uint256 cplus;
        uint256 dmax;
        uint256 kmax;
        uint256 kmin;
        uint256 rmin;
        uint256 u1;
        uint256 u2;
        uint256 ucrit;
        uint256 ulow;
    }

    struct UserInputDataJson {
        Config config;
        uint256 id;
        Input input;
        uint256 success;
    }

    struct UserInputData {
        IDynamicKinkModel.Config config;
        uint256 id;
        IDynamicKinkModel.UserFriendlyConfig input;
        bool success;
    }

    function _readUserInputDataFromJson() internal view returns (UserInputData[] memory data) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/silo-core/test/foundry/data/KinkDefaultConfigTests.json");
        string memory json = vm.readFile(path);

        UserInputDataJson[] memory dataJson =
            abi.decode(vm.parseJson(json, string(abi.encodePacked("."))), (UserInputDataJson[]));
        require(dataJson.length > 0, "No data found");
        data = new UserInputData[](dataJson.length);

        for (uint256 i; i < dataJson.length; i++) {
            // console2.log("dataJson[i].id", dataJson[i].id);
            data[i] = _toConfigStruct(dataJson[i]);
        }

        // for (uint i; i < data.length; i++) {
        //     _printRcomp(data[i]);
        // }
    }

    function _print(UserInputDataJson memory _data) internal pure {
        console2.log("ID#", _data.id);
        console2.log("input:");
        console2.log("ulow", _data.input.ulow);
        console2.log("u1", _data.input.u1);
        console2.log("u2", _data.input.u2);
        console2.log("ucrit", _data.input.ucrit);
        console2.log("Rmin", _data.input.Rmin);
        console2.log("Rcritmin", _data.input.Rcritmin);
        console2.log("Rcritmax", _data.input.Rcritmax);
        console2.log("R100max", _data.input.R100max);
        console2.log("Tlow", _data.input.Tlow);
        console2.log("T1", _data.input.T1);
        console2.log("T2", _data.input.T2);
        console2.log("Tcrit", _data.input.Tcrit);
        console2.log("Tmin", _data.input.Tmin);

        console2.log("config:");
        console2.log("alpha", _data.config.alpha);
        console2.log("c1", _data.config.c1);
        console2.log("c2", _data.config.c2);
        console2.log("cminus", _data.config.cminus);
        console2.log("cplus", _data.config.cplus);
        console2.log("dmax", _data.config.dmax);
        console2.log("kmax", _data.config.kmax);
        console2.log("kmin", _data.config.kmin);
        console2.log("rmin", _data.config.rmin);
        console2.log("u1", _data.config.u1);
        console2.log("u2", _data.config.u2);
        console2.log("ucrit", _data.config.ucrit);
        console2.log("ulow", _data.config.ulow);
    }

    function _print(UserInputData memory _data) internal pure {
        console2.log("ID#", _data.id);

        console2.log("INPUT");
        console2.log("ulow", _data.input.ulow);
        console2.log("u1", _data.input.u1);
        console2.log("u2", _data.input.u2);
        console2.log("ucrit", _data.input.ucrit);
        console2.log("Rmin", _data.input.rmin);
        console2.log("Rcritmin", _data.input.rcritMin);
        console2.log("Rcritmax", _data.input.rcritMax);
        console2.log("R100max", _data.input.r100);
        console2.log("Tlow", _data.input.tlow);
        console2.log("T1", _data.input.t1);
        console2.log("T2", _data.input.t2);
        console2.log("Tcrit", _data.input.tcrit);
        console2.log("Tmin", _data.input.tMin);

        console2.log("Config");
        console2.log("alpha", _data.config.alpha);
        console2.log("c1", _data.config.c1);
        console2.log("c2", _data.config.c2);
        console2.log("cminus", _data.config.cminus);
        console2.log("cplus", _data.config.cplus);
        console2.log("dmax", _data.config.dmax);
        console2.log("kmax", _data.config.kmax);
        console2.log("kmin", _data.config.kmin);
        console2.log("rmin", _data.config.rmin);
        console2.log("u1", _data.config.u1);
        console2.log("u2", _data.config.u2);
        console2.log("ucrit", _data.config.ucrit);
        console2.log("ulow", _data.config.ulow);
    }

    function _toConfigStruct(UserInputDataJson memory _in) internal pure returns (UserInputData memory _out) {
        // console2.log("config transform");

        _out.config = IDynamicKinkModel.Config({
            ulow: int256(_in.config.ulow),
            u1: int256(_in.config.u1),
            u2: int256(_in.config.u2),
            ucrit: int256(_in.config.ucrit),
            rmin: int256(_in.config.rmin),
            kmin: int256(_in.config.kmin).toInt96(),
            kmax: int256(_in.config.kmax).toInt96(),
            alpha: int256(_in.config.alpha),
            cminus: int256(_in.config.cminus),
            cplus: int256(_in.config.cplus),
            c1: int256(_in.config.c1),
            c2: int256(_in.config.c2),
            dmax: int256(_in.config.dmax)
        });

        // console2.log("input transform");
        _out.input = IDynamicKinkModel.UserFriendlyConfig({
            ulow: _in.input.ulow.toUint64(),
            u1: _in.input.u1.toUint64(),
            u2: _in.input.u2.toUint64(),
            ucrit: _in.input.ucrit.toUint64(),
            rmin: _in.input.Rmin.toUint72(),
            rcritMin: _in.input.Rcritmin.toUint72(),
            rcritMax: _in.input.Rcritmax.toUint72(),
            r100: _in.input.R100max.toUint72(),
            tlow: _in.input.Tlow.toUint32(),
            t1: _in.input.T1.toUint32(),
            t2: _in.input.T2.toUint32(),
            tcrit: _in.input.Tcrit.toUint32(),
            tMin: _in.input.Tmin.toUint32()
        });

        _out.id = _in.id;
        _out.success = _in.success == 1;
    }
}
