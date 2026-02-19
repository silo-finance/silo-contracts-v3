// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ICrossReentrancyGuard} from "silo-core/contracts/interfaces/ICrossReentrancyGuard.sol";
import {ShareToken} from "silo-core/contracts/utils/ShareToken.sol";
import {MethodReentrancyTest} from "../MethodReentrancyTest.sol";
import {MaliciousToken} from "../../MaliciousToken.sol";
import {TestStateLib} from "../../TestState.sol";

contract TransferReentrancyTest is MethodReentrancyTest {
    function callMethod() external {
        MaliciousToken token = MaliciousToken(TestStateLib.token0());
        ISilo silo = TestStateLib.silo0();
        address depositor = makeAddr("Depositor");
        address receiver = makeAddr("Receiver");
        uint256 amount = 100e18;

        TestStateLib.disableReentrancy();

        token.mint(depositor, amount);

        vm.prank(depositor);
        token.approve(address(silo), amount);

        uint256 depositAmount = amount / 2;

        vm.prank(depositor);
        silo.deposit(depositAmount, depositor, ISilo.CollateralType.Collateral);

        vm.prank(depositor);
        silo.deposit(depositAmount, depositor, ISilo.CollateralType.Protected);

        (address protected, address collateral,) = TestStateLib.siloConfig().getShareTokens(address(silo));

        TestStateLib.enableReentrancy();

        vm.prank(depositor);
        require(ShareToken(collateral).transfer(receiver, depositAmount), "transfer failed 13");

        vm.prank(depositor);
        require(ShareToken(protected).transfer(receiver, depositAmount), "transfer failed 14");
    }

    function verifyReentrancy() external {
        ISiloConfig config = TestStateLib.siloConfig();
        ISilo silo0 = TestStateLib.silo0();
        ISilo silo1 = TestStateLib.silo1();

        (address protected, address collateral,) = config.getShareTokens(address(silo0));

        vm.expectRevert(ICrossReentrancyGuard.CrossReentrantCall.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ShareToken(collateral).transfer(address(0), 0);

        vm.expectRevert(ICrossReentrancyGuard.CrossReentrantCall.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ShareToken(protected).transfer(address(0), 0);

        (protected, collateral,) = config.getShareTokens(address(silo1));

        vm.expectRevert(ICrossReentrancyGuard.CrossReentrantCall.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ShareToken(collateral).transfer(address(0), 0);

        vm.expectRevert(ICrossReentrancyGuard.CrossReentrantCall.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ShareToken(protected).transfer(address(0), 0);
    }

    function methodDescription() external pure returns (string memory description) {
        description = "transfer(address,uint256)";
    }
}
