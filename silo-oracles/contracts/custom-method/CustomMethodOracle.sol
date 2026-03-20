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
    /// @notice Config contract address (clone-specific); all other immutable params via `getConfig()`.
    CustomMethodOracleConfig public oracleConfig;

    /// @dev Canonical parameterless signature string (factory-normalized); kept on the clone, not on config.
    string internal _methodSignature;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(CustomMethodOracleConfig _oracleConfig, string calldata _canonicalMethodSignature)
        external
        virtual
        initializer
    {
        oracleConfig = _oracleConfig;
        _methodSignature = _canonicalMethodSignature;
        emit CustomMethodConfigDeployed(address(_oracleConfig));
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

        uint256 assetPrice = _readPrice(_cfg.target, _cfg.callSelector);

        require(assetPrice <= type(uint128).max, InvalidReturnData());

        quoteAmount = OracleNormalization.normalizePrice(
            _baseAmount,
            assetPrice,
            _cfg.normalizationDivider,
            _cfg.normalizationMultiplier
        );

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
    function methodSignature() external view virtual override returns (string memory) {
        return _methodSignature;
    }

    /// @inheritdoc ICustomMethodOracle
    function getConfig() external view virtual override returns (ICustomMethodOracle.OracleConfig memory) {
        return oracleConfig.getConfig();
    }

    /// @inheritdoc ICustomMethodOracle
    function callData() external view virtual override returns (bytes memory) {
        return abi.encodeWithSelector(oracleConfig.getConfig().callSelector);
    }

    /// @inheritdoc ICustomMethodOracle
    function callSelector() external view virtual override returns (bytes4) {
        return oracleConfig.getConfig().callSelector;
    }

    /// @inheritdoc ICustomMethodOracle
    function priceTarget() external view virtual override returns (address) {
        return oracleConfig.getConfig().target;
    }

    function _readPrice(address _target, bytes4 _callSelector) internal view returns (uint256 assetPrice) {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = _target.staticcall(abi.encodeWithSelector(_callSelector));

        require(success, StaticCallFailed());
        require(data.length >= 32, InvalidReturnData());

        assetPrice = abi.decode(data, (uint256));
    }
}
