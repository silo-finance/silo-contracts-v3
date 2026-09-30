// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {Ownable} from "openzeppelin5/access/Ownable.sol";
import {IERC4626} from "openzeppelin5/interfaces/IERC4626.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISiloFactory, SiloFactory} from "silo-core/contracts/SiloFactory.sol";

/*
forge test -vv --mc SiloFactorySettersTest
*/
contract SiloFactorySettersTest is Test {
    SiloFactory public siloFactory;

    address siloImpl = address(100001);
    address shareCollateralTokenImpl = address(100002);
    address shareDebtTokenImpl = address(100003);
    address daoFeeReceiver = address(100004);

    address hacker = makeAddr("Hacker");

    function setUp() public {
        siloFactory = new SiloFactory(daoFeeReceiver);
    }

    /*
    forge test -vvv --mt test_setDaoFee_reverts
    */
    function test_setDaoFee_reverts() public {
        uint128 maxFee = uint128(siloFactory.MAX_FEE());

        ISiloFactory.Range memory range = siloFactory.daoFeeRange();

        vm.expectRevert(ISiloFactory.MaxFeeExceeded.selector);
        siloFactory.setDaoFee(maxFee, maxFee + 1);

        vm.expectRevert(ISiloFactory.InvalidFeeRange.selector);
        siloFactory.setDaoFee(range.min + 1, range.min);

        vm.expectRevert(ISiloFactory.SameRange.selector);
        siloFactory.setDaoFee(range.min, range.max);

        vm.prank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, hacker));
        siloFactory.setDaoFee(range.min, range.max);

        // counter example
        siloFactory.setDaoFee(0, maxFee);
    }

    function test_setDaoFee_pass(uint128 _newMinDaoFee, uint128 _newMaxDaoFee) public {
        uint256 maxFee = siloFactory.MAX_FEE();

        vm.assume(_newMaxDaoFee <= maxFee);
        vm.assume(_newMinDaoFee <= _newMaxDaoFee);

        siloFactory.setDaoFee(_newMinDaoFee, _newMaxDaoFee);

        ISiloFactory.Range memory newRange = siloFactory.daoFeeRange();

        assertEq(newRange.min, _newMinDaoFee, "_newMinDaoFee");
        assertEq(newRange.max, _newMaxDaoFee, "_newMaxDaoFee");
    }

    /*
    forge test -vv --mt test_setMaxDeployerFee
    */
    function test_setMaxDeployerFee(uint256 _newMaxDeployerFee) public {
        uint256 maxFee = siloFactory.MAX_FEE();

        vm.assume(_newMaxDeployerFee <= maxFee);

        vm.expectRevert(ISiloFactory.MaxFeeExceeded.selector);
        siloFactory.setMaxDeployerFee(maxFee + 1);

        vm.prank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, hacker));
        siloFactory.setMaxDeployerFee(_newMaxDeployerFee);

        siloFactory.setMaxDeployerFee(_newMaxDeployerFee);

        assertEq(siloFactory.maxDeployerFee(), _newMaxDeployerFee);
    }

    /*
    forge test -vv --mt test_setMaxFlashloanFee
    */
    function test_setMaxFlashloanFee(uint256 _newMaxFlashloanFee) public {
        uint256 maxFee = siloFactory.MAX_FEE();

        vm.assume(_newMaxFlashloanFee <= maxFee);

        vm.expectRevert(ISiloFactory.MaxFeeExceeded.selector);
        siloFactory.setMaxFlashloanFee(maxFee + 1);

        vm.prank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, hacker));
        siloFactory.setMaxFlashloanFee(_newMaxFlashloanFee);

        siloFactory.setMaxFlashloanFee(_newMaxFlashloanFee);

        assertEq(siloFactory.maxFlashloanFee(), _newMaxFlashloanFee);
    }

    /*
    forge test -vv --mt test_setMaxLiquidationFee
    */
    function test_setMaxLiquidationFee(uint256 _newMaxLiquidationFee) public {
        uint256 maxFee = siloFactory.MAX_FEE();

        vm.assume(_newMaxLiquidationFee <= maxFee);

        vm.expectRevert(ISiloFactory.MaxFeeExceeded.selector);
        siloFactory.setMaxLiquidationFee(maxFee + 1);

        vm.prank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, hacker));
        siloFactory.setMaxLiquidationFee(_newMaxLiquidationFee);

        siloFactory.setMaxLiquidationFee(_newMaxLiquidationFee);

        assertEq(siloFactory.maxLiquidationFee(), _newMaxLiquidationFee);
    }

    /*
    forge test -vv --mt test_setDaoFeeReceiver
    */
    function test_setDaoFeeReceiver(address _newDaoFeeReceiver) public {
        vm.assume(_newDaoFeeReceiver != address(0));

        vm.expectRevert(ISiloFactory.DaoFeeReceiverZeroAddress.selector);
        siloFactory.setDaoFeeReceiver(address(0));

        vm.prank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, hacker));
        siloFactory.setDaoFeeReceiver(_newDaoFeeReceiver);

        siloFactory.setDaoFeeReceiver(_newDaoFeeReceiver);

        assertEq(siloFactory.daoFeeReceiver(), _newDaoFeeReceiver);

        address silo = makeAddr("Silo");
        address asset = makeAddr("asset");
        address config = makeAddr("SiloConfig");

        vm.mockCall(silo, abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(asset));

        vm.mockCall(silo, abi.encodeWithSelector(ISilo.config.selector), abi.encode(config));

        vm.mockCall(config, abi.encodeWithSelector(ISiloConfig.SILO_ID.selector), abi.encode(1));

        (address dao, address deployer) = siloFactory.getFeeReceivers(silo);

        assertEq(dao, _newDaoFeeReceiver);
        assertEq(deployer, address(0));
    }

    /*
    forge test -vv --mt test_setDaoFeeReceiverForAsset
    */
    function test_setDaoFeeReceiverForAsset() public {
        address silo = makeAddr("silo");
        address asset = makeAddr("siloAsset");
        address assetDaoFeeReceiver = makeAddr("assetDaoFeeReceiverForSilo");

        _assertDaoFeeReceiver(silo, daoFeeReceiver, "default receiver");

        vm.expectRevert(ISiloFactory.DaoFeeReceiverZeroAddress.selector);
        siloFactory.setDaoFeeReceiverForAsset(asset, address(0));

        vm.prank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, hacker));
        siloFactory.setDaoFeeReceiverForAsset(asset, assetDaoFeeReceiver);

        siloFactory.setDaoFeeReceiverForAsset(asset, assetDaoFeeReceiver);
        _assertDaoFeeReceiver(silo, assetDaoFeeReceiver, "assetDaoFeeReceiver set");

        vm.expectRevert(ISiloFactory.SameDaoFeeReceiver.selector);
        siloFactory.setDaoFeeReceiverForAsset(asset, assetDaoFeeReceiver);

        siloFactory.setDaoFeeReceiverForAsset(asset, address(0));
        _assertDaoFeeReceiver(silo, daoFeeReceiver, "asset setup reset, back to default receiver");
    }

    /*
    forge test -vv --mt test_setDaoFeeReceiverForSilo
    */
    function test_setDaoFeeReceiverForSilo() public {
        address silo = makeAddr("silo");
        address siloDaoFeeReceiver = makeAddr("siloDaoFeeReceiverForSilo");

        _assertDaoFeeReceiver(silo, daoFeeReceiver, "default receiver");

        vm.expectRevert(ISiloFactory.DaoFeeReceiverZeroAddress.selector);
        siloFactory.setDaoFeeReceiverForSilo(silo, address(0));

        vm.prank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, hacker));
        siloFactory.setDaoFeeReceiverForSilo(silo, siloDaoFeeReceiver);

        siloFactory.setDaoFeeReceiverForSilo(silo, siloDaoFeeReceiver);
        _assertDaoFeeReceiver(silo, siloDaoFeeReceiver, "siloDaoFeeReceiver set");

        vm.expectRevert(ISiloFactory.SameDaoFeeReceiver.selector);
        siloFactory.setDaoFeeReceiverForSilo(silo, siloDaoFeeReceiver);

        siloFactory.setDaoFeeReceiverForSilo(silo, address(0));
        _assertDaoFeeReceiver(silo, daoFeeReceiver, "silo setup reset, back to default receiver");
    }

    /*
    forge test -vv --mt test_setDaoFeeReceiverFlow
    */
    function test_setDaoFeeReceiverFlow() public {
        address silo = makeAddr("silo");
        address asset = makeAddr("siloAsset");
        address siloDaoFeeReceiver = makeAddr("DaoFeeReceiverForSilo");
        address assetDaoFeeReceiver = makeAddr("DaoFeeReceiverForAsset");

        _assertDaoFeeReceiver(silo, daoFeeReceiver, "default receiver");

        siloFactory.setDaoFeeReceiverForAsset(asset, assetDaoFeeReceiver);
        _assertDaoFeeReceiver(silo, assetDaoFeeReceiver, "assetDaoFeeReceiver set");

        siloFactory.setDaoFeeReceiverForSilo(silo, siloDaoFeeReceiver);
        _assertDaoFeeReceiver(silo, siloDaoFeeReceiver, "silo setup has higher priority");

        siloFactory.setDaoFeeReceiverForAsset(asset, address(0));
        _assertDaoFeeReceiver(silo, siloDaoFeeReceiver, "silo setup is active");

        siloFactory.setDaoFeeReceiverForSilo(silo, address(0));
        _assertDaoFeeReceiver(silo, daoFeeReceiver, "silo setup reset, back to default receiver");
    }

    /*
    forge test -vv --mt test_setBaseURI
    */
    function test_setBaseURI(string calldata _newBaseURI) public {
        vm.assume(keccak256(bytes(_newBaseURI)) != keccak256(bytes(siloFactory.baseURI())));

        vm.prank(hacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, hacker));
        siloFactory.setBaseURI(_newBaseURI);

        siloFactory.setBaseURI(_newBaseURI);
        assertEq(siloFactory.baseURI(), _newBaseURI);
    }

    function _assertDaoFeeReceiver(address _silo, address _expectedAddress, string memory _msg) internal {
        address config = makeAddr("SiloConfig");
        address asset = makeAddr("siloAsset");

        vm.mockCall(_silo, abi.encodeWithSelector(ISilo.config.selector), abi.encode(config));

        vm.mockCall(_silo, abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(asset));

        vm.mockCall(config, abi.encodeWithSelector(ISiloConfig.SILO_ID.selector), abi.encode(1));

        (address dao,) = siloFactory.getFeeReceivers(_silo);

        assertEq(dao, _expectedAddress, string.concat("factory returns correct dao:", _msg));
    }
}
