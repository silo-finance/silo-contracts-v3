// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";
import {Aggregator} from "../_common/Aggregator.sol";

// solhint-disable ordering

contract ERC4626Oracle is ISiloOracle, Aggregator, IVersioned {
    IERC4626 public immutable VAULT;

    error AssetNotSupported();
    error ZeroPrice();

    constructor(IERC4626 _vault) {
        VAULT = _vault;
    }

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
        if (_baseToken != address(VAULT)) revert AssetNotSupported();

        quoteAmount = VAULT.convertToAssets(_baseAmount);

        if (quoteAmount == 0) revert ZeroPrice();
    }

    /// @inheritdoc ISiloOracle
    function quoteToken() external view virtual returns (address) {
        return VAULT.asset();
    }

    /// @inheritdoc IVersioned
    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure override virtual returns (string memory version) {
        version = "ERC4626Oracle 4.0.0";
    }

    /// @inheritdoc Aggregator
    function baseToken() public view virtual override returns (address token) {
        return address(VAULT);
    }
}
