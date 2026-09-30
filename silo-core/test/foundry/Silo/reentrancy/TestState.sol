// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Utils} from "silo-foundry-utils/lib/Utils.sol";
import {VmLib} from "silo-foundry-utils/lib/VmLib.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";

contract ReentrancyTestState {
    address public siloConfig;
    address public silo0;
    address public silo1;
    address public token0;
    address public token1;
    address public hookReceiver;
    address public leverageRouter;
    bool public reenter = true;
    bool public reenterViaLiquidationCall = false;
    bool public leverageReenter = true;

    function set(
        address _siloConfig,
        address _silo0,
        address _silo1,
        address _token0,
        address _token1,
        address _hookReceiver,
        address _leverageRouter
    ) external {
        siloConfig = _siloConfig;
        silo0 = _silo0;
        silo1 = _silo1;
        token0 = _token0;
        token1 = _token1;
        hookReceiver = _hookReceiver;
        leverageRouter = _leverageRouter;
    }

    function setReenter(bool _status) external {
        reenter = _status;
    }

    function setReenterViaLiquidationCall(bool _status) external {
        reenterViaLiquidationCall = _status;
    }

    function setLeverageReenter(bool _status) external {
        leverageReenter = _status;
    }
}

library TestStateLib {
    address internal constant _ADDRESS = address(uint160(uint256(keccak256("silo reentrancy test"))));

    function init(
        address _siloConfig,
        address _silo0,
        address _silo1,
        address _token0,
        address _token1,
        address _hookReceiver,
        address _leverageRouter
    ) internal {
        bytes memory code = Utils.getCodeAt(_ADDRESS);

        if (code.length != 0) return;

        ReentrancyTestState state = new ReentrancyTestState();

        bytes memory deployedCode = Utils.getCodeAt(address(state));

        VmLib.vm().etch(_ADDRESS, deployedCode);

        ReentrancyTestState(_ADDRESS).set(
            _siloConfig, _silo0, _silo1, _token0, _token1, _hookReceiver, _leverageRouter
        );
        ReentrancyTestState(_ADDRESS).setReenter(true);
        ReentrancyTestState(_ADDRESS).setLeverageReenter(false);
    }

    function silo0() internal view returns (ISilo) {
        return ISilo(ReentrancyTestState(_ADDRESS).silo0());
    }

    function silo1() internal view returns (ISilo) {
        return ISilo(ReentrancyTestState(_ADDRESS).silo1());
    }

    function token0() internal view returns (address) {
        return ReentrancyTestState(_ADDRESS).token0();
    }

    function token1() internal view returns (address) {
        return ReentrancyTestState(_ADDRESS).token1();
    }

    function siloConfig() internal view returns (ISiloConfig) {
        return ISiloConfig(ReentrancyTestState(_ADDRESS).siloConfig());
    }

    function hookReceiver() internal view returns (address) {
        return ReentrancyTestState(_ADDRESS).hookReceiver();
    }

    function leverageRouter() internal view returns (address) {
        return ReentrancyTestState(_ADDRESS).leverageRouter();
    }

    function reenter() internal view returns (bool) {
        return ReentrancyTestState(_ADDRESS).reenter();
    }

    function disableReentrancy() internal {
        ReentrancyTestState(_ADDRESS).setReenter(false);
    }

    function enableReentrancy() internal {
        ReentrancyTestState(_ADDRESS).setReenter(true);
    }

    function setReenterViaLiquidationCall(bool _status) internal {
        ReentrancyTestState(_ADDRESS).setReenterViaLiquidationCall(_status);
    }

    function reenterViaLiquidationCall() internal view returns (bool) {
        return ReentrancyTestState(_ADDRESS).reenterViaLiquidationCall();
    }

    function leverageReenter() internal view returns (bool) {
        return ReentrancyTestState(_ADDRESS).leverageReenter();
    }

    function disableLeverageReentrancy() internal {
        ReentrancyTestState(_ADDRESS).setLeverageReenter(false);
    }

    function enableLeverageReentrancy() internal {
        ReentrancyTestState(_ADDRESS).setLeverageReenter(true);
    }
}
