// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Initializable} from "openzeppelin5-upgradeable/proxy/utils/Initializable.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";

import {Aggregator} from "../_common/Aggregator.sol";
import {OracleNormalization} from "../lib/OracleNormalization.sol";
import {ICustomMethodOracle} from "../interfaces/ICustomMethodOracle.sol";
import {CustomMethodOracleConfig} from "./CustomMethodOracleConfig.sol";

// solhint-disable ordering

contract CustomMethodOracle is ICustomMethodOracle, ISiloOracle, Initializable, Aggregator, IVersioned {
    CustomMethodOracleConfig public oracleConfig;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice One-time init; use factory only.
    function initialize(CustomMethodOracleConfig _configAddress) external virtual initializer {
        oracleConfig = _configAddress;
        emit CustomMethodConfigDeployed(address(_configAddress));
    }

    /// @inheritdoc ISiloOracle
    function quote(uint256 _baseAmount, address _baseToken)
        public
        view
        virtual
        override(Aggregator, ISiloOracle)
        returns (uint256 quoteAmount)
    {
        CustomMethodOracleConfig cfg = oracleConfig;

        if (_baseToken != address(cfg.baseToken())) revert AssetNotSupported();
        if (_baseAmount > type(uint128).max) revert BaseAmountOverflow();

        uint256 assetPrice = _readPrice(cfg);

        if (assetPrice > type(uint128).max) revert InvalidReturnData();

        quoteAmount = OracleNormalization.normalizePrice(
            _baseAmount,
            assetPrice,
            cfg.normalizationDivider(),
            cfg.normalizationMultiplier()
        );

        if (quoteAmount == 0) revert ZeroQuote();

        return quoteAmount;
    }

    /// @inheritdoc ISiloOracle
    function quoteToken() external view virtual returns (address) {
        return address(oracleConfig.quoteToken());
    }

    function beforeQuote(address) external pure virtual override {
        // nothing
    }

    /// @inheritdoc IVersioned
    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure virtual override returns (string memory version) {
        version = "CustomMethodOracle 1.0.0";
    }

    /// @inheritdoc Aggregator
    function baseToken() public view virtual override returns (address token) {
        return address(oracleConfig.baseToken());
    }

    /// @inheritdoc ICustomMethodOracle
    function methodSignature() external view virtual override returns (string memory) {
        return oracleConfig.methodSignature();
    }

    /// @inheritdoc ICustomMethodOracle
    function callData() external view virtual override returns (bytes memory) {
        return abi.encodeWithSelector(oracleConfig.callSelector());
    }

    /// @inheritdoc ICustomMethodOracle
    function callSelector() external view virtual override returns (bytes4) {
        return oracleConfig.callSelector();
    }

    /// @inheritdoc ICustomMethodOracle
    function priceTarget() external view virtual override returns (address) {
        return oracleConfig.target();
    }

    function _readPrice(CustomMethodOracleConfig cfg) internal view returns (uint256 assetPrice) {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = cfg.target().staticcall(abi.encodeWithSelector(cfg.callSelector()));

        if (!success) revert StaticCallFailed();
        if (data.length < 32) revert InvalidReturnData();

        if (cfg.returnIsSigned()) {
            int256 signed = abi.decode(data, (int256));
            if (signed <= 0) revert InvalidSignedPrice();
            // forge-lint: disable-next-line(unsafe-typecast)
            assetPrice = uint256(signed);
        } else {
            assetPrice = abi.decode(data, (uint256));
            if (assetPrice == 0) revert ZeroQuote();
        }
    }
}
