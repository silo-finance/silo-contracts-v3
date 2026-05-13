// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IHookReceiver} from "silo-core/contracts/interfaces/IHookReceiver.sol";

import {GaugeHookReceiver} from "silo-core/contracts/hooks/gauge/GaugeHookReceiver.sol";
import {PartialLiquidation} from "silo-core/contracts/hooks/liquidation/PartialLiquidation.sol";
import {BaseHookReceiver} from "silo-core/contracts/hooks/_common/BaseHookReceiver.sol";

contract SiloHookV1 is GaugeHookReceiver, PartialLiquidation {
    /// @inheritdoc IHookReceiver
    function initialize(ISiloConfig _config, bytes calldata _data)
        public
        initializer
        virtual
    {
        (address owner) = abi.decode(_data, (address));

        BaseHookReceiver.__BaseHookReceiver_init(_config);
        GaugeHookReceiver.__GaugeHookReceiver_init(owner);
        PartialLiquidation.__PartialLiquidation_init(owner);
    }

    /// @inheritdoc IHookReceiver
    function beforeAction(address, uint256, bytes calldata)
        public
        virtual
        onlySilo()
        override
    {
        // Do not expect any actions.
        revert RequestNotSupported();
    }

    /// @inheritdoc IHookReceiver
    function afterAction(address _silo, uint256 _action, bytes calldata _inputAndOutput)
        public
        virtual
        onlySiloOrShareToken()
        override(GaugeHookReceiver, IHookReceiver)
    {
        GaugeHookReceiver.afterAction(_silo, _action, _inputAndOutput);
    }
}
