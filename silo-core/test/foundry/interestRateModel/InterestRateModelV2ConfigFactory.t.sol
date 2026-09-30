// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IInterestRateModelV2} from "silo-core/contracts/interfaces/IInterestRateModelV2.sol";
import {InterestRateModelV2Factory} from "silo-core/contracts/interestRateModel/InterestRateModelV2Factory.sol";

import {InterestRateModelConfigs} from "../_common/InterestRateModelConfigs.sol";

// forge test -vv --mc InterestRateModelV2FactoryTest
contract InterestRateModelV2FactoryTest is Test, InterestRateModelConfigs {
    InterestRateModelV2Factory factory;

    function setUp() public {
        factory = new InterestRateModelV2Factory();
    }

    /*
    forge test -vv --mt test_IRMF_hashConfig
    */
    function test_IRMF_hashConfig() public view {
        IInterestRateModelV2.Config memory config;
        assertEq(keccak256(abi.encode(config)), factory.hashConfig(config), "hash should match");
    }

    /*
    forge test -vv --mt test_IRMF_verifyConfig
    */
    function test_IRMF_verifyConfig() public {
        IInterestRateModelV2.Config memory config;

        vm.expectRevert(IInterestRateModelV2.InvalidUopt.selector);
        factory.verifyConfig(config);

        config.uopt = -1;
        vm.expectRevert(IInterestRateModelV2.InvalidUopt.selector);
        factory.verifyConfig(config);

        config.uopt = int256(factory.DP());
        vm.expectRevert(IInterestRateModelV2.InvalidUopt.selector);
        factory.verifyConfig(config);

        config.uopt = 0.5e18; // valid

        config.ucrit = config.uopt - 1;
        vm.expectRevert(IInterestRateModelV2.InvalidUcrit.selector);
        factory.verifyConfig(config);

        config.ucrit = int256(factory.DP());
        vm.expectRevert(IInterestRateModelV2.InvalidUcrit.selector);
        factory.verifyConfig(config);

        config.ucrit = config.uopt + 1; // valid

        config.ulow = -1;
        vm.expectRevert(IInterestRateModelV2.InvalidUlow.selector);
        factory.verifyConfig(config);

        config.ulow = config.uopt + 1;
        vm.expectRevert(IInterestRateModelV2.InvalidUlow.selector);
        factory.verifyConfig(config);

        config.ulow = config.uopt - 1; // valid

        config.ki = -1;
        vm.expectRevert(IInterestRateModelV2.InvalidKi.selector);
        factory.verifyConfig(config);

        config.ki = 1; // valid

        config.kcrit = -1;
        vm.expectRevert(IInterestRateModelV2.InvalidKcrit.selector);
        factory.verifyConfig(config);

        config.kcrit = 1; // valid

        config.klow = -1;
        vm.expectRevert(IInterestRateModelV2.InvalidKlow.selector);
        factory.verifyConfig(config);

        config.klow = 1; // valid

        config.klin = -1;
        vm.expectRevert(IInterestRateModelV2.InvalidKlin.selector);
        factory.verifyConfig(config);

        config.klin = 1; // valid

        config.beta = -1;
        vm.expectRevert(IInterestRateModelV2.InvalidBeta.selector);
        factory.verifyConfig(config);
        config.beta = 1;

        config.ri = -1;
        vm.expectRevert(IInterestRateModelV2.InvalidRi.selector);
        factory.verifyConfig(config);
        config.ri = 2 ** 46 - 1; // valid

        config.Tcrit = -1;
        vm.expectRevert(IInterestRateModelV2.InvalidTcrit.selector);
        factory.verifyConfig(config);
        config.Tcrit = type(int112).max; // valid

        factory.verifyConfig(config);

        factory.verifyConfig(_defaultConfig());
    }

    /*
    forge test -vv --mt test_IRMF_create_new
    */
    function test_IRMF_create_new() public {
        IInterestRateModelV2.Config memory config = _defaultConfig();

        (bytes32 configHash, IInterestRateModelV2 irm) = factory.create(config, bytes32(0));

        assertEq(configHash, factory.hashConfig(config), "wrong config hash");
        assertEq(address(irm), address(factory.irmByConfigHash(configHash)), "irm address is stored");
    }

    /*
    forge test -vv --mt test_IRMF_create_reusable
    */
    function test_IRMF_create_reusable() public {
        IInterestRateModelV2.Config memory config = _defaultConfig();

        (bytes32 configHash, IInterestRateModelV2 irm) = factory.create(config, bytes32(0));
        (bytes32 configHash2, IInterestRateModelV2 irm2) = factory.create(config, bytes32(0));

        assertEq(configHash, configHash2, "config hash is the same for same config");
        assertEq(address(irm), address(irm2), "irm address is the same");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_IRMF_create_reorg
    */
    function test_IRMF_create_reorg() public {
        address eoa1 = makeAddr("eoa1");
        address eoa2 = makeAddr("eoa2");

        IInterestRateModelV2.Config memory config = _defaultConfig();

        uint256 snapshot = vm.snapshotState();

        vm.prank(eoa1);
        (, IInterestRateModelV2 irm) = factory.create(config, bytes32(0));

        vm.revertToState(snapshot);

        vm.prank(eoa2);
        (, IInterestRateModelV2 irm2) = factory.create(config, bytes32(0));

        assertNotEq(address(irm), address(irm2), "irm address is the same");
    }
}
