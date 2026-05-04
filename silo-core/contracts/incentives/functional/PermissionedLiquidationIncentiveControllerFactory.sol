// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Ownable} from "openzeppelin5/access/Ownable.sol";

import {
    IPermissionedLiquidationIncentiveControllerFactory
} from "silo-core/contracts/interfaces/IPermissionedLiquidationIncentiveControllerFactory.sol";
import {
    PermissionedLiquidationIncentiveController
} from "silo-core/contracts/incentives/functional/PermissionedLiquidationIncentiveController.sol";
import {TransparentProxy} from "silo-core/contracts/utils/TransparentProxy.sol";

import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";

/// @notice Minimal factory for upgradeable PermissionedLiquidationIncentiveController proxies.
contract PermissionedLiquidationIncentiveControllerFactory is IPermissionedLiquidationIncentiveControllerFactory, IVersioned {
    /// @dev Implementation used by all created proxies.
    address public immutable IMPLEMENTATION;

    mapping(address => bool) public isSiloIncentivesController;

    constructor() {
        IMPLEMENTATION = address(new PermissionedLiquidationIncentiveController());
    }

    /// @inheritdoc IPermissionedLiquidationIncentiveControllerFactory
    // TODO if we will only set this for silo sha token, then we don;t need dotifier to pass as input
    // do we need another way? eg notifier to be share token??
    function create(IShareToken _shareToken) external returns (address controller) {
        //TODO salt?
        address proxyAdminOwner = Ownable(_shareToken.hookReceiver()).owner();
        bytes memory initData = abi.encodeCall(PermissionedLiquidationIncentiveController.initialize, (_shareToken));

        controller = address(new TransparentProxy(IMPLEMENTATION, proxyAdminOwner, initData));

        isSiloIncentivesController[controller] = true;

        emit PermissionedLiquidationIncentiveControllerCreated(controller, address(_shareToken));
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure override returns (string memory) {
        return "PermissionedLiquidationIncentiveControllerFactory 4.12.0";
    }
}
