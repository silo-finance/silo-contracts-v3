// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Address} from "openzeppelin5/utils/Address.sol";
import {Pausable} from "openzeppelin5/utils/Pausable.sol";
import {Ownable2Step, Ownable} from "openzeppelin5/access/Ownable2Step.sol";
import {ReentrancyGuard} from "openzeppelin5/utils/ReentrancyGuard.sol";

import {ISiloRouterV2} from "../interfaces/ISiloRouterV2.sol";
import {IVersioned} from "../interfaces/IVersioned.sol";

/// @title SiloRouterV2
/// @custom:security-contact security@silo.finance
/// @notice Silo Router is a utility contract that aims to improve UX. It can batch any number or combination
/// of actions (Deposit, Withdraw, Borrow, Repay) and execute them in a single transaction.
/// @dev SiloRouterV2 requires only first action asset to be approved
/// @dev Caller should ensure that the router balance is empty after multicall.
contract SiloRouterV2 is Pausable, Ownable2Step, ReentrancyGuard, ISiloRouterV2, IVersioned {
    /// @notice The address of the implementation contract
    address public immutable IMPLEMENTATION;

    /// @notice Constructor for the SiloRouterV2 contract
    /// @param _initialOwner The address of the initial owner
    /// @param _implementation The address of the implementation contract
    constructor (address _initialOwner, address _implementation) Ownable(_initialOwner) {
        // expect implementation to not work with storage
        IMPLEMENTATION = _implementation;
    }

    /// @dev Needed for unwrapping native tokens
    receive() external whenNotPaused payable {
        // `multicall` method may call `IWrappedNativeToken.withdraw()`
        // and we need to receive the withdrawn native token unconditionally
    }

    /// @inheritdoc ISiloRouterV2
    function multicall(bytes[] calldata data)
        external
        virtual
        payable
        nonReentrant
        whenNotPaused
        returns (bytes[] memory results)
    {
        results = new bytes[](data.length);

        for (uint256 i = 0; i < data.length; i++) {
            // expect implementation not to use `msg.value`
            results[i] = Address.functionDelegateCall(IMPLEMENTATION, data[i]);
        }

        return results;
    }

    /// @inheritdoc ISiloRouterV2
    function pause() external virtual onlyOwner {
        _pause();
    }

    /// @inheritdoc ISiloRouterV2
    function unpause() external virtual onlyOwner {
        _unpause();
    }

    /// @inheritdoc IVersioned
    function VERSION() external pure virtual returns (string memory) { // solhint-disable-line func-name-mixedcase
        return "SiloRouterV2 4.0.0";
    }
}
