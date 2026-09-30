// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {RescueTokens} from "silo-core/contracts/utils/RescueTokens.sol";
import {MintableToken} from "../_common/MintableToken.sol";

/*
    FOUNDRY_PROFILE=core_test forge test --mc RescueTokensTest
*/
contract RescueTokensTest is Test {
    RescueTokens internal _rescue;
    MintableToken internal _token;
    address internal _receiver = makeAddr("RECEIVER");

    function setUp() public {
        vm.prank(_receiver);
        _rescue = new RescueTokens();
        _token = new MintableToken({ _setDecimals: 18 });

        assertEq(_rescue.TOKEN_RECEIVER(), _receiver);
    }

    function test_rescueTokens() public {
        uint256 amount = 100e18;

        _token.mint({ _owner: address(_rescue), _amount: amount });
        assertEq(_token.balanceOf(address(_rescue)), amount);

        vm.expectEmit(true, true, true, true);
        emit RescueTokens.TokensRescued({ token: address(_token), amount: amount });

        _rescue.rescueTokens({ _token: IERC20(address(_token)) });

        assertEq(_token.balanceOf(address(_rescue)), 0);
        assertEq(_token.balanceOf(_receiver), amount);
    }

    function test_rescueNativeTokens() public {
        uint256 amount = 123;
        uint256 receiverBalanceBefore = _receiver.balance;

        vm.deal(address(_rescue), amount);
        assertEq(address(_rescue).balance, amount);

        _rescue.rescueNativeTokens();

        assertEq(address(_rescue).balance, 0);
        assertEq(_receiver.balance, receiverBalanceBefore + amount);
    }
}
