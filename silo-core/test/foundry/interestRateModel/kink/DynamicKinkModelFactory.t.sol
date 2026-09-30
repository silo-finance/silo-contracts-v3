// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {console2} from "forge-std/console2.sol";

import {Math} from "openzeppelin5/utils/math/Math.sol";


import {
    DynamicKinkModel, IDynamicKinkModel
} from "../../../../contracts/interestRateModel/kink/DynamicKinkModel.sol";
import {DynamicKinkModelFactory} from "../../../../contracts/interestRateModel/kink/DynamicKinkModelFactory.sol";
import {IDynamicKinkModelFactory} from "../../../../contracts/interfaces/IDynamicKinkModelFactory.sol";
import {IInterestRateModel} from "../../../../contracts/interfaces/IInterestRateModel.sol";

import {KinkCommonTest} from "./KinkCommon.t.sol";

import {RandomLib} from "../../_common/RandomLib.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

contract DynamicKinkFactoryMock is DynamicKinkModelFactory {
    using SafeCast for uint256;

    constructor() DynamicKinkModelFactory(new DynamicKinkModel()) {}

    function castConfig(IDynamicKinkModel.UserFriendlyConfig calldata _default)
        external
        pure
        returns (IDynamicKinkModel.UserFriendlyConfigInt memory)
    {
        return _castConfig(_default);
    }
}

