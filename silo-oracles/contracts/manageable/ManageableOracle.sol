// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Initializable} from "openzeppelin5-upgradeable/proxy/utils/Initializable.sol";

import {Aggregator} from "../_common/Aggregator.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IManageableOracle} from "silo-oracles/contracts/interfaces/IManageableOracle.sol";
import {PendingAddress, PendingUint192, PendingLib} from "silo-vaults/contracts/libraries/PendingLib.sol";
import {IVersioned} from "silo-core/contracts/interfaces/IVersioned.sol";
import {TokenHelper} from "silo-core/contracts/lib/TokenHelper.sol";
import {RevertLib} from "silo-core/contracts/lib/RevertLib.sol";

/// @title ManageableOracle
/// @notice Oracle forwarder that allows updating the oracle address with time lock and owner approval
contract ManageableOracle is Aggregator, ISiloOracle, IManageableOracle, Initializable, IVersioned {
    using PendingLib for PendingAddress;
    using PendingLib for PendingUint192;

    /// @dev Minimum time lock duration
    uint32 public constant MIN_TIMELOCK = 1 days;

    /// @dev Maximum time lock duration
    uint32 public constant MAX_TIMELOCK = 14 days;

    address public owner;

    /// @dev Quote token address (set during initialization)
    address public quoteToken;

    /// @dev Base token decimals (set during initialization)
    uint256 public baseTokenDecimals;

    /// @dev Current oracle
    ISiloOracle public oracle;

    /// @dev Current time lock duration
    uint32 public timelock;

    /// @dev Pending oracle address
    PendingAddress public pendingOracle;

    /// @dev Pending time lock duration
    PendingUint192 public pendingTimelock;

    /// @dev Pending ownership change (zero address means renounce, otherwise transfer)
    /// @notice Only one type of ownership change can be pending at a time (either transfer or renounce)
    PendingAddress public pendingOwnership;

    /// @dev Base token address (set during initialization)
    address internal _baseTokenInternal;

    /// @dev Modifier to check if timelock has elapsed
    modifier afterTimelock(uint64 _validAt) {
        require(_validAt != 0, NoPendingUpdate());
        require(block.timestamp >= _validAt, TimelockNotExpired());
        _;
    }

    /// @dev Modifier to check if the caller is the owner
    modifier onlyOwner() {
        require(msg.sender == owner, OnlyOwner());
        _;
    }

    modifier whenPending(uint256 _validAt) {
        require(_validAt != 0, NoPendingUpdateToCancel());
        _;
    }

    modifier whenNotPending(uint256 _validAt) {
        require(_validAt == 0, PendingUpdate());
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the ManageableOracle
    /// @param _oracle Initial oracle address
    /// @param _owner Address that will own the contract
    /// @param _timelock Initial time lock duration
    function initialize(ISiloOracle _oracle, address _owner, uint32 _timelock) external initializer {
        require(address(_oracle) != address(0), ZeroOracle());
        require(_owner != address(0), ZeroOwner());
        require(_timelock >= MIN_TIMELOCK && _timelock <= MAX_TIMELOCK, InvalidTimelock());

        quoteToken = _oracle.quoteToken();
        address baseTokenCached = Aggregator(address(_oracle)).baseToken();
        _baseTokenInternal = baseTokenCached;
        baseTokenDecimals = TokenHelper.assertAndGetDecimals(baseTokenCached);

        require(baseTokenDecimals != 0, BaseTokenDecimalsMustBeGreaterThanZero());

        oracle = _oracle;
        timelock = _timelock;

        oracleVerification(_oracle);

        _transferOwnership(_owner);

        emit OracleUpdated(_oracle);
        emit TimelockUpdated(_timelock);
    }

    /// @inheritdoc IManageableOracle
    function proposeOracle(ISiloOracle _oracle) external virtual onlyOwner whenNotPending(pendingOracle.validAt) {
        require(address(_oracle) != address(oracle), NoChange());

        oracleVerification(_oracle);

        pendingOracle.update(address(_oracle), timelock);
        emit OracleProposed(_oracle, pendingOracle.validAt);
    }

    /// @inheritdoc IManageableOracle
    function proposeTimelock(uint32 _timelock) external virtual onlyOwner whenNotPending(pendingTimelock.validAt) {
        require(_timelock != timelock, NoChange());
        require(_timelock >= MIN_TIMELOCK && _timelock <= MAX_TIMELOCK, InvalidTimelock());

        pendingTimelock.update(_timelock, timelock);
        emit TimelockProposed(_timelock, pendingTimelock.validAt);
    }

    /// @inheritdoc IManageableOracle
    function proposeTransferOwnership(address _newOwner)
        external
        virtual
        onlyOwner
        whenNotPending(pendingOwnership.validAt)
    {
        require(_newOwner != owner, NoChange());
        require(_newOwner != address(0), ZeroOwner());

        pendingOwnership.update(_newOwner, timelock);
        emit OwnershipTransferProposed(_newOwner, pendingOwnership.validAt);
    }

    /// @inheritdoc IManageableOracle
    function proposeRenounceOwnership() external virtual onlyOwner whenNotPending(pendingOwnership.validAt) {
        pendingOwnership.update(address(0), timelock);
        emit OwnershipRenounceProposed(pendingOwnership.validAt);
    }

    /// @inheritdoc IManageableOracle
    function acceptOracle() external virtual onlyOwner afterTimelock(pendingOracle.validAt) {
        oracle = ISiloOracle(pendingOracle.value);
        _resetPendingAddress(pendingOracle);
        emit OracleUpdated(oracle);
    }

    /// @inheritdoc IManageableOracle
    function acceptTimelock() external virtual onlyOwner afterTimelock(pendingTimelock.validAt) {
        timelock = uint32(pendingTimelock.value);
        _resetPendingUint192(pendingTimelock);
        emit TimelockUpdated(timelock);
    }

    /// @dev The new owner accepts the ownership transfer.
    function acceptOwnership() external virtual afterTimelock(pendingOwnership.validAt) {
        require(pendingOwnership.value != address(0), InvalidOwnershipChangeType());
        require(pendingOwnership.value == msg.sender, OnlyOwner());

        _resetPendingAddress(pendingOwnership);
        _transferOwnership(msg.sender);
    }

    /// @inheritdoc IManageableOracle
    function acceptRenounceOwnership() external virtual onlyOwner afterTimelock(pendingOwnership.validAt) {
        require(pendingOwnership.value == address(0), InvalidOwnershipChangeType());
        require(pendingOracle.validAt == 0, PendingOracleUpdate());
        require(pendingTimelock.validAt == 0, PendingTimelockUpdate());

        _resetPendingAddress(pendingOwnership);
        _transferOwnership(address(0));
    }

    /// @inheritdoc IManageableOracle
    function cancelOracle() external virtual onlyOwner whenPending(pendingOracle.validAt) {
        _resetPendingAddress(pendingOracle);
        emit OracleProposalCanceled();
    }

    /// @inheritdoc IManageableOracle
    function cancelTimelock() external virtual onlyOwner whenPending(pendingTimelock.validAt) {
        _resetPendingUint192(pendingTimelock);
        emit TimelockProposalCanceled();
    }

    /// @inheritdoc IManageableOracle
    function cancelTransferOwnership() external virtual onlyOwner whenPending(pendingOwnership.validAt) {
        require(pendingOwnership.value != address(0), InvalidOwnershipChangeType());

        _resetPendingAddress(pendingOwnership);
        emit OwnershipTransferCanceled();
    }

    /// @inheritdoc IManageableOracle
    function cancelRenounceOwnership() external virtual onlyOwner whenPending(pendingOwnership.validAt) {
        require(pendingOwnership.value == address(0), InvalidOwnershipChangeType());

        _resetPendingAddress(pendingOwnership);
        emit OwnershipRenounceCanceled();
    }

    /// @inheritdoc ISiloOracle
    function beforeQuote(address _baseToken) external virtual {
        oracle.beforeQuote(_baseToken);
    }

    /// @inheritdoc IVersioned
    // solhint-disable-next-line func-name-mixedcase
    function VERSION() external pure override returns (string memory version) {
        version = "ManageableOracle 4.0.0";
    }

    function baseToken() public view virtual override(Aggregator, IManageableOracle) returns (address) {
        return _baseTokenInternal;
    }

    /// @inheritdoc ISiloOracle
    function quote(uint256 _baseAmount, address _baseToken)
        public
        view
        virtual
        override(Aggregator, ISiloOracle)
        returns (uint256 quoteAmount)
    {
        quoteAmount = oracle.quote(_baseAmount, _baseToken);
    }

    /// @inheritdoc IManageableOracle
    function oracleVerification(ISiloOracle _oracle) public view virtual {
        address baseTokenCached = baseToken();
        require(baseTokenCached != address(0), ZeroBaseToken());

        require(address(_oracle) != address(0), ZeroOracle());
        require(_oracle.quoteToken() == quoteToken, QuoteTokenMustBeTheSame());
        require(Aggregator(address(_oracle)).baseToken() == baseTokenCached, BaseTokenMustBeTheSame());

        // sanity check
        try _oracle.quote(10 ** baseTokenDecimals, baseTokenCached) returns (uint256 price) {
            require(price != 0, OracleQuoteFailed());
        } catch (bytes memory reason) {
            RevertLib.revertBytes(reason, OracleQuoteFailed.selector);
        }
    }

    function _resetPendingAddress(PendingAddress storage _pending) internal virtual {
        _pending.value = address(0);
        _pending.validAt = 0;
    }

    function _resetPendingUint192(PendingUint192 storage _pending) internal virtual {
        _pending.value = 0;
        _pending.validAt = 0;
    }

    function _transferOwnership(address _newOwner) internal virtual {
        address oldOwner = owner;
        owner = _newOwner;
        emit OwnershipTransferred(oldOwner, _newOwner);
    }
}
