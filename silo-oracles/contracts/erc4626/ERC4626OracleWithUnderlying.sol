// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";
import {Aggregator} from "../_common/Aggregator.sol";

import {IERC4626OracleWithUnderlying} from "../interfaces/IERC4626OracleWithUnderlying.sol";

// solhint-disable ordering

/// @dev quote will returns price in oracle decimals
contract ERC4626OracleWithUnderlying is IERC4626OracleWithUnderlying, Aggregator, IVersioned {
    /// @dev address of the vault itself, vault share is base token
    IERC4626 private immutable _VAULT; // solhint-disable-line var-name-mixedcase

    /// @dev quoteToken address of asset in which price id denominated in
    address private immutable _QUOTE_TOKEN; // solhint-disable-line var-name-mixedcase

    /// @dev vault.asset()
    address private immutable _VAULT_ASSET; // solhint-disable-line var-name-mixedcase

    /// @dev oracle address to provide price for `_VAULT_ASSET`
    ISiloOracle private immutable _ORACLE; // solhint-disable-line var-name-mixedcase

    /// @dev all verification should be done by factory
    constructor(IERC4626 _vault, ISiloOracle _oracle) {
        _VAULT = _vault;
        _ORACLE = _oracle;

        _VAULT_ASSET = _vault.asset();
        _QUOTE_TOKEN = _oracle.quoteToken();
    }

    function getConfig() external view returns (Config memory) {
        return Config({
            baseToken: _VAULT,
            quoteToken: _QUOTE_TOKEN,
            oracle: _ORACLE,
            vaultAsset: _VAULT_ASSET
        });
    }
    
    /// @inheritdoc ISiloOracle
    function quote(uint256 _baseAmount, address _baseToken)
        public
        view
        virtual
        override(Aggregator, ISiloOracle)
        returns (uint256 quoteAmount)
    {
        require(_baseAmount < type(uint128).max, BaseAmountOverflow());
        require(_baseToken == address(_VAULT), AssetNotSupported());

        uint256 underlyingAssets = _VAULT.convertToAssets(_baseAmount);
        quoteAmount = _ORACLE.quote(underlyingAssets, _VAULT_ASSET);
  
        require(quoteAmount != 0, ZeroQuote());
    }

    /// @inheritdoc ISiloOracle
    function quoteToken() external view virtual returns (address) {
        return _QUOTE_TOKEN;
    }

    function beforeQuote(address) external pure virtual override {
        // nothing to execute
    }

    /// @inheritdoc IVersioned
    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure override returns (string memory version) {
        version = "ERC4626OracleWithUnderlying 4.0.0";
    }

    /// @inheritdoc Aggregator
    function baseToken() public view virtual override returns (address token) {
        return address(_VAULT);
    }
}