/* 
FOUNDRY_PROFILE=core_test forge test --mc DynamicKinkModelFactoryTest -vv
*/
contract DynamicKinkModelFactoryTest is KinkCommonTest {
    using RandomLib for uint256;
    using RandomLib for uint72;
    using RandomLib for uint64;
    using RandomLib for uint32;

    uint256 constant DP = 1e18;

    IDynamicKinkModel.ImmutableArgs immutableArgs = _defaultImmutableArgs();

    function setUp() public {
        IDynamicKinkModel.Config memory emptyConfig;
        irm = DynamicKinkModel(
            address(FACTORY.create(emptyConfig, immutableArgs, address(this), address(this), bytes32(0)))
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_create_revertOnInvalidConfig -vv
    */
    function test_kink_create_revertOnInvalidConfig(IDynamicKinkModel.Config memory _config) public {
        vm.assume(!_isValidConfig(_config));

        vm.expectRevert();
        FACTORY.create(_config, immutableArgs, address(this), address(this), bytes32(0));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_predictAddress_pass -vv
    */
    function test_kink_predictAddress_pass(
        RandomKinkConfig memory _config,
        address _deployer,
        bytes32 _externalSalt
    ) public whenValidConfig(_config) {
        vm.assume(_deployer != address(0));

        address predictedAddress = FACTORY.predictAddress(_deployer, _externalSalt);
        IDynamicKinkModel.Config memory config = _toConfig(_config);
        FACTORY.verifyConfig(config);

        vm.prank(_deployer);
        IInterestRateModel deployedIrm =
            FACTORY.create(config, immutableArgs, address(this), address(this), _externalSalt);

        assertEq(
            predictedAddress, address(deployedIrm), "predicted address is not the same as the deployed address"
        );
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_create_pass_fuzz -vv
    */
    function test_kink_create_pass_fuzz(
        RandomKinkConfig memory _config,
        IDynamicKinkModel.ImmutableArgs memory _immutableArgs
    ) public whenValidConfig(_config) makeValidImmutableArgs(_immutableArgs) {
        address predictedAddress = FACTORY.predictAddress(address(this), bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit IDynamicKinkModelFactory.NewDynamicKinkModel(IDynamicKinkModel(predictedAddress));

        FACTORY.create(_toConfig(_config), _immutableArgs, address(this), address(this), bytes32(0));

        assertTrue(FACTORY.createdByFactory(predictedAddress));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_generateConfig_works -vv
    */
    function test_kink_generateConfig_works_fuzz(IDynamicKinkModel.UserFriendlyConfig memory _in) public {
        // _printUserFriendlyConfig(_in);

        // start help fuzzing ----------------------------
        // with straight config as input, we fail with too many rejection,
        // so we need to "help" to build config that will pass
        _buildRandomUserFriendlyConfig(_in);
        // end help fuzzing ------------------------------

        // _printUserFriendlyConfig(_in);

        try FACTORY.generateConfig(_in) returns (IDynamicKinkModel.Config memory config) {
            // any config can be used to create IRM
            FACTORY.create(config, immutableArgs, address(this), address(this), bytes32(0));
        } catch {
            vm.assume(false);
        }
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_generateConfig_reverts -vv
    */
    function test_kink_generateConfig_reverts() public {
        IDynamicKinkModel.UserFriendlyConfig memory userCfg;

        // forge-lint: disable-next-line(unsafe-typecast)
        userCfg.u1 = uint64(DP);
        vm.expectRevert(IDynamicKinkModel.InvalidU1.selector);
        FACTORY.generateConfig(userCfg);

        userCfg.u1 = 1;
        userCfg.u2 = userCfg.u1;
        vm.expectRevert(IDynamicKinkModel.InvalidU1.selector);
        FACTORY.generateConfig(userCfg);

        userCfg.u2 = 2;
        userCfg.ucrit = userCfg.u2;
        vm.expectRevert(IDynamicKinkModel.InvalidU2.selector);
        FACTORY.generateConfig(userCfg);

        // forge-lint: disable-next-line(unsafe-typecast)
        userCfg.ucrit = uint64(DP);
        vm.expectRevert(IDynamicKinkModel.InvalidUcrit.selector);
        FACTORY.generateConfig(userCfg);

        // forge-lint: disable-next-line(unsafe-typecast)
        userCfg.ucrit = uint64(DP - 1);
        vm.expectRevert(IDynamicKinkModel.InvalidRcritMin.selector);
        FACTORY.generateConfig(userCfg);

        userCfg.rmin = 1;
        vm.expectRevert(IDynamicKinkModel.InvalidRcritMin.selector);
        FACTORY.generateConfig(userCfg);

        userCfg.rcritMin = 1;
        vm.expectRevert(IDynamicKinkModel.InvalidRcritMin.selector);
        FACTORY.generateConfig(userCfg);

        userCfg.rcritMin = 2;
        vm.expectRevert(IDynamicKinkModel.InvalidRcritMin.selector);
        FACTORY.generateConfig(userCfg);

        userCfg.rcritMax = 2;
        vm.expectRevert(IDynamicKinkModel.InvalidRcritMax.selector);
        FACTORY.generateConfig(userCfg);

        userCfg.r100 = 2;
        vm.expectRevert(IDynamicKinkModel.InvalidRcritMax.selector);
        FACTORY.generateConfig(userCfg);

        userCfg.r100 = 3;
        vm.expectRevert(IDynamicKinkModel.InvalidTMin.selector);
        FACTORY.generateConfig(userCfg);

        userCfg.tMin = 1;
        vm.expectRevert(IDynamicKinkModel.InvalidTCrit.selector);
        FACTORY.generateConfig(userCfg);

        userCfg.tcrit = 1;
        vm.expectRevert(IDynamicKinkModel.InvalidTCrit.selector);
        FACTORY.generateConfig(userCfg);

        userCfg.t2 = 365 days * 100;
        vm.expectRevert(IDynamicKinkModel.InvalidT2.selector);
        FACTORY.generateConfig(userCfg);

        userCfg.t2 = 365 days * 100 - 1;
        vm.expectRevert(IDynamicKinkModel.InvalidTLow.selector);
        FACTORY.generateConfig(userCfg);

        userCfg.tlow = 1;
        vm.expectRevert(IDynamicKinkModel.InvalidT1.selector);
        FACTORY.generateConfig(userCfg);

        userCfg.t1 = 365 days * 100;
        vm.expectRevert(IDynamicKinkModel.InvalidT1.selector);
        FACTORY.generateConfig(userCfg);

        userCfg.t1 = 365 days * 100 - 1;
        vm.expectRevert(IDynamicKinkModel.InvalidAlpha.selector);
        FACTORY.generateConfig(userCfg);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --mt test_kink_castConfig -vv
    */
    function test_kink_castConfig(IDynamicKinkModel.UserFriendlyConfig memory _in) public {
        DynamicKinkFactoryMock factory = new DynamicKinkFactoryMock();

        IDynamicKinkModel.UserFriendlyConfigInt memory _out = factory.castConfig(_in);

        // forge-lint: disable-next-line(asm-keccak256)
        bytes32 hashIn = keccak256(abi.encode(_in));
        // forge-lint: disable-next-line(asm-keccak256)
        bytes32 hashOut = keccak256(abi.encode(_out));

        assertEq(hashIn, hashOut, "castConfig fail In != Out");
    }

    function _printUserFriendlyConfig(IDynamicKinkModel.UserFriendlyConfig memory _in) internal pure {
        console2.log("--------------------------------");
        console2.log("ulow", _in.ulow);
        console2.log("ucrit", _in.ucrit);
        console2.log("u1", _in.u1);
        console2.log("u2", _in.u2);
        console2.log("rmin", _in.rmin);
        console2.log("rcritMin", _in.rcritMin);
        console2.log("rcritMax", _in.rcritMax);
        console2.log("r100", _in.r100);
        console2.log("t1", _in.t1);
        console2.log("t2", _in.t2);
        console2.log("tlow", _in.tlow);
        console2.log("tcrit", _in.tcrit);
        console2.log("tMin", _in.tMin);
    }

    function _buildRandomUserFriendlyConfig(IDynamicKinkModel.UserFriendlyConfig memory _in) internal pure {
        _in.ulow = uint64(_in.ulow.randomBelow(0, DP - 4)); // -4 is to have space for other values, for every `<` we need to sub 1
        _in.u1 = uint64(_in.u1.randomInside(_in.ulow, DP - 3));
        _in.u2 = uint64(_in.u2.randomInside(_in.u1, DP - 2));
        _in.ucrit = uint64(_in.ucrit.randomInside(_in.u2, DP));

        // minimal values: 0 <= rmin < rcritMin < rritMax <= r100 --> 0 <= 0 < 1 < 2 <= r100
        _in.r100 = uint72(Math.max(2, _in.r100));
        _in.rmin = uint72(_in.rmin.randomBelow(0, _in.r100 - 1));
        _in.rcritMin = uint72(_in.rcritMin.randomInside(_in.rmin, _in.r100));
        _in.rcritMax = uint72(_in.rcritMax.randomAbove(_in.rcritMin, _in.r100));

        uint256 y = 365 days; // for purpose of fuzzing, 1y is a limit for time values

        // 0 < tMin <= tcrit <= t2 < 100y
        _in.tMin = uint32(_in.tMin.randomBetween(1, y));
        _in.tcrit = uint32(_in.tcrit.randomBetween(_in.tMin, y));
        _in.t2 = uint32(_in.t2.randomBetween(_in.tcrit, y));

        // 0 < tlow <= t1 < 100y
        _in.tlow = uint32(_in.tlow.randomBetween(1, y));
        _in.t1 = uint32(_in.t1.randomBetween(_in.tlow, y));
    }
}
