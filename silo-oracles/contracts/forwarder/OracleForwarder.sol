// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Ownable2Step, Ownable} from "openzeppelin5/access/Ownable2Step.sol";

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";
import {IOracleForwarder} from "silo-oracles/contracts/interfaces/IOracleForwarder.sol";

contract OracleForwarder is Ownable2Step, IOracleForwarder, IVersioned {
    address public immutable QUOTE_TOKEN;

    ISiloOracle public oracle;

    constructor(ISiloOracle _oracle, address _owner) Ownable(_owner) {
        QUOTE_TOKEN = _oracle.quoteToken();

        _setOracle(_oracle);
    }

    /// @inheritdoc IOracleForwarder
    function setOracle(ISiloOracle _oracle) external virtual onlyOwner {
        require(_oracle.quoteToken() == QUOTE_TOKEN, QuoteTokenMustBeTheSame());

        _setOracle(_oracle);
    }

    /// @inheritdoc ISiloOracle
    function beforeQuote(address _baseToken) external virtual {
        oracle.beforeQuote(_baseToken);
    }

    /// @inheritdoc ISiloOracle
    function quote(uint256 _baseAmount, address _baseToken) external virtual view returns (uint256 quoteAmount) {
        quoteAmount = oracle.quote(_baseAmount, _baseToken);
    }

    /// @inheritdoc ISiloOracle
    function quoteToken() external virtual view returns (address token) {
        token = QUOTE_TOKEN;
    }

    /// @inheritdoc IVersioned
    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure override returns (string memory version) {
        version = "OracleForwarder 4.0.0";
    }

    function _setOracle(ISiloOracle _oracle) internal virtual {
        oracle = _oracle;

        emit OracleSet(_oracle);
    }
}
