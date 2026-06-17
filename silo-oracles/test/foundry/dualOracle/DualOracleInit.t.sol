// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Clones} from "openzeppelin5/proxy/Clones.sol";
import {Initializable} from "openzeppelin5-upgradeable/proxy/utils/Initializable.sol";

import {DualOracleFactory} from "silo-oracles/contracts/dualOracle/DualOracleFactory.sol";
import {DualOracle} from "silo-oracles/contracts/dualOracle/DualOracle.sol";
import {IDualOracle} from "silo-oracles/contracts/interfaces/IDualOracle.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IERC20Metadata} from "silo-oracles/test/foundry/interfaces/IERC20Metadata.sol";
import {SiloOracleMock1} from "silo-oracles/test/foundry/_mocks/silo-oracles/SiloOracleMock1.sol";

/*
 FOUNDRY_PROFILE=oracles forge test --mc DualOracleInitTest
*/
contract DualOracleInitTest is Test {
    uint256 internal constant LOWER_BOUND = 0.5e18;
    uint256 internal constant UPPER_BOUND = 2e18;
    uint32 internal constant TIMELOCK = 1 days;

    address internal owner = makeAddr("Owner");
    address internal priceSetter = makeAddr("PriceSetter");

    DualOracleFactory internal factory;
    SiloOracleMock1 internal oracleMock;
    address internal baseToken;

    function setUp() public {
        oracleMock = new SiloOracleMock1();
        factory = new DualOracleFactory();
        baseToken = oracleMock.baseToken();

        vm.mockCall(baseToken, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_DualOracle_cannotInitializeTwice
    */
    function test_DualOracle_cannotInitializeTwice() public {
        IDualOracle dualOracle = factory.create(
            ISiloOracle(address(oracleMock)), owner, priceSetter, TIMELOCK, LOWER_BOUND, UPPER_BOUND, bytes32(0)
        );

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        DualOracle(address(dualOracle)).initialize(
            ISiloOracle(address(oracleMock)), owner, priceSetter, TIMELOCK, LOWER_BOUND, UPPER_BOUND
        );
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_DualOracle_cannotInitialize_directlyCreated
    */
    function test_DualOracle_cannotInitialize_directlyCreated() public {
        DualOracle direct = new DualOracle();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        direct.initialize(ISiloOracle(address(oracleMock)), owner, priceSetter, TIMELOCK, LOWER_BOUND, UPPER_BOUND);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_DualOracle_directlyCreated_hasNoAdmin
    */
    function test_DualOracle_directlyCreated_hasNoAdmin() public {
        DualOracle direct = new DualOracle();
        assertFalse(direct.hasRole(direct.DEFAULT_ADMIN_ROLE(), owner));
        assertFalse(direct.hasRole(direct.DEFAULT_ADMIN_ROLE(), address(this)));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_DualOracle_initialize_revert_ZeroOracle
    */
    function test_DualOracle_initialize_revert_ZeroOracle() public {
        DualOracle clone = _clonedOracle();

        vm.expectRevert(IDualOracle.ZeroOracle.selector);
        clone.initialize(ISiloOracle(address(0)), owner, priceSetter, TIMELOCK, LOWER_BOUND, UPPER_BOUND);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_DualOracle_initialize_revert_ZeroOwner
    */
    function test_DualOracle_initialize_revert_ZeroOwner() public {
        DualOracle clone = _clonedOracle();

        vm.expectRevert(IDualOracle.ZeroOwner.selector);
        clone.initialize(ISiloOracle(address(oracleMock)), address(0), priceSetter, TIMELOCK, LOWER_BOUND, UPPER_BOUND);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_DualOracle_initialize_revert_LowerBoundMustBeGreaterThanZero
    */
    function test_DualOracle_initialize_revert_LowerBoundMustBeGreaterThanZero() public {
        DualOracle clone = _clonedOracle();

        vm.expectRevert(IDualOracle.LowerBoundMustBeGreaterThanZero.selector);
        clone.initialize(ISiloOracle(address(oracleMock)), owner, priceSetter, TIMELOCK, 0, UPPER_BOUND);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_DualOracle_initialize_revert_InvalidBounds_equal
    */
    function test_DualOracle_initialize_revert_InvalidBounds_equal() public {
        DualOracle clone = _clonedOracle();

        vm.expectRevert(IDualOracle.InvalidBounds.selector);
        clone.initialize(ISiloOracle(address(oracleMock)), owner, priceSetter, TIMELOCK, UPPER_BOUND, UPPER_BOUND);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_DualOracle_initialize_revert_InvalidBounds_lowerGtUpper
    */
    function test_DualOracle_initialize_revert_InvalidBounds_lowerGtUpper() public {
        DualOracle clone = _clonedOracle();

        vm.expectRevert(IDualOracle.InvalidBounds.selector);
        clone.initialize(
            ISiloOracle(address(oracleMock)), owner, priceSetter, TIMELOCK, UPPER_BOUND + 1, UPPER_BOUND
        );
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_DualOracle_initialize_revert_BaseTokenDecimalsMustBeGreaterThanZero
    */
    function test_DualOracle_initialize_revert_BaseTokenDecimalsMustBeGreaterThanZero() public {
        DualOracle clone = _clonedOracle();

        vm.mockCall(baseToken, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(uint8(0)));

        vm.expectRevert(IDualOracle.BaseTokenDecimalsMustBeGreaterThanZero.selector);
        clone.initialize(ISiloOracle(address(oracleMock)), owner, priceSetter, TIMELOCK, LOWER_BOUND, UPPER_BOUND);
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_DualOracle_initialize_getters
    */
    function test_DualOracle_initialize_getters() public {
        IDualOracle dualOracle = factory.create(
            ISiloOracle(address(oracleMock)), owner, priceSetter, TIMELOCK, LOWER_BOUND, UPPER_BOUND, bytes32(0)
        );

        DualOracle d = DualOracle(address(dualOracle));

        assertTrue(d.hasRole(d.DEFAULT_ADMIN_ROLE(), owner), "owner should have DEFAULT_ADMIN_ROLE");
        assertTrue(d.hasRole(d.PRICE_SETTER_ROLE(), priceSetter), "priceSetter should have PRICE_SETTER_ROLE");
        assertFalse(d.hasRole(d.PRICE_SETTER_ROLE(), owner), "owner should not have PRICE_SETTER_ROLE by default");
        assertEq(address(dualOracle.oracle()), address(oracleMock), "oracle mismatch");
        assertEq(dualOracle.timelock(), TIMELOCK, "timelock mismatch");
        assertEq(dualOracle.lowerPriceBound(), LOWER_BOUND, "lowerPriceBound mismatch");
        assertEq(dualOracle.upperPriceBound(), UPPER_BOUND, "upperPriceBound mismatch");
        assertEq(dualOracle.baseToken(), baseToken, "baseToken mismatch");
        assertEq(dualOracle.baseTokenDecimals(), 18, "baseTokenDecimals mismatch");
        assertEq(dualOracle.quoteToken(), oracleMock.quoteToken(), "quoteToken mismatch");
        assertEq(dualOracle.manualPrice(), 0, "manualPrice should be zero");
        assertEq(dualOracle.overrideValidAt(), 0, "overrideValidAt should be zero");
        assertFalse(dualOracle.isOverrideActive(), "override should not be active");
        assertFalse(d.paused(), "should not be paused");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_DualOracle_initialize_withZeroPriceSetter_succeeds
    */
    function test_DualOracle_initialize_withZeroPriceSetter_succeeds() public {
        IDualOracle dualOracle = factory.create(
            ISiloOracle(address(oracleMock)), owner, address(0), TIMELOCK, LOWER_BOUND, UPPER_BOUND, bytes32(0)
        );

        DualOracle d = DualOracle(address(dualOracle));
        assertTrue(d.hasRole(d.DEFAULT_ADMIN_ROLE(), owner));
        assertEq(d.getRoleMemberCount(d.PRICE_SETTER_ROLE()), 0, "no price setter should be assigned");
    }

    // ─── helpers ──────────────────────────────────────────────────────────────

    uint256 private _cloneCount;

    function _clonedOracle() internal returns (DualOracle) {
        bytes32 salt = keccak256(abi.encode("clone", _cloneCount++));
        return DualOracle(Clones.cloneDeterministic(address(factory.ORACLE_IMPLEMENTATION()), salt));
    }
}
