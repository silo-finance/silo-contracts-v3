// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Initializable} from "openzeppelin5-upgradeable/proxy/utils/Initializable.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";
import {TokenHelper} from "silo-core/contracts/lib/TokenHelper.sol";
import {Aggregator} from "silo-oracles/contracts/_common/Aggregator.sol";
import {IFlatPriceOracle} from "silo-oracles/contracts/interfaces/IFlatPriceOracle.sol";

contract FlatPriceOracle is IFlatPriceOracle, ISiloOracle, Initializable, Aggregator, IVersioned {
    uint256 public price;
    uint256 public normalizationDivider;
    address private _baseToken;
    address public override quoteToken;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(uint256 _price, address _baseTokenArg, address _quoteTokenArg) external initializer {
        require(_baseTokenArg != address(0), AddressZero());
        require(_quoteTokenArg != address(0), AddressZero());
        require(_baseTokenArg != _quoteTokenArg, TokensAreTheSame());
        require(_price != 0, ZeroPrice());

        uint256 baseTokenDecimals = TokenHelper.assertAndGetDecimals(_baseTokenArg);

        price = _price;
        normalizationDivider = 10 ** baseTokenDecimals;
        _baseToken = _baseTokenArg;
        quoteToken = _quoteTokenArg;
    }

    function description() external view override returns (string memory) {
        return string.concat(
            TokenHelper.symbol(_baseToken),
            " / ",
            TokenHelper.symbol(quoteToken)
        );
    }

    function beforeQuote(address) external pure override {
        // nothing to execute
    }

    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure override returns (string memory v) {
        v = "FlatPriceOracle 4.12.0";
    }

    function quote(uint256 _baseAmount, address _baseTokenArg)
        public
        view
        override(Aggregator, ISiloOracle)
        returns (uint256 quoteAmount)
    {
        require(_baseTokenArg == _baseToken, AssetNotSupported());

        quoteAmount = _baseAmount * price / normalizationDivider;
        require(quoteAmount != 0, ZeroPrice());
    }

    function baseToken() public view override returns (address token) {
        return _baseToken;
    }
}
