// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Ownable2StepUpgradeable, OwnableUpgradeable} from "openzeppelin5-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin5-upgradeable/utils/PausableUpgradeable.sol";

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {OracleNormalization} from "silo-oracles/contracts/lib/OracleNormalization.sol";
import {ChainlinkV3Oracle} from "silo-oracles/contracts/chainlinkV3/ChainlinkV3Oracle.sol";
import {ChainlinkV3OracleConfig} from "silo-oracles/contracts/chainlinkV3/ChainlinkV3OracleConfig.sol";
import {IChainlinkV3Oracle} from "silo-oracles/contracts/interfaces/IChainlinkV3Oracle.sol";
import {IDualOracle} from "silo-oracles/contracts/interfaces/IDualOracle.sol";
import {DualOracleConfig} from "silo-oracles/contracts/dualOracle/DualOracleConfig.sol";

// solhint-disable ordering

/// @title DualOracle
/// @notice Extends ChainlinkV3Oracle with two governance-controlled safety mechanisms:
///         pause mode and a bounded manual price override.
///
/// Priority (highest → lowest):
///   1. Paused          → all quote() / latestRoundData() calls revert
///   2. Override active → returns admin-set manual price (normalized to 18 dp via same path as CL)
///   3. Normal          → delegates entirely to ChainlinkV3Oracle.quote()
///
/// Timelocked:  enabling override   (proposeOverride → wait → acceptOverride)
/// Immediate:   pause / unpause, disableOverride, setManualPrice
contract DualOracle is IDualOracle, ChainlinkV3Oracle, Ownable2StepUpgradeable, PausableUpgradeable {
    /// @inheritdoc IDualOracle
    uint256 public manualPrice;

    /// @inheritdoc IDualOracle
    uint64 public overrideValidAt;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialise the cloned oracle with its config.
    ///         Validation of config is performed by DualOracleFactory — use the factory, not this directly.
    ///         Overrides ChainlinkV3Oracle.initialize to also wire up Ownable from DualOracleConfig.
    function initialize(ChainlinkV3OracleConfig _configAddress, address _owner) external virtual override initializer {
        ChainlinkV3Oracle.initialize(_configAddress);

        __Ownable_init(_owner);
        __Pausable_init();
    }

    /// @inheritdoc PausableUpgradeable
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc PausableUpgradeable
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc IDualOracle
    function setManualPrice(uint256 _price) external onlyOwner {
        require(_price != manualPrice, PriceNotChanged());

        if (_price == 0) {
            // allow setting zero price to disable override mode without a new timelock
            manualPrice = 0;
            emit ManualPriceSet(0);

            overrideValidAt = 0;
            emit OverrideDisabled();
        } else {
            // allow updating manual price immediately without a new timelock
            DualOracleConfig dualConfig = DualOracleConfig(address(oracleConfig));
            require(_price >= dualConfig.getLowerBound(), PriceBelowLowerBound());
            require(_price <= dualConfig.getUpperBound(), PriceAboveUpperBound());

            manualPrice = _price;
            emit ManualPriceSet(_price);

            // when override is not active, require a new activation with the updated price
            if (!isOverrideActive()) {
                uint64 validAt = uint64(block.timestamp + DualOracleConfig(address(oracleConfig)).getTimelock());
                overrideValidAt = validAt;
                emit OverrideEnabled(validAt);
            }
        }
    }

    function isOverrideActive() public view returns (bool) {
        uint64 validAt = overrideValidAt;
        return validAt != 0 && block.timestamp >= validAt;
    }

    /// @dev Priority: paused > override > ChainlinkV3Oracle.quote()
    ///      When override is active the manual price is run through the same
    ///      OracleNormalization path as a live Chainlink answer, keeping behaviour consistent.
    function quote(uint256 _baseAmount, address _baseToken)
        public
        view
        virtual
        override(ChainlinkV3Oracle, ISiloOracle)
        whenNotPaused
        returns (uint256 quoteAmount)
    {
        if (isOverrideActive()) return manualPrice;
        else return ChainlinkV3Oracle.quote(_baseAmount, _baseToken);
    }

    /// @inheritdoc ChainlinkV3Oracle
    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure virtual override returns (string memory version) {
        version = "DualOracle 1.0.0";
    }
}
