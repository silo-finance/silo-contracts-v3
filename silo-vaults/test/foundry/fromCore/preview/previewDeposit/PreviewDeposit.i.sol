// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {VaultsLittleHelper} from "../../_common/VaultsLittleHelper.sol";

/*
    forge test -vv --ffi --mc PreviewDepositTest
*/
contract PreviewDepositTest is VaultsLittleHelper {
    address immutable DEPOSITOR;

    constructor() {
        DEPOSITOR = makeAddr("Depositor");
    }

    /*
    forge test -vv --ffi --mt test_previewDeposit_beforeInterest_fuzz
    */
    /// forge-config: vaults_tests.fuzz.runs = 10000
    function test_previewDeposit_beforeInterest_fuzz(uint128 _assets) public {
        vm.assume(_assets > 0);

        uint256 previewShares =vault.previewDeposit(_assets);
        uint256 shares = _deposit(_assets, DEPOSITOR);

        assertEq(previewShares, shares, "previewDeposit must return as close but NOT more");
        assertEq(previewShares, vault.convertToShares(_assets), "previewDeposit == convertToShares");
    }

    /*
    forge test -vv --ffi --mt test_previewDeposit_afterNoInterest
    */
    /// forge-config: vaults_tests.fuzz.runs = 10000
    function test_previewDeposit_afterNoInterest_fuzz(uint128 _assets) public {
        vm.assume(_assets > 0);

        uint256 sharesBefore = _deposit(_assets, DEPOSITOR);

        vm.warp(block.timestamp + 365 days);
        _silo0().accrueInterest();
        _silo1().accrueInterest();

        uint256 previewShares = vault.previewDeposit(_assets);
        uint256 gotShares = _deposit(_assets, DEPOSITOR);

        assertEq(previewShares, gotShares, "previewDeposit must return as close but NOT more");
        assertEq(previewShares, sharesBefore, "without interest shares must be the same");
        assertEq(previewShares, vault.convertToShares(_assets), "previewDeposit == convertToShares");
    }
}
