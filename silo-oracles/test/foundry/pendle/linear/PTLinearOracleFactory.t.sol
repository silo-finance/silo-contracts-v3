// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import {Initializable} from "openzeppelin5-upgradeable/proxy/utils/Initializable.sol";

import {IPTLinearOracleConfig} from "silo-oracles/contracts/interfaces/IPTLinearOracleConfig.sol";
import {IPTLinearOracleFactory} from "silo-oracles/contracts/interfaces/IPTLinearOracleFactory.sol";
import {IPTLinearOracle} from "silo-oracles/contracts/interfaces/IPTLinearOracle.sol";

import {PTLinearOracle} from "silo-oracles/contracts/pendle/linear/PTLinearOracle.sol";

import {PTLinearOracleFactory} from "silo-oracles/contracts/pendle/linear/PTLinearOracleFactory.sol";

import {SparkLinearDiscountOracleFactoryMock} from "./_common/SparkLinearDiscountOracleFactoryMock.sol";
import {PTLinearMocks} from "./_common/PTLinearMocks.sol";

/*
    FOUNDRY_PROFILE=oracles forge test --mc PTLinearOracleFactoryTest --ffi -vv
*/
contract PTLinearOracleFactoryTest is PTLinearMocks {
    PTLinearOracleFactory immutable FACTORY;

    constructor() {
        FACTORY = new PTLinearOracleFactory(address(new SparkLinearDiscountOracleFactoryMock()));
    }

    function setUp() public {
        vm.clearMockedCalls();
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_ptLinear_predictAddress_fuzz --ffi -vv
    */
    function test_ptLinear_predictAddress_fuzz(
        IPTLinearOracleFactory.DeploymentConfig memory _config,
        address _deployer,
        bytes32 _externalSalt
    ) public assumeValidConfig(_config) {
        vm.assume(_deployer != address(0));

        _doAllNecessaryMockCalls();

        address predictedAddress = FACTORY.predictAddress(_config, _deployer, _externalSalt);

        vm.prank(_deployer);
        address oracle = address(FACTORY.create(_config, _externalSalt));

        assertEq(oracle, predictedAddress, "Predicted address does not match");

        address oracle2 = address(FACTORY.create(_config, _externalSalt));

        address predictedAddress2 = FACTORY.predictAddress(_config, _deployer, _externalSalt);

        assertEq(
            predictedAddress, predictedAddress2, "predicted addresses should be the same if we reuse the same config"
        );

        assertEq(oracle2, oracle, "Oracle addresses should be the same if we reuse the same config");
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_ptLinear_resolveExistingOracle --ffi -vv
    */
    function test_ptLinear_resolveExistingOracle_fuzz(IPTLinearOracleFactory.DeploymentConfig memory _config)
        public
        assumeValidConfig(_config)
    {
        _doAllNecessaryMockCalls();

        bytes32 configId = FACTORY.hashConfig(_config);

        address existingOracle = FACTORY.resolveExistingOracle(configId);

        assertEq(existingOracle, address(0), "No existing oracle should be found");

        address oracle = address(FACTORY.create(_config, bytes32(0)));

        existingOracle = FACTORY.resolveExistingOracle(configId);
        assertEq(existingOracle, address(oracle), "Existing oracle should be found");
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_ptLinear_reusableConfigs_fuzz --ffi -vv
    */
    function test_ptLinear_reusableConfigs_fuzz(
        IPTLinearOracleFactory.DeploymentConfig memory _config,
        address _deployer,
        bytes32 _externalSalt
    ) public assumeValidConfig(_config) {
        _doAllNecessaryMockCalls();

        vm.prank(_deployer);
        address oracle1 = address(FACTORY.create(_config, _externalSalt));

        // deployer does not matter here, because we use the same config
        address oracle2 = address(FACTORY.create(_config, bytes32(0)));

        assertEq(oracle1, oracle2, "Oracle addresses should be the same if we reuse the same config");
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_ptLinear_reorg --ffi -vv
    */
    function test_ptLinear_reorg(
        IPTLinearOracleFactory.DeploymentConfig memory _config1,
        IPTLinearOracleFactory.DeploymentConfig memory _config2,
        address _eoa1,
        address _eoa2
    ) public assumeValidConfig(_config1) assumeValidConfig(_config2) {
        vm.assume(_eoa1 != address(0));
        vm.assume(_eoa2 != address(0));
        vm.assume(_eoa1 != _eoa2);
        vm.assume(_hashConfig(_config1) != _hashConfig(_config2));

        _mockExpiry();
        _mockDecimals(makeAddr("ptToken"), 18);

        uint256 snapshot = vm.snapshotState();

        vm.prank(_eoa1);
        address oracle1 = address(FACTORY.create(_config1, bytes32(0)));

        vm.prank(_eoa2);
        address oracle2 = address(FACTORY.create(_config2, bytes32(0)));

        vm.revertToState(snapshot);

        vm.prank(_eoa1); // user1 but config2
        address oracle3 = address(FACTORY.create(_config2, bytes32(0)));

        assertNotEq(oracle1, oracle2, "Oracle addresses should be different if we reorg");
        assertEq(oracle1, oracle3, "Oracle addresses should be the same for same user");
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_ptLinear_verifyConfig_pass_fuzz --ffi -vv
    */
    function test_ptLinear_verifyConfig_pass_fuzz(IPTLinearOracleFactory.DeploymentConfig memory _config)
        public
        assumeValidConfig(_config)
    {
        _doAllNecessaryMockCalls();

        FACTORY.createAndVerifyOracleConfig(_config);
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_ptLinear_createAndVerifyConfig_fail --ffi -vv
    */
    function test_ptLinear_createAndVerifyConfig_fail() public {
        vm.warp(100);

        IPTLinearOracleFactory.DeploymentConfig memory config;

        config.maxYield = 1e18;
        vm.expectRevert(abi.encodeWithSelector(IPTLinearOracleFactory.InvalidMaxYield.selector));
        FACTORY.createAndVerifyOracleConfig(config);

        config.maxYield = 0.3e18;

        vm.expectRevert(abi.encodeWithSelector(IPTLinearOracleFactory.AddressZero.selector));
        FACTORY.createAndVerifyOracleConfig(config);

        vm.expectRevert(abi.encodeWithSelector(IPTLinearOracleFactory.AddressZero.selector));
        FACTORY.createAndVerifyOracleConfig(config);

        config.hardcodedQuoteToken = makeAddr("quoteToken");
        config.ptToken = makeAddr("ptToken");
        _mockDecimals(config.ptToken, 19);
        _mockExpiry(makeAddr("ptToken"), 0);

        vm.expectRevert(abi.encodeWithSelector(IPTLinearOracleFactory.MaturityDateInvalid.selector));
        FACTORY.createAndVerifyOracleConfig(config);

        _mockExpiry(makeAddr("ptToken"), block.timestamp - 1);
        vm.expectRevert(abi.encodeWithSelector(IPTLinearOracleFactory.MaturityDateIsInThePast.selector));
        FACTORY.createAndVerifyOracleConfig(config);

        _mockExpiry(makeAddr("ptToken"), block.timestamp + 1);
        vm.expectRevert(abi.encodeWithSelector(IPTLinearOracleFactory.NormalizationDividerTooLarge.selector));
        FACTORY.createAndVerifyOracleConfig(config);

        _mockDecimals(config.ptToken, 0);
        FACTORY.createAndVerifyOracleConfig(config);
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_ptLinear_hashConfig --ffi -vv
    */
    function test_ptLinear_hashConfig_fuzz(IPTLinearOracleFactory.DeploymentConfig memory _config) public view {
        bytes32 configId = FACTORY.hashConfig(_config);

        assertEq(configId, keccak256(abi.encode(_config)), "Config hash should match");
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_ptLinear_implementation_canNotBeInit --ffi -vv
    */
    function test_ptLinear_implementation_canNotBeInit() public {
        address implementation = address(FACTORY.ORACLE_IMPLEMENTATION());

        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        IPTLinearOracle(implementation).initialize(IPTLinearOracleConfig(address(1)));
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_ptLinear_disableInitializers --ffi -vv
    */
    function test_ptLinear_disableInitializers() public {
        PTLinearOracle oracle = new PTLinearOracle();

        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        oracle.initialize(IPTLinearOracleConfig(address(1)));
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_ptLinear_clone_alreadyInitialized --ffi -vv
    */
    function test_ptLinear_clone_alreadyInitialized() public {
        IPTLinearOracleFactory.DeploymentConfig memory config;

        _makeValidConfig(config);

        _doAllNecessaryMockCalls();

        address oracle = address(FACTORY.create(config, bytes32(0)));

        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        IPTLinearOracle(oracle).initialize(IPTLinearOracleConfig(address(1)));
    }

    /*
    FOUNDRY_PROFILE=oracles forge test --mt test_ptLinear_getConfig --ffi -vv
    */
    function test_ptLinear_getConfig(IPTLinearOracleFactory.DeploymentConfig memory _config)
        public
        assumeValidConfig(_config)
    {
        _doAllNecessaryMockCalls();

        IPTLinearOracle oracle = FACTORY.create(_config, bytes32(0));
        IPTLinearOracleConfig.OracleConfig memory cfg = oracle.oracleConfig().getConfig();

        assertEq(cfg.linearOracle, makeAddr("sparkLinearDiscountOracle"), "Linear oracle should match");
        assertEq(cfg.ptToken, makeAddr("ptToken"), "PT token should match");
        assertEq(cfg.hardcodedQuoteToken, _config.hardcodedQuoteToken, "Hardcoded quote token should match");
    }

    function _hashConfig(IPTLinearOracleFactory.DeploymentConfig memory _config) internal pure returns (bytes32) {
        return keccak256(abi.encode(_config));
    }
}
