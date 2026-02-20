// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";

import {StdCheats} from "forge-std/StdCheats.sol";
import {CommonBase} from "forge-std/Base.sol";

import {MainnetDeploy} from "silo-core/deploy/MainnetDeploy.s.sol";
import {SiloFactoryDeploy} from "silo-core/deploy/SiloFactoryDeploy.s.sol";
import {SiloImplementationDeploy} from "silo-core/deploy/SiloImplementationDeploy.s.sol";
import {SiloDeployWithDeployerOwner} from "silo-core/deploy/silo/SiloDeployWithDeployerOwner.s.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

struct SiloConfigOverride {
    address token0;
    address token1;
    address hookReceiver;
    address hookReceiverImplementation;
    address solvencyOracle0;
    address maxLtvOracle0;
    string configName;
}

contract SiloDeploy_Local is SiloDeployWithDeployerOwner {
    bytes32 public constant CLONE_IMPLEMENTATION_KEY = keccak256(bytes("CLONE_IMPLEMENTATION"));

    SiloConfigOverride internal siloConfigOverride;

    error SiloFixtureHookReceiverImplNotFound(string hookReceiver);

    constructor(SiloConfigOverride memory _override) {
        siloConfigOverride = _override;
    }

    function beforeCreateSilo(ISiloConfig.InitData memory _config, address _hookReceiverImplementation)
        internal
        view
        override
        returns (address hookImplementation)
    {
        // Override the default values if overrides are provided
        if (siloConfigOverride.token0 != address(0)) {
            console2.log("[override] token0 %s -> %s", _config.token0, siloConfigOverride.token0);
            _config.token0 = siloConfigOverride.token0;
        }

        if (siloConfigOverride.token1 != address(0)) {
            console2.log("[override] token1 %s -> %s", _config.token1, siloConfigOverride.token1);
            _config.token1 = siloConfigOverride.token1;
        }

        if (siloConfigOverride.solvencyOracle0 != address(0)) {
            console2.log(
                "[override] solvencyOracle0 %s -> %s", _config.solvencyOracle0, siloConfigOverride.solvencyOracle0
            );

            _config.solvencyOracle0 = siloConfigOverride.solvencyOracle0;
        }

        if (siloConfigOverride.maxLtvOracle0 != address(0)) {
            console2.log(
                "[override] maxLtvOracle0 %s -> %s", _config.maxLtvOracle0, siloConfigOverride.maxLtvOracle0
            );

            _config.maxLtvOracle0 = siloConfigOverride.maxLtvOracle0;
        }

        if (
            siloConfigOverride.hookReceiver != address(0)
                || siloConfigOverride.hookReceiverImplementation != address(0)
        ) {
            console2.log("[override] hookReceiver %s -> %s", _config.hookReceiver, siloConfigOverride.hookReceiver);
            console2.log("[override] hookImplementation -> %s", siloConfigOverride.hookReceiverImplementation);

            _config.hookReceiver = siloConfigOverride.hookReceiver;
            hookImplementation = siloConfigOverride.hookReceiverImplementation;
        } else {
            hookImplementation = _hookReceiverImplementation;
        }
    }
}

