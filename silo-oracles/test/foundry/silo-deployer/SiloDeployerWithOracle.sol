// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {console2} from "forge-std/console2.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";

import {SiloCoreContracts, SiloCoreDeployments} from "silo-core/common/SiloCoreContracts.sol";
import {MainnetDeploy} from "silo-core/deploy/MainnetDeploy.s.sol";
import {SiloConfigData} from "silo-core/deploy/input-readers/SiloConfigData.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISiloDeployer} from "silo-core/contracts/interfaces/ISiloDeployer.sol";
import {SiloDeployer} from "silo-core/contracts/SiloDeployer.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {MintableToken} from "silo-core/test/foundry/_common/MintableToken.sol";

import {DKinkIRMConfigDataReader} from "silo-core/deploy/input-readers/DKinkIRMConfigDataReader.sol";
import {DKinkIRMConfigData} from "silo-core/deploy/input-readers/DKinkIRMConfigData.sol";
import {IDynamicKinkModel} from "silo-core/contracts/interfaces/IDynamicKinkModel.sol";

/*
    FOUNDRY_PROFILE=oracles forge test --mc CustomMethodOracleSiloDeployIntegrationTest --ffi -vv
*/
abstract contract SiloDeployerWithOracle is Test, DKinkIRMConfigDataReader {
    MintableToken token0;
    MintableToken token1;

    ISiloDeployer internal siloDeployer;

    ISiloConfig siloConfig;

    ISiloOracle siloOracle;

    function setUp() public virtual {
        AddrLib.init();
        _deploySiloCoreWithSiloDeployer();
        _deployOracleFactory();

        token0 = new MintableToken(6);
        token1 = new MintableToken(18);

        siloDeployer = _resolveSiloDeployer();
    }

    function _deployOracleFactory() internal virtual;

    function _oracleTxData() internal virtual returns (ISiloDeployer.OracleCreationTxData memory txData);

    function _deployMarket() internal {
        (
            ISiloConfig.InitData memory siloInitData,
            bytes memory irmConfigData0,
            bytes memory irmConfigData1,
            address hookImpl
        ) = _localInitData();

        ISiloDeployer.Oracles memory oracles;
        oracles.solvencyOracle0 = _oracleTxData();

        console2.log("[SiloCommonDeploy] siloInitData.token0", siloInitData.token0);
        console2.log("[SiloCommonDeploy] siloInitData.token1", siloInitData.token1);
        console2.log("[SiloCommonDeploy] hookReceiverImplementation", hookImpl);

        ISiloDeployer.ClonableHookReceiver memory hookReceiver = ISiloDeployer.ClonableHookReceiver({
            implementation: hookImpl, initializationData: abi.encode(address(this))
        });

        siloConfig = siloDeployer.deploy({
            _oracles: oracles,
            _irmConfigData0: irmConfigData0,
            _irmConfigData1: irmConfigData1,
            _clonableHookReceiver: hookReceiver,
            _siloInitData: siloInitData
        });

        (address silo0,) = siloConfig.getSilos();
        siloOracle = ISiloOracle(siloConfig.getConfig(silo0).solvencyOracle);
    }

    function _localInitData()
        internal
        returns (
            ISiloConfig.InitData memory initData,
            bytes memory irmConfigData0,
            bytes memory irmConfigData1,
            address hookImpl
        )
    {
        SiloConfigData siloConfigData = new SiloConfigData();
        (, initData, hookImpl) = siloConfigData.getConfigData("Silo_Kink");
        initData.token0 = address(token0);
        initData.token1 = address(token1);

        initData.liquidationTargetLtv1 = 0;
        initData.lt1 = 0;
        initData.maxLtv1 = 0;
        initData.liquidationFee1 = 0;

        irmConfigData0 = _prepareDKinkIRMConfig("static-2.4-6:T1day_C200");
        irmConfigData1 = _prepareDKinkIRMConfig("static-2.4-6:T1day_C200");
    }

    function _prepareDKinkIRMConfig(string memory _configName) internal returns (bytes memory irmConfigData) {
        DKinkIRMConfigData dkinkIRMModelData = new DKinkIRMConfigData();

        (IDynamicKinkModel.Config memory dkinkIRMConfigData, IDynamicKinkModel.ImmutableArgs memory immutableArgs) =
            dkinkIRMModelData.getConfigData(_configName);

        ISiloDeployer.DKinkIRMConfig memory dkinkIRMConfig = ISiloDeployer.DKinkIRMConfig({
            config: dkinkIRMConfigData, immutableArgs: immutableArgs, initialOwner: address(this)
        });

        irmConfigData = abi.encode(dkinkIRMConfig);
    }

    function _resolveSiloDeployer() internal returns (SiloDeployer deployer) {
        address siloDeployerAddr = SiloCoreDeployments.get(SiloCoreContracts.SILO_DEPLOYER, ChainsLib.chainAlias());
        deployer = SiloDeployer(siloDeployerAddr);
    }

    function _deploySiloCoreWithSiloDeployer() internal {
        MainnetDeploy mainnetDeploy = new MainnetDeploy();
        mainnetDeploy.disableDeploymentsSync();
        mainnetDeploy.run();
    }
}
