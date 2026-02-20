// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";
import {IsAVAX} from "silo-oracles/contracts/interfaces/IsAVAX.sol";
import {Aggregator} from "../../_common/Aggregator.sol";

// solhint-disable ordering

/// @dev sAVAXOracle is a custom oracle for tAVAX/wAVAX market
contract sAVAXOracle is ISiloOracle, Aggregator, IVersioned { // solhint-disable-line contract-name-camelcase
    IsAVAX public constant S_AVAX = IsAVAX(0x2b2C81e08f1Af8835a78Bb2A90AE924ACE0eA4bE);
    address public constant IAU_SAVAX = 0x5Ac32E4c756bD57630eAdF216668Ba16fA4635a2;

    error AssetNotSupported();
    error ZeroPrice();

    /// @inheritdoc ISiloOracle
    function beforeQuote(address _baseToken) external view {
        // only for an ISiloOracle interface implementation
    }

    /// @inheritdoc ISiloOracle
    function quote(uint256 _baseAmount, address _baseToken)
        public
        view
        virtual
        override(Aggregator, ISiloOracle)
        returns (uint256 quoteAmount)
    {
        require(_baseToken == IAU_SAVAX, AssetNotSupported());

        quoteAmount = S_AVAX.getPooledAvaxByShares(_baseAmount);

        if (quoteAmount == 0) revert ZeroPrice();
    }

    /// @inheritdoc ISiloOracle
    function quoteToken() external view virtual returns (address) {
        return 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7; // WAVAX
    }

    /// @inheritdoc IVersioned
    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure override returns (string memory version) {
        version = "sAVAXOracle 4.0.0";
    }

    /// @inheritdoc Aggregator
    function baseToken() public view virtual override returns (address token) {
        return IAU_SAVAX;
    }
}
