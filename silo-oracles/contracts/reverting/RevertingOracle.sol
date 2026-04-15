// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {Aggregator} from "../_common/Aggregator.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IManageableOracle} from "silo-oracles/contracts/interfaces/IManageableOracle.sol";

/// @dev this oracle is created to use as underlying for ManageableOracle.
/// It will pass the verification process so it can be set as underlying oracle, 
/// but once it is set, it will always revert.
/// If the message sender has the oracle() method and the value of oracle() is not set 
/// to the RevertingOracle contract, then we will not revert.
contract RevertingOracle is Aggregator, IVersioned, ISiloOracle {
    error ThisOracleAlwaysReverts();

    function description() external view virtual override returns (string memory) {
        return "This oracle always reverts";
    }

    /// @notice copy quote token from msg.sender
    function quoteToken() external view override returns (address) {
        // Purpose of this is only to pass verification on a ManageableOracle.
        return ISiloOracle(msg.sender).quoteToken();
    }

    /// @notice always reverts
    function beforeQuote(address /* _baseToken */) external pure override {
        revert ThisOracleAlwaysReverts();
    }

    function VERSION() external pure override returns (string memory) { // solhint-disable-line func-name-mixedcase
        return "RevertingOracle 4.9.0";
    }

    /// @notice always reverts
    function quote(uint256 /* _baseAmount */, address /* _baseToken */)
        public
        view
        override(Aggregator, ISiloOracle)
        returns (uint256 quoteAmount)
    {
        if (_isRevertingActive()) revert ThisOracleAlwaysReverts();

        // Purpose of this is only to pass verification on a ManageableOracle.
        return 1;
    }

    /// @notice copy base token from msg.sender
    function baseToken() public view override returns (address) {
        // Purpose of this is only to pass verification on a ManageableOracle.
        return Aggregator(msg.sender).baseToken();
    }

    function _isRevertingActive() internal view returns (bool) {
        try IManageableOracle(msg.sender).oracle() returns (ISiloOracle oracle) {
            return address(oracle) == address(this);
        } catch {
            return true;
        }
    }
}
