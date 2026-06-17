// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {DualOracleFactory} from "silo-oracles/contracts/dualOracle/DualOracleFactory.sol";
import {IDualOracle} from "silo-oracles/contracts/interfaces/IDualOracle.sol";
import {IDualOracleFactory} from "silo-oracles/contracts/interfaces/IDualOracleFactory.sol";
import {ISiloOracle} from "silo-core/contracts/interfaces/ISiloOracle.sol";
import {IERC20Metadata} from "silo-oracles/test/foundry/interfaces/IERC20Metadata.sol";
import {SiloOracleMock1} from "silo-oracles/test/foundry/_mocks/silo-oracles/SiloOracleMock1.sol";

import {MockOracleFactory} from "./common/MockOracleFactory.sol";

/*
 FOUNDRY_PROFILE=oracles forge test --mc DualOracleFactoryTest
*/
contract DualOracleFactoryTest is Test {
    uint256 internal constant LOWER_BOUND = 0.5e18;
    uint256 internal constant UPPER_BOUND = 2e18;
    uint32 internal constant TIMELOCK = 1 days;

    DualOracleFactory internal factory;
    SiloOracleMock1 internal oracleMock;
    address internal owner;
    address internal priceSetter;
    address internal baseToken;

    function setUp() public {
        oracleMock = new SiloOracleMock1();
        factory = new DualOracleFactory();
        owner = makeAddr("Owner");
        priceSetter = makeAddr("PriceSetter");
        baseToken = oracleMock.baseToken();

        vm.mockCall(baseToken, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_ORACLE_IMPLEMENTATION_isSet
    */
    function test_ORACLE_IMPLEMENTATION_isSet() public view {
        assertTrue(address(factory.ORACLE_IMPLEMENTATION()) != address(0), "implementation should not be zero");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_predictAddress_revert_DeployerCannotBeZero
    */
    function test_predictAddress_revert_DeployerCannotBeZero() public {
        vm.expectRevert(IDualOracleFactory.DeployerCannotBeZero.selector);
        factory.predictAddress(address(0), bytes32(0));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_predictAddress_matchesDeploy
    */
    function test_predictAddress_matchesDeploy() public {
        address predicted = factory.predictAddress(address(this), bytes32(0));
        IDualOracle deployed = factory.create(
            ISiloOracle(address(oracleMock)), owner, priceSetter, TIMELOCK, LOWER_BOUND, UPPER_BOUND, bytes32(0)
        );
        assertEq(address(deployed), predicted, "predicted address should match deployed");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_predictAddress_differentDeployers_differentAddresses
    */
    function test_predictAddress_differentDeployers_differentAddresses() public {
        address addr1 = factory.predictAddress(makeAddr("Deployer1"), bytes32(0));
        address addr2 = factory.predictAddress(makeAddr("Deployer2"), bytes32(0));
        assertTrue(addr1 != addr2, "different deployers should yield different addresses");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_predictAddress_frontrun_doesNotAffectOwnPrediction
    */
    function test_predictAddress_frontrun_doesNotAffectOwnPrediction() public {
        address predicted = factory.predictAddress(address(this), bytes32(0));

        vm.prank(makeAddr("Frontrunner"));
        factory.create(
            ISiloOracle(address(oracleMock)), owner, priceSetter, TIMELOCK, LOWER_BOUND, UPPER_BOUND, bytes32(0)
        );

        IDualOracle deployed = factory.create(
            ISiloOracle(address(oracleMock)), owner, priceSetter, TIMELOCK, LOWER_BOUND, UPPER_BOUND, bytes32(0)
        );
        assertEq(address(deployed), predicted, "frontrun should not affect our predicted address");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_create_withOracle_registersInFactory
    */
    function test_create_withOracle_registersInFactory() public {
        IDualOracle deployed = factory.create(
            ISiloOracle(address(oracleMock)), owner, priceSetter, TIMELOCK, LOWER_BOUND, UPPER_BOUND, bytes32(0)
        );
        assertTrue(factory.createdInFactory(address(deployed)), "oracle should be registered");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_create_withOracle_emitsDualOracleCreated
    */
    function test_create_withOracle_emitsDualOracleCreated() public {
        address predicted = factory.predictAddress(address(this), bytes32(0));

        vm.expectEmit(true, false, false, false, address(factory));
        emit IDualOracleFactory.DualOracleCreated(predicted);

        factory.create(
            ISiloOracle(address(oracleMock)), owner, priceSetter, TIMELOCK, LOWER_BOUND, UPPER_BOUND, bytes32(0)
        );
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_create_withOracle_differentSalts_differentAddresses
    */
    function test_create_withOracle_differentSalts_differentAddresses() public {
        IDualOracle oracle1 = factory.create(
            ISiloOracle(address(oracleMock)), owner, priceSetter, TIMELOCK, LOWER_BOUND, UPPER_BOUND, bytes32(uint256(1))
        );
        IDualOracle oracle2 = factory.create(
            ISiloOracle(address(oracleMock)), owner, priceSetter, TIMELOCK, LOWER_BOUND, UPPER_BOUND, bytes32(uint256(2))
        );
        assertTrue(address(oracle1) != address(oracle2), "different salts should produce different addresses");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_create_withOracle_sameSalt_differentAddresses_dueToNonce
    */
    function test_create_withOracle_sameSalt_differentAddresses_dueToNonce() public {
        IDualOracle oracle1 = factory.create(
            ISiloOracle(address(oracleMock)), owner, priceSetter, TIMELOCK, LOWER_BOUND, UPPER_BOUND, bytes32(0)
        );
        IDualOracle oracle2 = factory.create(
            ISiloOracle(address(oracleMock)), owner, priceSetter, TIMELOCK, LOWER_BOUND, UPPER_BOUND, bytes32(0)
        );
        assertTrue(
            address(oracle1) != address(oracle2),
            "nonce increment should produce different addresses for same salt"
        );
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_create_withUnderlyingFactory_works
    */
    function test_create_withUnderlyingFactory_works() public {
        MockOracleFactory mockFactory = new MockOracleFactory();
        bytes memory initData = abi.encodeWithSelector(MockOracleFactory.create.selector, address(oracleMock));

        IDualOracle deployed = factory.create(
            address(mockFactory), initData, owner, priceSetter, TIMELOCK, LOWER_BOUND, UPPER_BOUND, bytes32(0)
        );

        assertEq(address(deployed.oracle()), address(oracleMock), "wrong underlying oracle");
        assertTrue(factory.createdInFactory(address(deployed)), "oracle should be registered");
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_create_withUnderlyingFactory_revert_ZeroFactory
    */
    function test_create_withUnderlyingFactory_revert_ZeroFactory() public {
        vm.expectRevert(IDualOracleFactory.ZeroFactory.selector);
        factory.create(address(0), bytes(""), owner, priceSetter, TIMELOCK, LOWER_BOUND, UPPER_BOUND, bytes32(0));
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_create_withUnderlyingFactory_revert_FailedToCreateUnderlyingOracle_callReverts
    */
    function test_create_withUnderlyingFactory_revert_FailedToCreateUnderlyingOracle_callReverts() public {
        address failingFactory = makeAddr("FailingFactory");
        vm.mockCallRevert(failingFactory, bytes(""), abi.encodePacked("factory failed"));

        vm.expectRevert(IDualOracleFactory.FailedToCreateUnderlyingOracle.selector);
        factory.create(
            failingFactory, bytes(""), owner, priceSetter, TIMELOCK, LOWER_BOUND, UPPER_BOUND, bytes32(0)
        );
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_create_withUnderlyingFactory_revert_FailedToCreateUnderlyingOracle_wrongReturnSize
    */
    function test_create_withUnderlyingFactory_revert_FailedToCreateUnderlyingOracle_wrongReturnSize() public {
        address badReturnFactory = makeAddr("BadReturnFactory");
        vm.mockCall(badReturnFactory, bytes(""), abi.encode(address(oracleMock), address(oracleMock)));

        vm.expectRevert(IDualOracleFactory.FailedToCreateUnderlyingOracle.selector);
        factory.create(
            badReturnFactory, bytes(""), owner, priceSetter, TIMELOCK, LOWER_BOUND, UPPER_BOUND, bytes32(0)
        );
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_create_withUnderlyingFactory_revert_FailedToCreateUnderlyingOracle_emptyReturn
    */
    function test_create_withUnderlyingFactory_revert_FailedToCreateUnderlyingOracle_emptyReturn() public {
        address emptyReturnFactory = makeAddr("EmptyReturnFactory");
        vm.mockCall(emptyReturnFactory, bytes(""), bytes(""));

        vm.expectRevert(IDualOracleFactory.FailedToCreateUnderlyingOracle.selector);
        factory.create(
            emptyReturnFactory, bytes(""), owner, priceSetter, TIMELOCK, LOWER_BOUND, UPPER_BOUND, bytes32(0)
        );
    }

    /*
        FOUNDRY_PROFILE=oracles forge test --mt test_createdInFactory_false_forExternalOracle
    */
    function test_createdInFactory_false_forExternalOracle() public {
        assertFalse(factory.createdInFactory(address(oracleMock)), "external oracle should not be in factory");
        assertFalse(factory.createdInFactory(makeAddr("Random")), "random address should not be in factory");
    }
}
