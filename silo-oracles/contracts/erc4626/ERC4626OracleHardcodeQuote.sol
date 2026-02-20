// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {ERC4626Oracle} from "silo-oracles/contracts/erc4626/ERC4626Oracle.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";

contract ERC4626OracleHardcodeQuote is ERC4626Oracle {
    address internal immutable _QUOTE_TOKEN;

    constructor(IERC4626 _vault, address _quoteToken) ERC4626Oracle(_vault) {
        _QUOTE_TOKEN = _quoteToken;
    }

    /// @inheritdoc ISiloOracle
    function quoteToken() external view override returns (address) {
        return _QUOTE_TOKEN;
    }

    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure override returns (string memory version) {
        version = "ERC4626OracleHardcodeQuote 4.0.0";
    }
}
