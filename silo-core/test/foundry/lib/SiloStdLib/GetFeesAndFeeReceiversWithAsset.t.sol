// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IntegrationTest} from "silo-foundry-utils/networks/IntegrationTest.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISiloFactory} from "silo-core/contracts/SiloFactory.sol";
import {SiloStdLib} from "silo-core/contracts/lib/SiloStdLib.sol";
import {SiloCoreContracts} from "silo-core/common/SiloCoreContracts.sol";
import {SiloConfigData} from "silo-core/deploy/input-readers/SiloConfigData.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";

import {SiloLittleHelper} from "silo-core/test/foundry/_common/SiloLittleHelper.sol";

/*
forge test -vv --ffi --mc GetFeesAndFeeReceiversWithAssetTest
*/
contract GetFeesAndFeeReceiversWithAssetTest is SiloLittleHelper, IntegrationTest {
    string public constant SILO_TO_DEPLOY = SiloConfigsNames.SILO_LOCAL_DEPLOYER;

    ISiloConfig siloConfig;
    SiloConfigData siloData;

    function setUp() public {
        siloData = new SiloConfigData();

        siloConfig = _setUpLocalFixture(SILO_TO_DEPLOY);

        siloFactory = ISiloFactory(getAddress(SiloCoreContracts.SILO_FACTORY));
    }

    function config() external view returns (ISiloConfig) {
        return siloConfig;
    }

    function factory() external view returns (ISiloFactory) {
        return siloFactory;
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_getFeesAndFeeReceiversWithAsset
    */
    function test_getFeesAndFeeReceiversWithAsset(address _newDeployer) public {
        vm.assume(_newDeployer != address(0));

        (, ISiloConfig.InitData memory initData,) = siloData.getConfigData(SILO_TO_DEPLOY);
        (address silo0, address silo1) = siloConfig.getSilos();

        (uint256 daoFee, uint256 deployerFee,, address asset) = siloConfig.getFeesWithAsset(silo0);

        assertGe(daoFee, siloFactory.daoFeeRange().min, "min.daoFee");
        assertLe(daoFee, siloFactory.daoFeeRange().max, "max.daoFee");
        assertEq(deployerFee, initData.deployerFee, "deployerFee");
        assertEq(asset, address(token0), "asset");

        (address daoFeeReceiver, address deployerFeeReceiver) = siloFactory.getFeeReceivers(silo0);

        uint256 siloId = siloFactory.getNextSiloId() - 1;
        assertEq(daoFeeReceiver, siloFactory.daoFeeReceiver(), "daoFeeReceiver silo0");
        assertEq(deployerFeeReceiver, initData.deployer, "deployerFeeReceiver silo0");
        assertEq(deployerFeeReceiver, siloFactory.ownerOf(siloId), "ownerOf(siloId) silo0");

        (daoFeeReceiver, deployerFeeReceiver) = siloFactory.getFeeReceivers(silo1);

        assertEq(daoFeeReceiver, siloFactory.daoFeeReceiver(), "daoFeeReceiver silo1");
        assertEq(deployerFeeReceiver, initData.deployer, "deployerFeeReceiver silo1");
        assertEq(deployerFeeReceiver, siloFactory.ownerOf(siloId), "ownerOf(siloId) silo1");

        assertEq(siloFactory.getNextSiloId(), siloId + 1, "getNextSiloId");

        vm.prank(initData.deployer);
        siloFactory.transferFrom(initData.deployer, _newDeployer, siloId);

        (, deployerFeeReceiver) = siloFactory.getFeeReceivers(silo0);

        assertEq(deployerFeeReceiver, _newDeployer, "deployerFeeReceiver silo0");
        assertEq(siloFactory.ownerOf(siloId), _newDeployer, "ownerOf(siloId) silo0");

        (, deployerFeeReceiver) = siloFactory.getFeeReceivers(silo1);

        assertEq(deployerFeeReceiver, _newDeployer, "deployerFeeReceiver silo1");
        assertEq(siloFactory.ownerOf(siloId), _newDeployer, "ownerOf(siloId) silo1");

        bytes memory data = abi.encodeWithSelector(ISiloConfig.getFeesWithAsset.selector, address(this));
        vm.mockCall(address(siloConfig), data, abi.encode(daoFee, deployerFee, 0, asset));
        vm.expectCall(address(siloConfig), data);

        bytes memory data2 = abi.encodeWithSelector(ISiloFactory.getFeeReceivers.selector, address(this));
        vm.mockCall(address(siloFactory), data2, abi.encode(daoFeeReceiver, deployerFeeReceiver));
        vm.expectCall(address(siloFactory), data2);

        (
            address mockedDaoFeeReceiver,
            address mockedDeployerFeeReceiver,
            uint256 mockedDaoFee,
            uint256 mockedDeployerFee,
            address mockedAsset
        ) = SiloStdLib.getFeesAndFeeReceiversWithAsset(ISilo(address(this)));

        assertEq(mockedDaoFeeReceiver, daoFeeReceiver, "mockedDaoFeeReceiver");
        assertEq(mockedDeployerFeeReceiver, deployerFeeReceiver, "mockedDeployerFeeReceiver");
        assertEq(mockedDaoFee, daoFee, "mockedDaoFee");
        assertEq(mockedDeployerFee, deployerFee, "mockedDeployerFee");
        assertEq(mockedAsset, asset, "mockedAsset");
    }
}
