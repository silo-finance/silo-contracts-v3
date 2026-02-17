// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {Clones} from "openzeppelin5/proxy/Clones.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";

import {SiloHookV2} from "silo-core/contracts/hooks/SiloHookV2.sol";

abstract contract CloneHookV2 is Test {
    ISiloConfig siloConfig = ISiloConfig(makeAddr("siloConfig"));
    address silo0 = makeAddr("silo0");
    address silo1 = makeAddr("silo1");

    address collateralShareToken = silo0;
    address protectedShareToken = makeAddr("protectedShareToken");
    address debtShareToken = makeAddr("debtShareToken");

    SiloHookV2 defaulting;

    function _cloneHook(ISiloConfig.ConfigData memory _config0, ISiloConfig.ConfigData memory _config1)
        internal
        returns (SiloHookV2 hook)
    {
        SiloHookV2 implementation = new SiloHookV2();
        hook = SiloHookV2(Clones.clone(address(implementation)));

        _mockSiloConfig(_config0, _config1);

        hook.initialize(siloConfig, abi.encode(address(this)));
    }

    function _mockGetShareTokens() internal {
        vm.mockCall(
            address(siloConfig),
            abi.encodeWithSelector(ISiloConfig.getShareTokens.selector, silo0),
            abi.encode(protectedShareToken, collateralShareToken, debtShareToken)
        );

        vm.mockCall(
            address(siloConfig),
            abi.encodeWithSelector(ISiloConfig.getShareTokens.selector, silo1),
            abi.encode(
                makeAddr("protectedShareToken1"), makeAddr("collateralShareToken1"), makeAddr("debtShareToken1")
            )
        );
    }

    function _mockSiloConfig(ISiloConfig.ConfigData memory _config0, ISiloConfig.ConfigData memory _config1)
        internal
    {
        vm.mockCall(
            address(siloConfig), abi.encodeWithSelector(ISiloConfig.getSilos.selector), abi.encode(silo0, silo1)
        );

        vm.mockCall(
            address(siloConfig), abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo0), abi.encode(_config0)
        );

        vm.mockCall(
            address(siloConfig), abi.encodeWithSelector(ISiloConfig.getConfig.selector, silo1), abi.encode(_config1)
        );

        vm.mockCall(collateralShareToken, abi.encodeWithSelector(IShareToken.silo.selector), abi.encode(silo0));

        vm.mockCall(protectedShareToken, abi.encodeWithSelector(IShareToken.silo.selector), abi.encode(silo0));

        vm.mockCall(debtShareToken, abi.encodeWithSelector(IShareToken.silo.selector), abi.encode(silo0));
    }
}