contract SiloFixture is StdCheats, CommonBase {
    uint256 internal constant _FORKING_BLOCK_NUMBER = 17336000;

    bool internal _mainNetDeployed;

    function deploy_ETH_USDC()
        external
        returns (ISiloConfig siloConfig, ISilo silo0, ISilo silo1, address weth, address usdc, address hookReceiver)
    {
        return _deploy(new SiloDeployWithDeployerOwner(), SiloConfigsNames.SILO_ETH_USDC_UNI_V3);
    }

    function deploy_local(string memory _configName)
        external
        returns (
            ISiloConfig siloConfig,
            ISilo silo0,
            ISilo silo1,
            address token0,
            address token1,
            address hookReceiver
        )
    {
        SiloConfigOverride memory overrideArgs;
        return _deploy(new SiloDeploy_Local(overrideArgs), _configName);
    }

    function deploy_local(SiloConfigOverride memory _override)
        external
        returns (
            ISiloConfig siloConfig,
            ISilo silo0,
            ISilo silo1,
            address token0,
            address token1,
            address hookReceiver
        )
    {
        return _deploy(
            new SiloDeploy_Local(_override),
            bytes(_override.configName).length == 0
                ? SiloConfigsNames.SILO_LOCAL_NO_ORACLE_SILO
                : _override.configName
        );
    }

    function _deploy(SiloDeployWithDeployerOwner _siloDeploy, string memory _configName)
        internal
        returns (
            ISiloConfig siloConfig,
            ISilo silo0,
            ISilo silo1,
            address token0,
            address token1,
            address hookReceiver
        )
    {
        if (!_mainNetDeployed) {
            SiloFactoryDeploy siloFactoryDeploy = new SiloFactoryDeploy();
            siloFactoryDeploy.disableDeploymentsSync();
            siloFactoryDeploy.run();
            console2.log("[SiloFixture] _deploy: siloFactoryDeploy.run() done.");

            SiloImplementationDeploy siloImplementationDeploy = new SiloImplementationDeploy();
            siloImplementationDeploy.disableDeploymentsSync();
            siloImplementationDeploy.run();
            console2.log("[SiloFixture] _deploy: siloImplementationDeploy.run() done.");

            MainnetDeploy mainnetDeploy = new MainnetDeploy();
            mainnetDeploy.disableDeploymentsSync();
            mainnetDeploy.run();
            console2.log("[SiloFixture] _deploy: mainnetDeploy.run() done.");

            _mainNetDeployed = true;
        }

        siloConfig = _siloDeploy.useConfig(_configName).run();
        console2.log("[SiloFixture] _deploy: _siloDeploy(", _configName, ").run() done.");

        (address createdSilo0, address createdSilo1) = siloConfig.getSilos();

        ISiloConfig.ConfigData memory siloConfig0 = siloConfig.getConfig(createdSilo0);
        ISiloConfig.ConfigData memory siloConfig1 = siloConfig.getConfig(createdSilo1);

        silo0 = ISilo(siloConfig0.silo);
        silo1 = ISilo(siloConfig1.silo);
        console2.log("[SiloFixture] silo0", address(silo0));
        console2.log("[SiloFixture] silo1", address(silo1));
        console2.log("[SiloFixture] siloConfig", address(siloConfig));

        token0 = siloConfig0.token;
        token1 = siloConfig1.token;

        hookReceiver = siloConfig0.hookReceiver;
        if (hookReceiver == address(0)) revert("hookReceiver address is empty");

        _labelSiloMarketContracts(siloConfig, createdSilo0, createdSilo1);
    }

    function _labelSiloMarketContracts(ISiloConfig _siloConfig, address _silo0, address _silo1) internal {
        _labelSiloContracts(_siloConfig, _silo0, "Silo0:");
        _labelSiloContracts(_siloConfig, _silo1, "Silo1:");

        ISiloConfig.ConfigData memory config = _siloConfig.getConfig(_silo0);

        vm.label(config.hookReceiver, "HookReceiver");
        vm.label(address(_siloConfig), "SiloConfig");
    }

    function _labelSiloContracts(ISiloConfig _siloConfig, address _silo, string memory _prefix) internal {
        ISiloConfig.ConfigData memory config = _siloConfig.getConfig(_silo);

        vm.label(config.token, string.concat(_prefix, "asset"));
        vm.label(config.protectedShareToken, string.concat(_prefix, "protectedShareToken"));
        vm.label(config.collateralShareToken, string.concat(_prefix, "collateralShareToken"));
        vm.label(config.debtShareToken, string.concat(_prefix, "debtShareToken"));
        vm.label(config.interestRateModel, string.concat(_prefix, "interestRateModel"));

        if (config.solvencyOracle != address(0)) {
            vm.label(config.solvencyOracle, string.concat(_prefix, "solvencyOracle"));
        }

        if (config.maxLtvOracle != address(0)) {
            vm.label(config.maxLtvOracle, string.concat(_prefix, "maxLtvOracle"));
        }
    }
}
