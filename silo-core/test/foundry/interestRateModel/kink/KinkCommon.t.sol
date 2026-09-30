// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {SignedMath} from "openzeppelin5/utils/math/SignedMath.sol";
import {
    DynamicKinkModel, IDynamicKinkModel
} from "../../../../contracts/interestRateModel/kink/DynamicKinkModel.sol";
import {IDynamicKinkModelConfig} from "../../../../contracts/interfaces/IDynamicKinkModelConfig.sol";

import {KinkCommon} from "./KinkCommon.sol";

contract KinkCommonTest is Test, KinkCommon {
    modifier whenValidConfig(RandomKinkConfig memory _config) {
        bool valid = _isValidConfig(_config);
        vm.assume(valid);

        _;
    }

    modifier makeValidImmutableArgs(IDynamicKinkModel.ImmutableArgs memory _immutableArgs) {
        _immutableArgs.timelock = uint32(_immutableArgs.timelock % (FACTORY.IRM().MAX_TIMELOCK() + 1));
        _immutableArgs.rcompCap = int96(SignedMath.max(1, _immutableArgs.rcompCap % FACTORY.IRM().RCUR_CAP()));

        _;
    }

    /*  
    FOUNDRY_PROFILE=core_test forge test --mt test_self_makeConfigValid -vv
    */
    function test_self_makeConfigValid(IDynamicKinkModel.Config memory _config) public {
        if (address(irm) == address(0)) irm = new DynamicKinkModel();

        _printConfig(_config);
        _makeConfigValid(_config);
        _printConfig(_config);

        assertTrue(_isValidConfig(_config), "_makeConfigValid does not work");
    }

    function _assertConfigEq(
        IDynamicKinkModel.Config memory _config1,
        IDynamicKinkModel.Config memory _config2,
        string memory _name
    ) internal pure {
        assertEq(_config1.ulow, _config2.ulow, string.concat("[", _name, "] ulow does not match"));
        assertEq(_config1.u1, _config2.u1, string.concat("[", _name, "] u1 does not match"));
        assertEq(_config1.u2, _config2.u2, string.concat("[", _name, "] u2 does not match"));
        assertEq(_config1.ucrit, _config2.ucrit, string.concat("[", _name, "] ucrit does not match"));
        assertEq(_config1.rmin, _config2.rmin, string.concat("[", _name, "] rmin does not match"));
        assertEq(_config1.kmin, _config2.kmin, string.concat("[", _name, "] kmin does not match"));
        assertEq(_config1.kmax, _config2.kmax, string.concat("[", _name, "] kmax does not match"));
        assertEq(_config1.alpha, _config2.alpha, string.concat("[", _name, "] alpha does not match"));
        assertEq(_config1.cminus, _config2.cminus, string.concat("[", _name, "] cminus does not match"));
        assertEq(_config1.cplus, _config2.cplus, string.concat("[", _name, "] cplus does not match"));
        assertEq(_config1.c1, _config2.c1, string.concat("[", _name, "] c1 does not match"));
        assertEq(_config1.c2, _config2.c2, string.concat("[", _name, "] c2 does not match"));
        assertEq(_config1.dmax, _config2.dmax, string.concat("[", _name, "] dmax does not match"));
    }

    function _assertCorrectHistory(IDynamicKinkModelConfig _in, IDynamicKinkModelConfig _out) internal view {
        (, IDynamicKinkModelConfig irmConfig) = irm.configsHistory(_in);
        assertEq(address(irmConfig), address(_out), "history should point from _in => _out");
    }
}
