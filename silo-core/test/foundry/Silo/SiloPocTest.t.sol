// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {MintableToken} from "silo-core/test/foundry/_common/MintableToken.sol";
import {SiloFixture} from "silo-core/test/foundry/_common/fixtures/SiloFixture.sol";
import {SiloConfigOverride} from "silo-core/test/foundry/_common/fixtures/SiloFixture.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";

/// @dev Test with a ready for testing silo market setup.
/// For more examples on how to interact with the silo market, see the silo-core/test/foundry/Silo folder
/// deposits: silo-core/test/foundry/Silo/deposit
/// withdrawals: silo-core/test/foundry/Silo/withdraw
/// borrow: silo-core/test/foundry/Silo/borrow
/// repay: silo-core/test/foundry/Silo/repay
/// flashloans: silo-core/test/foundry/Silo/flashloan
contract SiloPocTest is Test {
    ISiloConfig internal _siloConfig;

    function setUp() public {
        // Example of how you can deploy a silo with a specific config and override some values if needed
        SiloFixture siloFixture = new SiloFixture();

        // SiloConfigOverride is a struct that contains the overrides for the silo config.
        // It is used to override the default values for the silo config.
        SiloConfigOverride memory configOverride;

        // tokens can be overridden with any other implementation of ERC20
        configOverride.token0 = address(new MintableToken(18));
        configOverride.token1 = address(new MintableToken(8));

        // If any specific config is needed, it can be overridden here.
        // The config file should be created in the silo-core/deploy/input/anvil folder.
        // For more config examples, see the silo-core/deploy/input folder.
        configOverride.configName = SiloConfigsNames.SILO_LOCAL_GAUGE_HOOK_RECEIVER;

        // Deploy the silo with the overrides
        (_siloConfig,,,,,) = siloFixture.deploy_local(configOverride);
    }

    /// @dev Example of how you can access the silo config
    // FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_poc_print_silo_market_config
    function test_poc_print_silo_market_config() public {
        (address silo0, address silo1) = _siloConfig.getSilos();

        emit log_string("\n--------------------------------");

        emit log_named_address("\n[silo0]", silo0);
        _printSiloConfig(silo0);

        emit log_named_address("\n[silo1]", silo1);
        _printSiloConfig(silo1);
    }

    function _printSiloConfig(address _silo) internal {
        ISiloConfig.ConfigData memory config = _siloConfig.getConfig(_silo);

        emit log_named_address("token", address(config.token));
        emit log_named_address("protectedShareToken", address(config.protectedShareToken));
        emit log_named_address("collateralShareToken", address(config.collateralShareToken));
        emit log_named_address("debtShareToken", address(config.debtShareToken));
        emit log_named_address("solvencyOracle", address(config.solvencyOracle));
        emit log_named_address("maxLtvOracle", address(config.maxLtvOracle));
        emit log_named_address("interestRateModel", address(config.interestRateModel));
        emit log_named_uint("maxLtv", config.maxLtv);
        emit log_named_uint("lt", config.lt);
        emit log_named_uint("liquidationTargetLtv", config.liquidationTargetLtv);
        emit log_named_uint("liquidationFee", config.liquidationFee);
        emit log_named_uint("flashloanFee", config.flashloanFee);
        emit log_named_address("hookReceiver", address(config.hookReceiver));
        emit log_named_string("callBeforeQuote", config.callBeforeQuote ? "true" : "false");
    }
}
