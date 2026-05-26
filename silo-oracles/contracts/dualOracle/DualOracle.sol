// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Ownable2StepUpgradeable, OwnableUpgradeable} from "openzeppelin5-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin5-upgradeable/utils/PausableUpgradeable.sol";

import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {OracleNormalization} from "silo-oracles/contracts/lib/OracleNormalization.sol";
import {IDualOracle} from "silo-oracles/contracts/interfaces/IDualOracle.sol";
import {DualOracleConfig} from "silo-oracles/contracts/dualOracle/DualOracleConfig.sol";

// solhint-disable ordering

/// @title DualOracle
///
/// Priority (highest → lowest):
///   1. Paused          → all quote() / latestRoundData() calls revert
///   2. Override active → returns admin-set manual price (normalized to 18 dp via same path as CL)
///   3. Normal          → delegates entirely to ChainlinkV3Oracle.quote()
contract DualOracle is IDualOracle, Aggregator, Ownable2StepUpgradeable, PausableUpgradeable {

    uint256 public constant MIN_TIMELOCK = 1 days;

    uint256 public constant MAX_TIMELOCK = 14 days;

    ISiloOracle public oracle;

    address public quoteToken;

    uint256 public timelock;

    address public override baseToken;

    uint256 public baseTokenDecimals;

    uint256 public lowerBound;

    uint256 public upperBound;

    uint256 public manualPrice;

    uint64 public overrideValidAt;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        ISiloOracle _oracle,
        address _owner,
        uint32 _timelock,
        uint256 _lowerBound,
        uint256 _upperBound
    ) external initializer {
        require(address(_oracle) != address(0), ZeroOracle());
        require(_owner != address(0), ZeroOwner());
        require(_timelock >= MIN_TIMELOCK && _timelock <= MAX_TIMELOCK, InvalidTimelock());
        require(_lowerBound > 0, LowerBoundMustBeGreaterThanZero());
        require(_lowerBound < _upperBound, InvalidBounds());

        __Ownable_init(_owner);
        __Pausable_init();

        oracle = _oracle;
        timelock = _timelock;
        baseToken = Aggregator(address(_oracle)).baseToken();
        baseTokenDecimals = TokenHelper.assertAndGetDecimals(baseToken);
        quoteToken = _oracle.quoteToken();
        lowerBound = _lowerBound;
        upperBound = _upperBound;

        require(baseTokenDecimals != 0, BaseTokenDecimalsMustBeGreaterThanZero());
        require(_oracle.quote(10 ** baseTokenDecimals, baseToken) > 0, OracleQuoteFailed());
    }

    function isOverrideActive() public view returns (bool) {
        uint64 validAt = overrideValidAt;
        return validAt != 0 && block.timestamp >= validAt;
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
            // TODO: make sure that getLowerBound > quote / 10^3 && getUpperBound < quote * 10^3
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
        else return oracle.quote(_baseAmount, _baseToken);
    }

    /// @inheritdoc ChainlinkV3Oracle
    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure virtual override returns (string memory version) {
        version = "DualOracle 1.0.0";
    }
}
