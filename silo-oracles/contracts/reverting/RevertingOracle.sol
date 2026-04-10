// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.28;

import {Aggregator} from "../_common/Aggregator.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IManageableOracle} from "silo-oracles/contracts/interfaces/IManageableOracle.sol";

contract RevertingOracle is Aggregator, IVersioned, ISiloOracle {
    string private constant _MANAGEABLE_ORACLE_VERSION = "ManageableOracle";

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
        return "RevertingOracle 4.8.0";
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
        if (!_detectManageableOracle()) return false;

        return address(IManageableOracle(msg.sender).oracle()) == address(this);
    }

    function _detectManageableOracle() internal view returns (bool) {
        uint256 versionLength = bytes(_MANAGEABLE_ORACLE_VERSION).length;

        try IVersioned(msg.sender).VERSION() returns (string memory version) {
            if (bytes(version).length < versionLength) {
                return false;
            }


            for (uint256 i = 0; i < versionLength; i++) {
                if (bytes1(bytes(version)[i]) != bytes1(bytes(_MANAGEABLE_ORACLE_VERSION)[i])) {
                    return false;
                }
            }
            
            return true;

        } catch {
            return false;
        }
    }
}
