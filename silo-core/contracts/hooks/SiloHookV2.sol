// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IHookReceiver} from "silo-core/contracts/interfaces/IHookReceiver.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";

import {GaugeHookReceiver} from "silo-core/contracts/hooks/gauge/GaugeHookReceiver.sol";
import {PartialLiquidationByDefaulting} from "silo-core/contracts/hooks/defaulting/PartialLiquidationByDefaulting.sol";
import {BaseHookReceiver} from "silo-core/contracts/hooks/_common/BaseHookReceiver.sol";

contract SiloHookV2 is GaugeHookReceiver, PartialLiquidationByDefaulting, IVersioned {
    function VERSION() external pure virtual returns (string memory) { // solhint-disable-line func-name-mixedcase
        return "SiloHookV2 4.4.0";
    }

    /// @inheritdoc IHookReceiver
    function initialize(ISiloConfig _config, bytes calldata _data) public virtual initializer {
        (address owner) = abi.decode(_data, (address));

        BaseHookReceiver.__BaseHookReceiver_init(_config);
        GaugeHookReceiver.__GaugeHookReceiver_init(owner);
        PartialLiquidationByDefaulting.__PartialLiquidationByDefaulting_init(owner);
    }

    /// @inheritdoc IHookReceiver
    function beforeAction(address, uint256, bytes calldata) public virtual override onlySilo {
        // Do not expect any actions.
        revert RequestNotSupported();
    }

    /// @inheritdoc IHookReceiver
    function afterAction(address _silo, uint256 _action, bytes calldata _inputAndOutput)
        public
        virtual
        override(GaugeHookReceiver, IHookReceiver)
        onlySiloOrShareToken
    {
        GaugeHookReceiver.afterAction(_silo, _action, _inputAndOutput);
    }
}
