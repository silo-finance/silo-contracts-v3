// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {console2} from "forge-std/console2.sol";

import {
    DynamicKinkModel, IDynamicKinkModel
} from "../../../../contracts/interestRateModel/kink/DynamicKinkModel.sol";
import {KinkCommonTest} from "./KinkCommon.t.sol";

/*
FOUNDRY_PROFILE=core_test forge test --mc KinkVerifyConfigTest -vv
*/
contract KinkVerifyConfigTest is KinkCommonTest {
    function setUp() public {
        irm = new DynamicKinkModel();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_constants -vv
    */
    function test_kink_constants() public view {
        int256 dp = 1e18;

        assertEq(dp, _DP, "invalid local DP");

        console2.log("UNIVERSAL_LIMIT %s", irm.UNIVERSAL_LIMIT());
        console2.log("RCUR_CAP %s", irm.RCUR_CAP());
        console2.log("RCOMP_CAP_PER_SECOND %s", irm.RCOMP_CAP_PER_SECOND());
        console2.log("X_MAX %s", irm.X_MAX());

        assertEq(irm.UNIVERSAL_LIMIT(), 1e9 * dp, "invalid UNIVERSAL_LIMIT");
        assertEq(irm.UNIVERSAL_LIMIT(), UNIVERSAL_LIMIT, "local UNIVERSAL_LIMIT does not match");
        assertEq(irm.MAX_TIMELOCK(), 7 days, "invalid MAX_TIMELOCK");

        assertLe(
            irm.UNIVERSAL_LIMIT(),
            type(int96).max,
            "universal limit is used ot cap int96, so we checking if cast does not overflow"
        );

        assertGe(
            irm.UNIVERSAL_LIMIT(),
            type(int96).min,
            "universal limit is used ot cap int96, so we checking if cast does not overflow"
        );

        assertEq(irm.RCUR_CAP(), 10 * dp, "invalid RCUR_CAP");
        assertEq(irm.RCOMP_CAP_PER_SECOND(), irm.RCUR_CAP() / 365 days, "invalid RCOMP_CAP_PER_SECOND");

        assertEq(irm.X_MAX(), 11 * dp, "invalid X_MAX");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_verifyConfig -vv
    */
    function test_kink_verifyConfig() public {
        IDynamicKinkModel.Config memory config;

        // empty config pass
        irm.verifyConfig(config);

        config.ulow = -1;
        vm.expectRevert(IDynamicKinkModel.InvalidUlow.selector);
        irm.verifyConfig(config);

        config.ulow = 1e18 + 1;
        vm.expectRevert(IDynamicKinkModel.InvalidUlow.selector);
        irm.verifyConfig(config);

        config.ulow = 0.5e18; // valid value

        config.u1 = -1;
        vm.expectRevert(IDynamicKinkModel.InvalidU1.selector);
        irm.verifyConfig(config);

        config.u1 = 1e18 + 1;
        vm.expectRevert(IDynamicKinkModel.InvalidU1.selector);
        irm.verifyConfig(config);

        config.u1 = 0.5e18; // valid value
        vm.expectRevert(IDynamicKinkModel.InvalidU2.selector);
        irm.verifyConfig(config);

        config.u2 = 1e18 + 1;
        vm.expectRevert(IDynamicKinkModel.InvalidU2.selector);
        irm.verifyConfig(config);

        config.u2 = 0.6e18; // valid value
        vm.expectRevert(IDynamicKinkModel.InvalidUcrit.selector);
        irm.verifyConfig(config);

        config.ucrit = 1e18 + 1;
        vm.expectRevert(IDynamicKinkModel.InvalidUcrit.selector);
        irm.verifyConfig(config);

        config.ucrit = 1e18; // valid value
        irm.verifyConfig(config);

        // ----

        config.rmin = -1;
        vm.expectRevert(IDynamicKinkModel.InvalidRmin.selector);
        irm.verifyConfig(config);

        config.rmin = 1e18 + 1;
        vm.expectRevert(IDynamicKinkModel.InvalidRmin.selector);
        irm.verifyConfig(config);

        config.rmin = 100e16; // valid value
        irm.verifyConfig(config);

        config.kmin = -1;
        vm.expectRevert(IDynamicKinkModel.InvalidKmin.selector);
        irm.verifyConfig(config);

        // Safe: UNIVERSAL_LIMIT is verified to fit in int96 (see test_kink_constants).
        // Casting is safe; adding 1 intentionally causes overflow to test validation.
        // forge-lint: disable-next-line(unsafe-typecast)
        config.kmin = int96(UNIVERSAL_LIMIT) + 1;
        vm.expectRevert(IDynamicKinkModel.InvalidKmin.selector);
        irm.verifyConfig(config);

        config.kmin = 100; // valid value
        vm.expectRevert(IDynamicKinkModel.InvalidKmax.selector);
        irm.verifyConfig(config);

        config.kmax = int96(UNIVERSAL_LIMIT) + 1;
        vm.expectRevert(IDynamicKinkModel.InvalidKmax.selector);
        irm.verifyConfig(config);

        config.kmax = int96(UNIVERSAL_LIMIT); // valid value
        irm.verifyConfig(config);

        // ----

        config.alpha = -1;
        vm.expectRevert(IDynamicKinkModel.InvalidAlpha.selector);
        irm.verifyConfig(config);

        config.alpha = UNIVERSAL_LIMIT + 1;
        vm.expectRevert(IDynamicKinkModel.InvalidAlpha.selector);
        irm.verifyConfig(config);

        config.alpha = UNIVERSAL_LIMIT; // valid value
        irm.verifyConfig(config);

        // ----

        config.cminus = -1;
        vm.expectRevert(IDynamicKinkModel.InvalidCminus.selector);
        irm.verifyConfig(config);

        config.cminus = UNIVERSAL_LIMIT + 1;
        vm.expectRevert(IDynamicKinkModel.InvalidCminus.selector);
        irm.verifyConfig(config);

        config.cminus = UNIVERSAL_LIMIT; // valid value
        irm.verifyConfig(config);

        config.cplus = -1;
        vm.expectRevert(IDynamicKinkModel.InvalidCplus.selector);
        irm.verifyConfig(config);

        config.cplus = UNIVERSAL_LIMIT + 1;
        vm.expectRevert(IDynamicKinkModel.InvalidCplus.selector);
        irm.verifyConfig(config);

        config.cplus = UNIVERSAL_LIMIT / 2; // valid value
        irm.verifyConfig(config);

        config.c1 = -1;
        vm.expectRevert(IDynamicKinkModel.InvalidC1.selector);
        irm.verifyConfig(config);

        config.c1 = UNIVERSAL_LIMIT + 1;
        vm.expectRevert(IDynamicKinkModel.InvalidC1.selector);
        irm.verifyConfig(config);

        config.c1 = UNIVERSAL_LIMIT / 2; // valid value
        irm.verifyConfig(config);

        // ----

        config.c2 = -1;
        vm.expectRevert(IDynamicKinkModel.InvalidC2.selector);
        irm.verifyConfig(config);

        config.c2 = UNIVERSAL_LIMIT + 1;
        vm.expectRevert(IDynamicKinkModel.InvalidC2.selector);
        irm.verifyConfig(config);

        config.c2 = UNIVERSAL_LIMIT / 2; // valid value
        vm.expectRevert(IDynamicKinkModel.InvalidDmax.selector);
        irm.verifyConfig(config);

        config.dmax = UNIVERSAL_LIMIT + 1;
        vm.expectRevert(IDynamicKinkModel.InvalidDmax.selector);
        irm.verifyConfig(config);

        config.dmax = config.c2 + 1; // valid value
        irm.verifyConfig(config);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_verifyConfig_maxValues -vv
    */
    function test_kink_verifyConfig_maxValues() public view {
        IDynamicKinkModel.Config memory config;

        config.ulow = _DP;
        config.u1 = _DP;
        config.u2 = _DP;
        config.ucrit = _DP;
        config.rmin = _DP;
        config.kmin = int96(UNIVERSAL_LIMIT);
        config.kmax = int96(UNIVERSAL_LIMIT);
        config.alpha = UNIVERSAL_LIMIT;
        config.cminus = UNIVERSAL_LIMIT;
        config.cplus = UNIVERSAL_LIMIT;
        config.c1 = UNIVERSAL_LIMIT;
        config.c2 = UNIVERSAL_LIMIT;
        config.dmax = UNIVERSAL_LIMIT;

        irm.verifyConfig(config);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_verifyConfig_minValues -vv
    */
    function test_kink_verifyConfig_minValues() public view {
        IDynamicKinkModel.Config memory config;

        config.ulow = 1;
        config.u1 = 1;
        config.u2 = 1;
        config.ucrit = 1;
        config.rmin = 1;
        config.kmin = 1;
        config.kmax = 1;
        config.alpha = 1;
        config.cminus = 1;
        config.cplus = 1;
        config.c1 = 1;
        config.c2 = 1;
        config.dmax = 1;

        irm.verifyConfig(config);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_verifyConfig_relation_ucrit -vv
    */
    function test_kink_verifyConfig_relation_ucrit() public {
        IDynamicKinkModel.Config memory config = _defaultConfig();

        config.ucrit = config.ulow - 1;
        vm.expectRevert(IDynamicKinkModel.InvalidUcrit.selector);
        irm.verifyConfig(config);

        config.ucrit = config.u2; // valid value
        irm.verifyConfig(config);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_verifyConfig_relation_u2 -vv
    */
    function test_kink_verifyConfig_relation_u2() public {
        IDynamicKinkModel.Config memory config = _defaultConfig();

        config.u2 = config.u1 - 1;
        vm.expectRevert(IDynamicKinkModel.InvalidU2.selector);
        irm.verifyConfig(config);

        config.u2 = config.u1; // valid value
        irm.verifyConfig(config);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_verifyConfig_relation_kmax -vv
    */
    function test_kink_verifyConfig_relation_kmax() public {
        IDynamicKinkModel.Config memory config = _defaultConfig();

        config.kmax = config.kmin - 1;
        vm.expectRevert(IDynamicKinkModel.InvalidKmax.selector);
        irm.verifyConfig(config);

        config.kmax = config.kmin; // valid value
        irm.verifyConfig(config);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_verifyConfig_relation_dmax -vv
    */
    function test_kink_verifyConfig_relation_dmax() public {
        IDynamicKinkModel.Config memory config = _defaultConfig();

        config.dmax = config.c2 - 1;
        vm.expectRevert(IDynamicKinkModel.InvalidDmax.selector);
        irm.verifyConfig(config);

        config.dmax = config.c2; // valid value
        irm.verifyConfig(config);
    }
}
