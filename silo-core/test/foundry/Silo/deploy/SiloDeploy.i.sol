// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";

import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {Deployments} from "silo-foundry-utils/lib/Deployments.sol";

import {IChainlinkV3Oracle} from "silo-oracles/contracts/interfaces/IChainlinkV3Oracle.sol";
import {IChainlinkV3Factory} from "silo-oracles/contracts/interfaces/IChainlinkV3Factory.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";
import {SiloDeployWithDeployerOwner} from "silo-core/deploy/silo/SiloDeployWithDeployerOwner.s.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISiloDeployer} from "silo-core/contracts/interfaces/ISiloDeployer.sol";
import {IHookReceiver} from "silo-core/contracts/interfaces/IHookReceiver.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {MainnetDeploy} from "silo-core/deploy/MainnetDeploy.s.sol";
import {SiloOraclesFactoriesContracts} from "silo-oracles/deploy/SiloOraclesFactoriesContracts.sol";

import {UniswapV3OracleFactoryMock} from
    "silo-core/test/foundry/_mocks/oracles-factories/UniswapV3OracleFactoryMock.sol";

import {ChainlinkV3OracleFactoryMock} from
    "silo-core/test/foundry/_mocks/oracles-factories/ChainlinkV3OracleFactoryMock.sol";

import {DIAOracleFactoryMock} from "silo-core/test/foundry/_mocks/oracles-factories/DIAOracleFactoryMock.sol";

