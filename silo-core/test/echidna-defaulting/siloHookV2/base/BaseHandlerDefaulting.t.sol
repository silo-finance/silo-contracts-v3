// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {console2} from "forge-std/console2.sol";

// Interfaces
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {Strings} from "openzeppelin5/utils/Strings.sol";
import {BaseHandler} from "silo-core/test/invariants/base/BaseHandler.t.sol";
import {DefaultBeforeAfterHooks} from "silo-core/test/invariants/hooks/DefaultBeforeAfterHooks.t.sol";

/// @title BaseHandler
/// @notice Contains common logic for all handlers
/// @dev inherits all suite assertions since per action assertions are implmenteds in the handlers
contract BaseHandlerDefaulting is BaseHandler {
    function _getOtherSilo(address _silo) internal view returns (address otherSilo) {
        (address silo0, address silo1) = ISilo(_silo).config().getSilos();
        otherSilo = silo0 == _silo ? silo1 : silo0;
    }

    function _defaultHooksBefore(address silo) internal virtual override {
        super._defaultHooksBefore(silo);

        address actor = _getRandomActor(0);
        rewardsBalanceBefore[actor] = gauge.getRewardsBalance(actor, _getImmediateProgramNames());
    }

    // function _defaultHooksAfter(address silo) internal override {
    //     super._defaultHooksAfter(silo);
    // }

    function _getProgramNames() internal view returns (string[] memory names) {
        names = new string[](2);
        names[0] = Strings.toHexString(address(vault0));

        (address protectedShareToken,,) = siloConfig.getShareTokens(address(vault0));
        names[1] = Strings.toHexString(protectedShareToken);
    }

    function _printBalances(ISilo _silo, address _user) internal view {
        (address protectedShareToken, address collateralShareToken, address debtShareToken) =
            _silo.config().getShareTokens(address(_silo));

        string memory userLabel = vm.getLabel(_user);

        uint256 balance = IShareToken(collateralShareToken).balanceOf(_user);
        console2.log("%s.balanceOf(%s)", vm.getLabel(collateralShareToken), userLabel, balance);
        uint256 assets = _silo.previewRedeem(balance);
        console2.log("\tbalance to assets", assets);
        console2.log("\tback to shares", _silo.convertToShares(assets));

        balance = IShareToken(protectedShareToken).balanceOf(_user);
        console2.log("%s.balanceOf(%s)", vm.getLabel(protectedShareToken), userLabel, balance);
        assets = _silo.previewRedeem(balance, ISilo.CollateralType.Protected);
        console2.log("\tbalance to assets", assets);
        console2.log("\tback to shares", _silo.convertToShares(assets, ISilo.AssetType.Protected));

        balance = IShareToken(debtShareToken).balanceOf(_user);
        console2.log("%s.balanceOf(%s)", vm.getLabel(debtShareToken), userLabel, balance);
        console2.log("\tbalance to assets", _silo.convertToAssets(balance, ISilo.AssetType.Debt));
    }

    function _printLtv(address _user) internal returns (uint256 ltv) {
        try siloLens.getLtv(vault0, _user) returns (uint256 _ltv) {
            ltv = _ltv;
            emit log_named_decimal_uint(string.concat(vm.getLabel(_user), " LTV [%]"), ltv, 16);
        } catch {
            console2.log("\t[_printLtv] getLtv failed");
        }
    }

    function _printMaxLiquidation(address _user) internal view {
        (uint256 collateralToLiquidate, uint256 debtToRepay,) = liquidationModule.maxLiquidation(_user);
        console2.log("maxLiquidation: collateralToLiquidate", collateralToLiquidate);
        console2.log("maxLiquidation: debtToRepay", debtToRepay);
    }
}
