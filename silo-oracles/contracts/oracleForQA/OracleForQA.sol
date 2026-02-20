// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.28;

import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";
import {Aggregator} from "../_common/Aggregator.sol";

// solhint-disable ordering

contract OracleForQA is ISiloOracle, Aggregator, IVersioned {
    address public immutable QUOTE_TOKEN;
    address public immutable BASE_TOKEN;
    uint256 public immutable BASE_DECIMALS;
    address public immutable ADMIN;

    uint256 public priceOfOneBaseToken;

    error ZeroPrice();
    error OnlyAdminCanSetPrice();

    constructor (address base, address _quote, address _admin, uint256 _initialPrice) {
        BASE_TOKEN = base;
        QUOTE_TOKEN = _quote;
        BASE_DECIMALS = IERC20Metadata(base).decimals();
        ADMIN = _admin;
        priceOfOneBaseToken = _initialPrice;
    }

    /// @param _price if oracle is set for WETH/USDC, where USDC is quote, then correct price would be 3000e6
    function setPriceOfOneBaseToken(uint256 _price) external {
        require(ADMIN == address(0) || msg.sender == ADMIN, OnlyAdminCanSetPrice());

        priceOfOneBaseToken = _price;
    }

    function quoteToken() external view override virtual returns (address) {
        return QUOTE_TOKEN;
    }

    /// @inheritdoc ISiloOracle
    function quote(uint256 _baseAmount, address _baseToken)
        public
        view
        virtual
        override(Aggregator, ISiloOracle)
        returns (uint256 quoteAmount)
    {
        quoteAmount = _baseToken == QUOTE_TOKEN
            ? _baseAmount
            : _baseAmount * priceOfOneBaseToken / (10 ** BASE_DECIMALS);

        require(quoteAmount != 0, ZeroPrice());
    }

    function beforeQuote(address) external pure virtual override {
        // nothing to execute
    }

    /// @inheritdoc IVersioned
    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure override returns (string memory version) {
        version = "OracleForQA 4.0.0";
    }

    /// @inheritdoc Aggregator
    function baseToken() public view virtual override returns (address token) {
        return BASE_TOKEN;
    }
}
