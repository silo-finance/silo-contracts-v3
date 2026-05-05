// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {Ownable1and2Steps} from "common/access/Ownable1and2Steps.sol";

contract HookReceiverBootstrapMock is Ownable1and2Steps {
    constructor() Ownable1and2Steps(msg.sender) {}

    function initialize(ISiloConfig, bytes calldata) external virtual {
        if (owner() == address(0)) _transferOwnership(msg.sender);
    }

    function hookReceiverConfig(address) external view virtual returns (uint24 hooksBefore, uint24 hooksAfter) {
        return (0, 0);
    }

    function LIQUIDATION_LOGIC() external pure virtual returns (address) {
        return address(0);
    }

    function setGauge(address, address) external pure virtual {}

    function removeGauge(address) external pure virtual {}

    function configuredGauges(address) external pure virtual returns (address) {
        return address(0);
    }

    function transferOwnership1Step(address newOwner) public virtual override {
        if (newOwner == address(0)) return;
        _transferOwnership(newOwner);
    }
}