/*
AGGREGATOR=1INCH FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc SiloDeployTest
*/
contract SiloDeployTest is IntegrationTest {
    // in case of new silo implementation, block number should be updated
    uint256 internal constant _FORKING_BLOCK_NUMBER = 22616413;

    ISiloConfig internal _siloConfig;
    ISiloDeployer internal _siloDeployer;
    SiloDeployWithDeployerOwner internal _siloDeploy;

    UniswapV3OracleFactoryMock internal _uniV3OracleFactoryMock;
    ChainlinkV3OracleFactoryMock internal _chainlinkV3OracleFactoryMock;
    DIAOracleFactoryMock internal _diaOracleFactoryMock;

    function setUp() public {
        vm.createSelectFork(getChainRpcUrl(MAINNET_ALIAS), _FORKING_BLOCK_NUMBER);

        _uniV3OracleFactoryMock = new UniswapV3OracleFactoryMock();
        _chainlinkV3OracleFactoryMock = new ChainlinkV3OracleFactoryMock();
        _diaOracleFactoryMock = new DIAOracleFactoryMock();

        _mockOraclesFactories();

        Deployments.disableDeploymentsSync();

        MainnetDeploy mainnetDeploy = new MainnetDeploy();
        mainnetDeploy.run();

        _siloDeploy = new SiloDeployWithDeployerOwner();

        // Mock addresses for oracles configurations
        AddrLib.setAddress("CHAINLINK_PRIMARY_AGGREGATOR", makeAddr("Chainlink primary aggregator"));
        AddrLib.setAddress("CHAINLINK_SECONDARY_AGGREGATOR", makeAddr("Chainlink secondary aggregator"));
        AddrLib.setAddress("DIA_ORACLE_EXAMPLE", makeAddr("DIA oracle example"));

        _siloConfig = _siloDeploy.useConfig(_useConfig()).run();
    }

    /*
    AGGREGATOR=1INCH FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_hooks_are_initialized
    */
    function test_hooks_are_initialized() public view {
        (address silo0, address silo1) = _siloConfig.getSilos();

        _verifyHookReceiversForSilo(silo0);
        _verifyHookReceiversForSilo(silo1);
    }

    // AGGREGATOR=1INCH FOUNDRY_PROFILE=core_test forge test -vv --ffi -mt test_oracles_deploy
    function test_oracles_deploy() public view virtual {
        // solhint-disable-line func-name-mixedcase
        (, address silo1) = _siloConfig.getSilos();

        ISiloConfig.ConfigData memory siloConfig1 = _siloConfig.getConfig(silo1);

        assertEq(siloConfig1.solvencyOracle, _uniV3OracleFactoryMock.MOCK_ORACLE_ADDR(), "Invalid Uniswap oracle");

        // If maxLtv oracle is not set, fallback to solvency oracle
        assertEq(
            siloConfig1.maxLtvOracle,
            _uniV3OracleFactoryMock.MOCK_ORACLE_ADDR(),
            "Should have an Uniswap oracle as a fallback"
        );
    }

    // AGGREGATOR=1INCH FOUNDRY_PROFILE=core_test forge test --ffi --mt test_encodeCallWithSalt -vv
    function test_encodeCallWithSalt() public pure {
        // forge-lint: disable-next-line(asm-keccak256)
        bytes32 salt = keccak256(bytes("some string"));

        IChainlinkV3Oracle.ChainlinkV3DeploymentConfig memory config;

        bytes memory callDataForModification = abi.encodeCall(IChainlinkV3Factory.create, (config, bytes32(0)));
        bytes memory callDataExpected = abi.encodeCall(IChainlinkV3Factory.create, (config, salt));

        assembly {
            let pointer := add(add(callDataForModification, 0x20), sub(mload(callDataForModification), 0x20))
            mstore(pointer, salt)
        }

        assertEq(keccak256(callDataForModification), keccak256(callDataExpected), "failed to update the salt");
    }

    // AGGREGATOR=1INCH FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_siloConfig_and_hookReceiver_reorg
    function test_siloConfig_and_hookReceiver_reorg() public {
        Vm.Wallet memory wallet1 = vm.createWallet("eoa1");
        Vm.Wallet memory wallet2 = vm.createWallet("eoa2");

        uint256 snapshot = vm.snapshotState();

        ISiloConfig siloConfig1 =
            _siloDeploy.useConfig(SiloConfigsNames.SILO_FULL_CONFIG_TEST).usePrivateKey(wallet1.privateKey).run();

        (address silo0,) = siloConfig1.getSilos();

        ISiloConfig.ConfigData memory siloConfigData1 = siloConfig1.getConfig(silo0);

        vm.revertToState(snapshot);

        ISiloConfig siloConfig2 =
            _siloDeploy.useConfig(SiloConfigsNames.SILO_FULL_CONFIG_TEST).usePrivateKey(wallet2.privateKey).run();

        (silo0,) = siloConfig2.getSilos();

        ISiloConfig.ConfigData memory siloConfigData2 = siloConfig2.getConfig(silo0);

        assertNotEq(address(siloConfig1), address(siloConfig2), "Silo configs should be different");
        assertNotEq(siloConfigData1.hookReceiver, siloConfigData2.hookReceiver, "Hook receiver should be different");
    }

    function _verifyHookReceiversForSilo(address _silo) internal view {
        IHookReceiver hookReceiver = IHookReceiver(IShareToken(_silo).hookSetup().hookReceiver);

        assertNotEq(address(hookReceiver), address(0), "Hook receiver not initialized");

        address protectedShareToken;
        address collateralShareToken;
        address debtShareToken;

        (protectedShareToken, collateralShareToken, debtShareToken) = _siloConfig.getShareTokens(_silo);

        _verifyHookReceiverForToken(protectedShareToken);
        _verifyHookReceiverForToken(collateralShareToken);
        _verifyHookReceiverForToken(debtShareToken);
    }

    function _verifyHookReceiverForToken(address _token) internal view {
        IShareToken.HookSetup memory hookSetup = IShareToken(_token).hookSetup();

        assertNotEq(hookSetup.hookReceiver, address(0), "Hook receiver not initialized");
    }

    function _mockOraclesFactories() internal {
        AddrLib.setAddress(
            SiloOraclesFactoriesContracts.UNISWAP_V3_ORACLE_FACTORY, address(_uniV3OracleFactoryMock)
        );
    }

    function _useConfig() internal virtual pure returns (string memory) {
        return SiloConfigsNames.SILO_FULL_CONFIG_TEST;
    }
}
