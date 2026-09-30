// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
    forge test -vv --ffi --mc MintTest
*/
contract MintTest is SiloLittleHelper, Test {
    ISiloConfig siloConfig;

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event DepositProtected(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    function setUp() public {
        siloConfig = _setUpLocalFixture();
    }

    /*
    forge test -vv --ffi --mt test_mint
    */
    function test_mint() public {
        uint256 shares = 1e18;
        address depositor = makeAddr("Depositor");

        uint256 previewMint = silo0.previewMint(shares);

        token0.mint(depositor, previewMint);

        vm.startPrank(depositor);
        token0.approve(address(silo0), previewMint);
        silo0.mint(shares, depositor);

        assertEq(silo0.getCollateralAssets(), previewMint, "previewMint should give us expected assets amount");
    }
}
