// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Initializable} from "openzeppelin5-upgradeable/proxy/utils/Initializable.sol";
import {Clones} from "openzeppelin5/proxy/Clones.sol";

import {ManageableOracleFactory} from "silo-oracles/contracts/manageable/ManageableOracleFactory.sol";
import {ManageableOracle} from "silo-oracles/contracts/manageable/ManageableOracle.sol";
import {Aggregator} from "silo-oracles/contracts/_common/Aggregator.sol";
import {IManageableOracleFactory} from "silo-oracles/contracts/interfaces/IManageableOracleFactory.sol";
import {IManageableOracle} from "silo-oracles/contracts/interfaces/IManageableOracle.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IERC20Metadata} from "silo-oracles/test/foundry/interfaces/IERC20Metadata.sol";
import {SiloOracleMock1} from "silo-oracles/test/foundry/_mocks/silo-oracles/SiloOracleMock1.sol";
import {MintableToken} from "silo-core/test/foundry/_common/MintableToken.sol";
import {TokenHelper} from "silo-core/contracts/lib/TokenHelper.sol";

import {MockOracleFactory} from "./common/MockOracleFactory.sol";

/*
 FOUNDRY_PROFILE=oracles forge test --mc ManageableOracleInitTest
*/
contract ManageableOracleInitTest is Test {
    address internal owner = makeAddr("Owner");
    uint32 internal constant timelock = 1 days;
    address internal baseToken;

    IManageableOracleFactory internal factory;
    SiloOracleMock1 internal oracleMock;

    function setUp() public {
        oracleMock = new SiloOracleMock1();
        factory = new ManageableOracleFactory();
        baseToken = oracleMock.baseToken();

        vm.mockCall(address(baseToken), abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ManageableOracle_cannotInitializeTwice_withOracle
        Test that after creating a ManageableOracle, we cannot call initialize again (with oracle)
    */
    function test_ManageableOracle_cannotInitializeTwice_withOracle() public {
        // Create ManageableOracle through factory
        IManageableOracle manageableOracle =
            factory.create(ISiloOracle(address(oracleMock)), owner, timelock, bytes32(0));

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        manageableOracle.initialize(ISiloOracle(address(oracleMock)), owner, timelock);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ManageableOracle_cannotInitialize_directlyCreated
        Test that when creating ManageableOracle directly (not through factory), we cannot initialize it
    */
    function test_ManageableOracle_cannotInitialize_directlyCreated() public {
        // Create ManageableOracle directly (not through factory)
        ManageableOracle manageableOracle = new ManageableOracle();

        // Try to call initialize - should revert with InvalidInitialization (because _disableInitializers was called in constructor)
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        manageableOracle.initialize(ISiloOracle(address(oracleMock)), owner, timelock);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ManageableOracle_directlyCreated_hasZeroOwner
        Test that when creating ManageableOracle directly (not through factory), owner is address(0)
    */
    function test_ManageableOracle_directlyCreated_hasZeroOwner() public {
        ManageableOracle manageableOracle = new ManageableOracle();
        assertEq(manageableOracle.owner(), address(0));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ManageableOracle_create_withOracle_getters
    */
    function test_ManageableOracle_create_withOracle_getters() public {
        IManageableOracle manageableOracle =
            factory.create(ISiloOracle(address(oracleMock)), owner, timelock, bytes32(0));

        _assertGettersAfterCreate(manageableOracle);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ManageableOracle_create_withFactory_getters
    */
    function test_ManageableOracle_create_withFactory_getters() public {
        (address mockFactory, bytes memory initData) = _mockOracleFactoryAndInitData(address(oracleMock));

        IManageableOracle manageableOracle = factory.create(mockFactory, initData, owner, timelock, bytes32(0));

        _assertGettersAfterCreate(manageableOracle);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ManageableOracle_initialize_revert_ZeroBaseToken
        Test that initialize reverts when baseToken is zero
    */
    function test_ManageableOracle_initialize_revert_ZeroBaseToken() public {
        IManageableOracle manageableOracle = _clonedOracle();

        vm.mockCall(
            address(oracleMock), abi.encodeWithSelector(IManageableOracle.baseToken.selector), abi.encode(address(0))
        );

        vm.expectRevert(TokenHelper.TokenIsNotAContract.selector);
        manageableOracle.initialize(ISiloOracle(address(oracleMock)), owner, timelock);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ManageableOracle_initialize_revert_ZeroOwner
        Test that initialize reverts when owner is zero
    */
    function test_ManageableOracle_initialize_revert_ZeroOwner() public {
        IManageableOracle manageableOracle = _clonedOracle();

        vm.expectRevert(IManageableOracle.ZeroOwner.selector);
        manageableOracle.initialize(ISiloOracle(address(oracleMock)), address(0), timelock);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ManageableOracle_initialize_revert_InvalidTimelock_tooLow
        Test that initialize reverts when timelock is too low
    */
    function test_ManageableOracle_initialize_revert_InvalidTimelock_tooLow() public {
        IManageableOracle manageableOracle = _clonedOracle();
        uint32 minTimelock = ManageableOracle(address(manageableOracle)).MIN_TIMELOCK();
        uint32 timelockTooLow = minTimelock - 1;

        vm.expectRevert(IManageableOracle.InvalidTimelock.selector);
        manageableOracle.initialize(ISiloOracle(address(oracleMock)), owner, timelockTooLow);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ManageableOracle_initialize_revert_InvalidTimelock_tooHigh
        Test that initialize reverts when timelock is too high
    */
    function test_ManageableOracle_initialize_revert_InvalidTimelock_tooHigh() public {
        IManageableOracle manageableOracle = _clonedOracle();
        uint32 maxTimelock = ManageableOracle(address(manageableOracle)).MAX_TIMELOCK();
        uint32 timelockTooHigh = maxTimelock + 1;

        vm.expectRevert(IManageableOracle.InvalidTimelock.selector);
        manageableOracle.initialize(ISiloOracle(address(oracleMock)), owner, timelockTooHigh);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ManageableOracle_initialize_revert_BaseTokenDecimalsMustBeGreaterThanZero
        Test that initialize reverts when baseToken has zero decimals
    */
    function test_ManageableOracle_initialize_revert_BaseTokenDecimalsMustBeGreaterThanZero() public {
        IManageableOracle manageableOracle = _clonedOracle();

        vm.mockCall(baseToken, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(0));

        vm.expectRevert(IManageableOracle.BaseTokenDecimalsMustBeGreaterThanZero.selector);
        manageableOracle.initialize(ISiloOracle(address(oracleMock)), owner, timelock);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ManageableOracle_initialize_revert_OracleQuoteFailed
        Test that initialize reverts when oracle quote returns zero
    */
    function test_ManageableOracle_initialize_revert_OracleQuoteFailed() public {
        IManageableOracle manageableOracle = _clonedOracle();
        address oracleMockZeroQuote = makeAddr("SiloOracleMockZeroQuote");

        vm.mockCall(
            oracleMockZeroQuote, abi.encodeWithSelector(IManageableOracle.baseToken.selector), abi.encode(baseToken)
        );
        vm.mockCall(
            oracleMockZeroQuote, abi.encodeWithSelector(ISiloOracle.quoteToken.selector), abi.encode(baseToken)
        );
        vm.mockCall(
            oracleMockZeroQuote, abi.encodeWithSelector(ISiloOracle.quote.selector, 1e18, baseToken), abi.encode(0)
        );

        vm.expectRevert(IManageableOracle.OracleQuoteFailed.selector);
        manageableOracle.initialize(ISiloOracle(oracleMockZeroQuote), owner, timelock);
    }

    function _mockOracleFactoryAndInitData(address _oracle)
        internal
        returns (address _mockFactory, bytes memory _initData)
    {
        _mockFactory = address(new MockOracleFactory());
        _initData = abi.encodeWithSelector(MockOracleFactory.create.selector, _oracle);

        vm.mockCall(_oracle, abi.encodeWithSelector(IManageableOracle.baseToken.selector), abi.encode(baseToken));
    }

    function _assertGettersAfterCreate(IManageableOracle _oracle) internal view {
        assertEq(_oracle.owner(), owner, "invalid owner");
        assertEq(address(_oracle.oracle()), address(oracleMock), "invalid oracle");

        (address pendingOracleValue, uint64 pendingOracleValidAt) = _oracle.pendingOracle();
        assertEq(pendingOracleValue, address(0), "invalid pendingOracle value");
        assertEq(pendingOracleValidAt, 0, "invalid pendingOracle validAt");
        assertEq(_oracle.timelock(), timelock, "invalid timelock");

        (uint192 pendingTimelockValue, uint64 pendingTimelockValidAt) = _oracle.pendingTimelock();
        assertEq(pendingTimelockValue, 0, "invalid pendingTimelock value");
        assertEq(pendingTimelockValidAt, 0, "invalid pendingTimelock validAt");

        (address pendingOwnershipValue, uint64 pendingOwnershipValidAt) = _oracle.pendingOwnership();
        assertEq(pendingOwnershipValue, address(0), "invalid pendingOwnership value");
        assertEq(pendingOwnershipValidAt, 0, "invalid pendingOwnership validAt");
        assertEq(Aggregator(address(_oracle)).baseToken(), baseToken, "invalid baseToken");
        assertEq(_oracle.baseTokenDecimals(), 18, "invalid baseTokenDecimals");
        assertEq(ISiloOracle(address(_oracle)).quoteToken(), oracleMock.quoteToken(), "invalid quoteToken");
    }

    function _clonedOracle() internal returns (IManageableOracle) {
        return IManageableOracle(Clones.cloneDeterministic(address(factory.ORACLE_IMPLEMENTATION()), bytes32(0)));
    }
}
