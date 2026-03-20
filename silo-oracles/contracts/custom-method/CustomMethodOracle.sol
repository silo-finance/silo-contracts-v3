// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Initializable} from "openzeppelin5-upgradeable/proxy/utils/Initializable.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";

import {Aggregator} from "../_common/Aggregator.sol";
import {OracleNormalization} from "../lib/OracleNormalization.sol";
import {ICustomMethodOracle} from "../interfaces/ICustomMethodOracle.sol";
import {CustomMethodOracleConfig} from "./CustomMethodOracleConfig.sol";

contract CustomMethodOracle is ICustomMethodOracle, ISiloOracle, Initializable, Aggregator, IVersioned {
    /// @notice Config contract address (clone-specific); all other immutable params via `getConfig()`.
    CustomMethodOracleConfig public oracleConfig;

    /// @notice Canonical parameterless signature string (factory-normalized)
    string public methodSignature;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc ICustomMethodOracle
    function initialize(address _oracleConfig, string calldata _methodSignature)
        external
        virtual
        initializer
    {
        oracleConfig = CustomMethodOracleConfig(_oracleConfig);
        methodSignature = _methodSignature;

        ICustomMethodOracle.OracleConfig memory _cfg = oracleConfig.getConfig();
        _readPrice({_target: _cfg.target, _callSelector: _cfg.callSelector});
    }

    /// @inheritdoc ISiloOracle
    function quote(uint256 _baseAmount, address _baseToken)
        public
        view
        virtual
        override(Aggregator, ISiloOracle)
        returns (uint256 quoteAmount)
    {
        ICustomMethodOracle.OracleConfig memory _cfg = oracleConfig.getConfig();

        require(_baseToken == _cfg.baseToken, AssetNotSupported());
        require(_baseAmount <= type(uint128).max, BaseAmountOverflow());

        uint256 assetPrice = _readPrice({_target: _cfg.target, _callSelector: _cfg.callSelector});

        require(assetPrice <= type(uint128).max, InvalidReturnData());

        quoteAmount = OracleNormalization.normalizePrice({
            _baseAmount: _baseAmount,
            _assetPrice: assetPrice,
            _normalizationDivider: _cfg.normalizationDivider,
            _normalizationMultiplier: _cfg.normalizationMultiplier
        });

        require(quoteAmount != 0, ZeroQuote());
    }

    /// @inheritdoc ISiloOracle
    function quoteToken() external view virtual returns (address) {
        return oracleConfig.getConfig().quoteToken;
    }

    function beforeQuote(address) external pure virtual override {
        // nothing to execute
    }

    /// @inheritdoc IVersioned
    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure virtual override returns (string memory version) {
        version = "CustomMethodOracle 4.5.0";
    }

    /// @inheritdoc Aggregator
    function baseToken() public view virtual override returns (address token) {
        return oracleConfig.getConfig().baseToken;
    }

    /// @inheritdoc ICustomMethodOracle
    function getConfig() external view virtual override returns (ICustomMethodOracle.OracleConfig memory) {
        return oracleConfig.getConfig();
    }

    function _readPrice(address _target, bytes4 _callSelector) internal view returns (uint256 assetPrice) {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = _target.staticcall(abi.encodeWithSelector(_callSelector));

        require(success, StaticCallFailed());
        require(data.length == 32, InvalidReturnData());

        assetPrice = abi.decode(data, (uint256));
        require(assetPrice != 0, ZeroQuote());
    }
}
