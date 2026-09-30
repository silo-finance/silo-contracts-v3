// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Ownable} from "openzeppelin5/access/Ownable.sol";

import {
    DynamicKinkModel, IDynamicKinkModel
} from "../../../../contracts/interestRateModel/kink/DynamicKinkModel.sol";
import {IDynamicKinkModelConfig} from "../../../../contracts/interestRateModel/kink/DynamicKinkModelConfig.sol";
import {DynamicKinkModelFactory} from "../../../../contracts/interestRateModel/kink/DynamicKinkModelFactory.sol";

import {DynamicKinkModelMock} from "./DynamicKinkModelMock.sol";
import {KinkCommonTest} from "./KinkCommon.t.sol";

/* 
FOUNDRY_PROFILE=core_test forge test --mc DynamicKinkModelTimelockTest -vv
*/
contract DynamicKinkModelTimelockTest is KinkCommonTest {
    address silo = address(this);

    function setUp() public {
        vm.warp(100);

        IDynamicKinkModel.Config memory emptyConfig;
        IDynamicKinkModel.ImmutableArgs memory immutableArgs =
            IDynamicKinkModel.ImmutableArgs({timelock: 1 days, rcompCap: 1});

        irm = DynamicKinkModel(address(FACTORY.create(emptyConfig, immutableArgs, address(this), silo, bytes32(0))));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_initialConfig_isActivatedImmediately -vv
    */
    function test_kink_initialConfig_isActivatedImmediately() public {
        assertEq(_getIRMImmutableConfig(irm).timelock, 1 days, "expect timelock for this test");

        assertEq(irm.activateConfigAt(), block.timestamp, "activateConfigAt should be equal to tx timestamp");
        assertEq(irm.pendingIrmConfig(), address(0), "there should be no pending config");

        // there should be nothing to cancel
        vm.expectRevert(IDynamicKinkModel.NoPendingUpdateToCancel.selector);
        irm.cancelPendingUpdateConfig();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_timelock_revert -vv
    */
    function test_kink_timelock_revert() public {
        IDynamicKinkModel.Config memory config;
        IDynamicKinkModel.ImmutableArgs memory immutableArgs =
            IDynamicKinkModel.ImmutableArgs({timelock: 7 days + 1, rcompCap: 1});

        vm.expectRevert(IDynamicKinkModel.InvalidTimelock.selector);
        FACTORY.create(config, immutableArgs, address(this), silo, bytes32(0));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_pendingUpdateConfig_pass -vv
    */
    function test_kink_pendingUpdateConfig_pass() public {
        IDynamicKinkModel.Config memory activeCfg = _getIRMConfig(irm);

        IDynamicKinkModel.Config memory pendingCfg;
        pendingCfg.ucrit = activeCfg.ucrit + 1; // make sure new config is different
        pendingCfg.kmin = activeCfg.kmin + 1; // make sure new config is different
        pendingCfg.kmax = activeCfg.kmax + 1; // make sure new config is different

        address activeIrmConfig = address(irm.irmConfig());

        vm.expectEmit(false, false, false, false);
        emit IDynamicKinkModel.NewConfig(IDynamicKinkModelConfig(address(0)), block.timestamp + 1 days);

        irm.updateConfig(pendingCfg);

        address pendingIrmConfig = irm.pendingIrmConfig();

        assertNotEq(pendingIrmConfig, address(0), "pendingIrmConfig exists");
        assertEq(irm.activateConfigAt(), block.timestamp + 1 days, "activateConfigAt is not correct");

        _assertModelCallsToActiveConfig(activeIrmConfig);

        vm.expectCall(pendingIrmConfig, abi.encodeWithSelector(IDynamicKinkModelConfig.getConfig.selector));
        irm.getModelStateAndConfig(true);

        vm.expectCall(pendingIrmConfig, abi.encodeWithSelector(IDynamicKinkModelConfig.getConfig.selector));
        irm.getPendingCurrentInterestRate(silo, block.timestamp);

        vm.expectCall(pendingIrmConfig, abi.encodeWithSelector(IDynamicKinkModelConfig.getConfig.selector));
        irm.getPendingCompoundInterestRate(silo, block.timestamp);

        IDynamicKinkModel.ModelState memory state = irm.modelState();
        assertEq(state.k, activeCfg.kmin, "modelState.k should return active k");

        (int96 activeK,) = irm.configsHistory(IDynamicKinkModelConfig(pendingIrmConfig));
        assertEq(activeK, activeCfg.kmin, "k in history is active, when pending config");

        (state,,) = irm.getModelStateAndConfig(true);
        assertEq(state.k, pendingCfg.kmin, "getModelStateAndConfig(true) return pending k");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_whenPendingKisUpdatedInHistory -vv
    */
    function test_kink_whenPendingKisUpdatedInHistory() public {
        DynamicKinkModelFactory f = new DynamicKinkModelFactory(new DynamicKinkModelMock());

        vm.warp(1000 days);

        IDynamicKinkModel.Config memory cfg = _defaultConfig();
        IDynamicKinkModel.ImmutableArgs memory immutableArgs = _defaultImmutableArgs();
        immutableArgs.timelock = 1 days;
        irm = DynamicKinkModel(address(f.create(cfg, immutableArgs, address(this), address(this), bytes32(0))));

        IDynamicKinkModel.Config memory pendingCfg = _defaultConfig();
        pendingCfg.kmin = cfg.kmin + 1;
        irm.updateConfig(pendingCfg);

        (IDynamicKinkModel.ModelState memory state,,) = irm.getModelStateAndConfig(true);
        assertEq(state.k, pendingCfg.kmin, "model state has pending k");

        (int96 historyK,) = irm.configsHistory(IDynamicKinkModelConfig(irm.pendingIrmConfig()));
        assertEq(historyK, cfg.kmin, "history has active k");

        (state,,) = irm.getModelStateAndConfig(false);
        assertEq(state.k, cfg.kmin, "(getModelStateAndConfig(false)) returns active k");

        // modify K in history and state to verify modification
        int96 mockedK = 321;
        DynamicKinkModelMock(address(irm)).mockHistoryK(mockedK);
        DynamicKinkModelMock(address(irm)).mockStateK(mockedK);

        assertTrue(irm.pendingConfigExists(), "must be pending config for this test");

        irm.getCompoundInterestRateAndUpdate({
            _collateralAssets: 1e18,
            _debtAssets: 0.5e18,
            _interestRateTimestamp: 0 // we will acctu for long perion, so I;m expecting overflow
        });

        (state,,) = irm.getModelStateAndConfig(true);
        assertEq(state.k, mockedK, "pending k is not updated");
        assertEq(irm.modelState().k, cfg.kmin, "modelState.k returns updated value");

        (historyK,) = irm.configsHistory(IDynamicKinkModelConfig(irm.pendingIrmConfig()));
        assertEq(historyK, cfg.kmin, "pending k is updated in history");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_pendingConfig_isActivatedAtTimelock -vv
    */
    function test_kink_pendingConfig_isActivatedAtTimelock() public {
        IDynamicKinkModel.Config memory config;
        config.ucrit = _getIRMConfig(irm).ucrit + 1; // make sure new config is different
        config.kmin = _getIRMConfig(irm).kmin + 1; // make sure new config is different
        config.kmax = _getIRMConfig(irm).kmax + 1; // make sure new config is different

        address prevIrmConfig = address(irm.irmConfig());

        irm.updateConfig(config);

        address pendingIrmConfig = irm.pendingIrmConfig();

        _assertCorrectHistory(IDynamicKinkModelConfig(pendingIrmConfig), IDynamicKinkModelConfig(prevIrmConfig));

        vm.warp(block.timestamp + 1 days);

        // QA

        vm.expectRevert(IDynamicKinkModel.NoPendingUpdateToCancel.selector);
        irm.cancelPendingUpdateConfig();

        assertEq(irm.pendingIrmConfig(), address(0), "pendingIrmConfig should be 0 at this point");
        assertEq(irm.activateConfigAt(), block.timestamp, "activateConfigAt should be equal to block.timestamp");

        _assertModelCallsToActiveConfig(pendingIrmConfig);

        IDynamicKinkModel.ModelState memory state = irm.modelState();
        assertEq(state.k, config.kmin, "modelState.k should return active k");

        (int96 activeK,) = irm.configsHistory(IDynamicKinkModelConfig(pendingIrmConfig));
        assertEq(activeK, config.kmin - 1, "k in history is lastactive k");
    }

    /*
        FOUNDRY_PROFILE=core_test forge test --mt test_kink_cancelPendingUpdateConfig_onlyOwner -vv
    */
    function test_kink_cancelPendingUpdateConfig_onlyOwner() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(1)));

        irm.cancelPendingUpdateConfig();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_cancelPendingUpdateConfig_pass -vv
    */
    function test_kink_cancelPendingUpdateConfig_pass() public {
        IDynamicKinkModel.Config memory config;
        config.ucrit = _getIRMConfig(irm).ucrit + 1; // make sure new config is different

        address prevIrmConfig = address(irm.irmConfig());

        vm.expectEmit(false, false, false, false);
        emit IDynamicKinkModel.NewConfig(IDynamicKinkModelConfig(address(0)), block.timestamp + 1 days);

        irm.updateConfig(config);
        vm.warp(block.timestamp + 1 days - 1);

        irm.cancelPendingUpdateConfig();

        assertEq(irm.pendingIrmConfig(), address(0), "pendingIrmConfig should be 0 at this point");
        assertEq(irm.activateConfigAt(), 0, "activateConfigAt should be reset to 0");

        _assertModelCallsToActiveConfig(prevIrmConfig);

        _assertCorrectHistory(IDynamicKinkModelConfig(prevIrmConfig), IDynamicKinkModelConfig(address(0)));
    }

    function _assertModelCallsToActiveConfig(address _irmConfig) internal {
        assertEq(address(irm.irmConfig()), _irmConfig, "undexpected irm.irmConfig()");

        // expect calls to _irmConfig

        vm.expectCall(_irmConfig, abi.encodeWithSelector(IDynamicKinkModelConfig.getConfig.selector));
        irm.getModelStateAndConfig(false);

        vm.expectCall(_irmConfig, abi.encodeWithSelector(IDynamicKinkModelConfig.getConfig.selector));
        irm.getCompoundInterestRate(silo, block.timestamp);

        vm.expectCall(_irmConfig, abi.encodeWithSelector(IDynamicKinkModelConfig.getConfig.selector));
        irm.getCurrentInterestRate(silo, block.timestamp);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_pendingConfigExists -vv
    */
    function test_kink_pendingConfigExists() public {
        IDynamicKinkModel.Config memory cfg;

        assertFalse(irm.pendingConfigExists(), "pendingConfigExists should be false at beginning");

        irm.updateConfig(cfg);
        assertTrue(irm.pendingConfigExists(), "pendingConfigExists should be true when update is called");

        irm.cancelPendingUpdateConfig();
        assertFalse(irm.pendingConfigExists(), "pendingConfigExists should be false after cancel");

        irm.updateConfig(cfg);
        vm.warp(block.timestamp + 1 days - 1);
        assertTrue(irm.pendingConfigExists(), "pendingConfigExists should be true before timelock");

        vm.warp(block.timestamp + 1);
        assertFalse(irm.pendingConfigExists(), "pendingConfigExists should be FALSE after timelock");
    }
}
