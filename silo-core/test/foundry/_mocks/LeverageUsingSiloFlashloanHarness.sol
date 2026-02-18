pragma solidity 0.8.28;

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ILeverageUsingSiloFlashloan} from "silo-core/contracts/interfaces/ILeverageUsingSiloFlashloan.sol";
import {LeverageUsingSiloFlashloanWithGeneralSwap} from
    "silo-core/contracts/leverage/LeverageUsingSiloFlashloanWithGeneralSwap.sol";

contract LeverageUsingSiloFlashloanHarness is LeverageUsingSiloFlashloanWithGeneralSwap {
    constructor(address _router, address _native) LeverageUsingSiloFlashloanWithGeneralSwap(_router, _native) {}

    function setTxData(
        address _msgSender,
        ISiloConfig _siloConfig,
        ILeverageUsingSiloFlashloan.LeverageAction _action,
        address _flashloanTarget,
        uint256 _msgValue
    ) external {
        _txMsgSender = _msgSender;
        _txSiloConfig = _siloConfig;
        _txAction = _action;
        _txFlashloanTarget = _flashloanTarget;
        _txMsgValue = _msgValue;
    }
}
