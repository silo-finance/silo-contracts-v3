// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ManualLiquidationHelper} from "silo-core/contracts/utils/liquidationHelper/ManualLiquidationHelper.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

abstract contract ManualLiquidationHelperCommon is SiloLittleHelper, Test {
    address payable private constant TOKENS_RECEIVER = payable(address(123));

    address constant BORROWER = address(0x123);
    uint256 constant COLLATERAL = 10e18;
    uint256 constant DEBT = 7.5e18;

    ManualLiquidationHelper immutable LIQUIDATION_HELPER;

    ISiloConfig siloConfig;

    address _debtAsset;

    constructor() {
        LIQUIDATION_HELPER = new ManualLiquidationHelper(makeAddr("nativeToken"), _tokenReceiver());
        LIQUIDATION_HELPER.grantRole({role: LIQUIDATION_HELPER.ALLOWED_ROLE(), account: address(this)});
    }

    function _executeLiquidation() internal virtual {
        LIQUIDATION_HELPER.executeLiquidation(silo1, BORROWER);
    }

    function _tokenReceiver() internal virtual returns (address payable) {
        return TOKENS_RECEIVER;
    }

    function _assertAddressDoesNotHaveTokens(address _address) internal view {
        assertEq(token0.balanceOf(_address), 0, "token0.balanceOf");
        assertEq(token1.balanceOf(_address), 0, "token1.balanceOf");

        _assertAddressHasNoSTokens(silo0, _address);
        _assertAddressHasNoSTokens(silo1, _address);
    }

    function _assertAddressHasSTokens(ISilo _silo, address _address) internal view {
        (address protectedShareToken, address collateralShareToken,) = siloConfig.getShareTokens(address(_silo));

        uint256 pBalance = IERC20(protectedShareToken).balanceOf(_address);
        uint256 cBalance = IERC20(collateralShareToken).balanceOf(_address);

        assertGt(pBalance + cBalance, 0, "expect TOKENS_RECEIVER has sTokens");
    }

    function _assertAddressHasNoSTokens(ISilo _silo, address _address) internal view {
        (address protectedShareToken, address collateralShareToken, address debtShareToken) =
            siloConfig.getShareTokens(address(_silo));

        uint256 pBalance = IERC20(protectedShareToken).balanceOf(_address);
        uint256 cBalance = IERC20(collateralShareToken).balanceOf(_address);
        uint256 dBalance = IERC20(debtShareToken).balanceOf(_address);

        assertEq(pBalance, 0, "expect `_address` has NO collateral sTokens");
        assertEq(cBalance, 0, "expect `_address` has NO protected sTokens");
        assertEq(dBalance, 0, "expect `_address` has NO debt sTokens");
    }
}
