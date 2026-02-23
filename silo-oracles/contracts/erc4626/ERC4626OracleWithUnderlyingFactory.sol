// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";

import {Create2Factory} from "common/utils/Create2Factory.sol";
import {MadeByFactory} from "../_common/MadeByFactory.sol";
import {IERC4626OracleWithUnderlying} from "../interfaces/IERC4626OracleWithUnderlying.sol";
import {ERC4626OracleWithUnderlying} from "../erc4626/ERC4626OracleWithUnderlying.sol";

contract ERC4626OracleWithUnderlyingFactory is Create2Factory, MadeByFactory {
    function create(
        IERC4626 _vault,
        ISiloOracle _oracle,
        bytes32 _externalSalt
    ) external virtual returns (ERC4626OracleWithUnderlying oracle) {
        verifyConfig(_vault, _oracle);

        oracle = new ERC4626OracleWithUnderlying{salt: _salt(_externalSalt)}( _vault, _oracle);

        _saveOracle(address(oracle));
    }

    function verifyConfig(IERC4626 _vault, ISiloOracle _oracle) public view virtual {
        require(address(_vault) != address(0), IERC4626OracleWithUnderlying.ZeroAddress());
        require(address(_oracle) != address(0), IERC4626OracleWithUnderlying.ZeroAddress());

        address vaultAsset = _vault.asset();

        require(vaultAsset != address(0), IERC4626OracleWithUnderlying.AssetZero());
        require(_oracle.quoteToken() != address(0), IERC4626OracleWithUnderlying.QuoteTokenZero());

        // sanity check for baseAsset
        require(
            _oracle.quote(10 ** IERC20Metadata(_vault.asset()).decimals(), vaultAsset) != 0,
            IERC4626OracleWithUnderlying.ZeroQuote()
        );
    }
}
