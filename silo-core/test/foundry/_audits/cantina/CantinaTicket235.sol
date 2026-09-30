// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {CantinaTicket} from "./CantinaTicket.sol";

/*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc CantinaTicket235
*/
contract CantinaTicket235 is CantinaTicket {
    function testCollateralTransitionExploit() public {
        token0.setOnDemand(true);

        address attacker = address(this);

        // Assume the attacker begins with an initial collateral deposit in "Collateral" state.
        uint256 initialDeposit = 100e18;
        uint256 initialShares = _deposit(initialDeposit, attacker, ISilo.CollateralType.Collateral);
        uint256 transitionShares = initialShares;
        // uint256 iterations = 1000;

        // SILO COMMENT: if round is invalid we will gain even after one iteration

        // for (uint256 i = 0; i < iterations; i++) {
        // Transition collateral from "Collateral" to "Protected Collateral".
        silo0.transitionCollateral(transitionShares, attacker, ISilo.CollateralType.Collateral);
        // Redeem the withdrawn assets by depositing them into the "Protected Collateral" state.
        // uint256 newShares = silo0.deposit(withdrawnAssets, attacker, ISilo.CollateralType.Protected);
        // The attacker uses the new shares for the next transition.
        // transitionShares = newShares;
        // }

        // After many transitions, the attacker redeems the final shares.
        uint256 redeemedAssets = silo0.redeem(
            silo0.maxRedeem(attacker, ISilo.CollateralType.Protected),
            attacker,
            attacker,
            ISilo.CollateralType.Protected
        );

        // If rounding discrepancies have accumulated, redeemedAssets will exceed the initialDeposit.
        assertEq(redeemedAssets, initialDeposit, "no gains");
    }
}
