// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {LiquidationCallByDefaultingReentrancyTest} from
    "../methods/silo-hook-v2/LiquidationCallByDefaultingReentrancyTest.sol";

import {GetRoleAdminReentrancyTest} from "../methods/leverage/GetRoleAdminReentrancyTest.sol";
import {GrantRoleReentrancyTest} from "../methods/leverage/GrantRoleReentrancyTest.sol";
import {HasRoleReentrancyTest} from "../methods/leverage/HasRoleReentrancyTest.sol";
import {RenounceRoleReentrancyTest} from "../methods/leverage/RenounceRoleReentrancyTest.sol";
import {RevokeRoleReentrancyTest} from "../methods/leverage/RevokeRoleReentrancyTest.sol";
import {SupportsInterfaceReentrancyTest} from "../methods/leverage/SupportsInterfaceReentrancyTest.sol";
import {AllowedRoleReentrancyTest} from "../methods/silo-hook-v2/AllowedRoleReentrancyTest.sol";
import {DefaultAdminRoleReentrancyTest} from "../methods/silo-hook-v2/DefaultAdminRoleReentrancyTest.sol";
import {KeeperFeeReentrancyTest} from "../methods/silo-hook-v2/KeeperFeeReentrancyTest.sol";
import {LiquidationLogicReentrancyTest} from "../methods/silo-hook-v2/LiquidationLogicReentrancyTest.sol";
import {LtMarginForDefaultingReentrancyTest} from "../methods/silo-hook-v2/LtMarginForDefaultingReentrancyTest.sol";
import {GetKeeperAndLenderSharesSplitReentrancyTest} from
    "../methods/silo-hook-v2/GetKeeperAndLenderSharesSplitReentrancyTest.sol";
import {ValidateControllerForCollateralReentrancyTest} from
    "../methods/silo-hook-v2/ValidateControllerForCollateralReentrancyTest.sol";
import {GetRoleMemberReentrancyTest} from "../methods/silo-hook-v2/GetRoleMemberReentrancyTest.sol";
import {GetRoleMemberCountReentrancyTest} from "../methods/silo-hook-v2/GetRoleMemberCountReentrancyTest.sol";
import {GetRoleMembersReentrancyTest} from "../methods/silo-hook-v2/GetRoleMembersReentrancyTest.sol";
import {ValidateDefaultingCollateralReentrancyTest} from
    "../methods/silo-hook-v2/ValidateDefaultingCollateralReentrancyTest.sol";
import {VersionReentrancyTest} from "../methods/silo-hook-v2/VersionReentrancyTest.sol";

import {SiloHookV1MethodsRegistry} from "./SiloHookV1MethodsRegistry.sol";

contract SiloHookV2MethodsRegistry is SiloHookV1MethodsRegistry {
    constructor() {
        _registerMethod(new LiquidationCallByDefaultingReentrancyTest());
        _registerMethod(new GetRoleAdminReentrancyTest());
        _registerMethod(new GrantRoleReentrancyTest());
        _registerMethod(new HasRoleReentrancyTest());
        _registerMethod(new RenounceRoleReentrancyTest());
        _registerMethod(new RevokeRoleReentrancyTest());
        _registerMethod(new SupportsInterfaceReentrancyTest());

        _registerMethod(new AllowedRoleReentrancyTest());
        _registerMethod(new DefaultAdminRoleReentrancyTest());
        _registerMethod(new KeeperFeeReentrancyTest());
        _registerMethod(new LiquidationLogicReentrancyTest());
        _registerMethod(new LtMarginForDefaultingReentrancyTest());
        _registerMethod(new GetRoleMemberReentrancyTest());
        _registerMethod(new GetRoleMemberCountReentrancyTest());
        _registerMethod(new GetRoleMembersReentrancyTest());

        _registerMethod(new GetKeeperAndLenderSharesSplitReentrancyTest());
        _registerMethod(new ValidateControllerForCollateralReentrancyTest());
        _registerMethod(new ValidateDefaultingCollateralReentrancyTest());
        _registerMethod(new VersionReentrancyTest());
    }

    function abiFile() external pure override returns (string memory) {
        return "/cache/foundry/out/silo-core/SiloHookV2.sol/SiloHookV2.json";
    }
}
