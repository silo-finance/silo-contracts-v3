// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Math} from "openzeppelin5/utils/math/Math.sol";

import {Actions} from "silo-core/contracts/lib/Actions.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISiloFactory} from "silo-core/contracts/interfaces/ISiloFactory.sol";
import {SiloStorageLib} from "silo-core/contracts/lib/SiloStorageLib.sol";
import {ShareTokenLib} from "silo-core/contracts/lib/ShareTokenLib.sol";

import {SiloConfigMock} from "../../_mocks/SiloConfigMock.sol";
import {SiloFactoryMock} from "../../_mocks/SiloFactoryMock.sol";
import {TokenMock} from "../../_mocks/TokenMock.sol";
import {SafeCast} from "openzeppelin5/utils/math/SafeCast.sol";

/*
FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc WithdrawFeesTest
*/
contract WithdrawFeesTest is Test {
    using SafeCast for uint256;

    uint256 public constant NO_PROTECTED_ASSETS = 0;

    ISiloConfig public config;
    ISiloFactory public factory;

    SiloConfigMock siloConfig;
    SiloFactoryMock siloFactory;
    TokenMock token;

    function _$() internal pure returns (ISilo.SiloStorage storage) {
        return SiloStorageLib.getSiloStorage();
    }

    function setUp() public {
        siloConfig = new SiloConfigMock(makeAddr("siloConfig"));

        ShareTokenLib.getShareTokenStorage().siloConfig = ISiloConfig(siloConfig.ADDRESS());
        config = ISiloConfig(siloConfig.ADDRESS());

        siloFactory = new SiloFactoryMock(address(0));
        factory = ISiloFactory(siloFactory.ADDRESS());

        token = new TokenMock(makeAddr("Asset"));

        ISiloConfig cfg = ShareTokenLib.siloConfig();
        emit log_address(address(cfg));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_withdrawFees_revert_WhenNoData
    */
    function test_withdrawFees_revert_WhenNoData() external {
        _reset();

        siloConfig.turnOnReentrancyProtectionMock();

        vm.expectRevert();
        _withdrawFees(ISilo(address(this)));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_withdrawFees_revert_NoLiquidity
    */
    function test_withdrawFees_revert_NoLiquidity() external {
        _$().daoAndDeployerRevenue = 1;

        uint256 daoFee;
        uint256 deployerFee;
        uint256 flashloanFeeInBp;
        address asset = token.ADDRESS();

        address dao;
        address deployer;

        siloConfig.turnOnReentrancyProtectionMock();
        siloConfig.getFeesWithAssetMock(address(this), daoFee, deployerFee, flashloanFeeInBp, asset);
        siloFactory.getFeeReceiversMock(address(this), dao, deployer);

        token.balanceOfMock(address(this), 0);
        _setProtectedAssets(NO_PROTECTED_ASSETS);

        vm.expectRevert(ISilo.NoLiquidity.selector);
        _withdrawFees(ISilo(address(this)));
    }

    /*
    forge test -vv --mt test_withdrawFees_EarnedZero
    */
    function test_withdrawFees_EarnedZero() external {
        _setProtectedAssets(NO_PROTECTED_ASSETS);

        siloConfig.turnOnReentrancyProtectionMock();

        vm.expectRevert(ISilo.EarnedZero.selector);
        _withdrawFees(ISilo(address(this)));
    }

    /*
    forge test -vv --mt test_withdrawFees_when_deployerFeeReceiver_isZero
    */
    function test_withdrawFees_when_deployerFeeReceiver_isZero() external {
        uint256 daoFee;
        uint256 deployerFee;
        uint256 flashloanFeeInBp;
        address asset = token.ADDRESS();

        address dao = makeAddr("DAO");
        address deployer;

        siloConfig.turnOnReentrancyProtectionMock();
        siloConfig.getFeesWithAssetMock(address(this), daoFee, deployerFee, flashloanFeeInBp, asset);
        siloFactory.getFeeReceiversMock(address(this), dao, deployer);
        siloConfig.turnOffReentrancyProtectionMock();

        token.balanceOfMock(address(this), 1e18);

        _$().daoAndDeployerRevenue = 9;

        _setProtectedAssets(NO_PROTECTED_ASSETS);

        (uint256 daoRevenue, uint256 deployerRevenue,) = _withdrawFees(ISilo(address(this)));

        assertEq(daoRevenue, 9, "daoRevenue");
        assertEq(deployerRevenue, 0, "no deployerRevenue, because deployer is empty");

        assertEq(_$().daoAndDeployerRevenue, 0, "_$().daoAndDeployerRevenue updated");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_withdrawFees_pass
    */
    function test_withdrawFees_pass() external {
        uint256 daoFee = 0.2e18;
        uint256 deployerFee = 0.2e18;
        uint256 daoAndDeployerRevenue = 1e18;
        uint256 daoFees = daoAndDeployerRevenue / 2;

        _withdrawFees_pass(daoFee, deployerFee, daoFees, daoAndDeployerRevenue - daoFees);

        daoFee = 0.2e18;
        deployerFee = 0.1e18;
        daoFees = Math.mulDiv(daoAndDeployerRevenue, 2, 3, Math.Rounding.Ceil);
        _withdrawFees_pass(daoFee, deployerFee, daoFees, daoAndDeployerRevenue - daoFees);

        daoFee = 0.2e18;
        deployerFee = 0.01e18;
        daoFees = Math.mulDiv(daoAndDeployerRevenue, 20, 21, Math.Rounding.Ceil);

        _withdrawFees_pass(daoFee, deployerFee, daoFees, daoAndDeployerRevenue - daoFees);
    }

    /*
    forge test -vv --mt test_cant_withdraw_more_than_available
    */
    function test_cant_withdraw_more_than_available() external {
        uint256 daoFee;
        uint256 deployerFee;
        uint256 flashloanFeeInBp;
        address asset = token.ADDRESS();
        uint256 siloBalance = 1e18;

        address dao = makeAddr("DAO");
        address deployer;

        siloConfig.turnOnReentrancyProtectionMock();
        siloConfig.getFeesWithAssetMock(address(this), daoFee, deployerFee, flashloanFeeInBp, asset);
        siloFactory.getFeeReceiversMock(address(this), dao, deployer);
        siloConfig.turnOffReentrancyProtectionMock();

        token.balanceOfMock(address(this), siloBalance);

        _$().daoAndDeployerRevenue = siloBalance.toUint192(); // fees are the same as balance

        uint256 protectedAssets = siloBalance / 3; // the third part of the balance is protected

        token.transferMock(dao, siloBalance - protectedAssets); // dao gets all the liquidity except protected assets
        _setProtectedAssets(protectedAssets);

        _withdrawFees(ISilo(address(this)));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_withdraw_to_deployer_fails
    */
    function test_withdraw_to_deployer_fails() external {
        uint256 daoFee = 0.1e18;
        uint256 deployerFee = 0.1e18;
        uint256 flashloanFeeInBp;
        address asset = token.ADDRESS();
        uint256 siloBalance = 1e18;

        address dao = makeAddr("DAO");
        address deployer = makeAddr("Deployer");

        siloConfig.turnOnReentrancyProtectionMock();
        siloConfig.getFeesWithAssetMock(address(this), daoFee, deployerFee, flashloanFeeInBp, asset);
        siloFactory.getFeeReceiversMock(address(this), dao, deployer);
        siloConfig.turnOffReentrancyProtectionMock();

        token.balanceOfMock(address(this), siloBalance);

        _$().daoAndDeployerRevenue = siloBalance.toUint192(); // fees are the same as balance

        token.transferResultFalseMock(deployer, siloBalance / 2); // transfer to deployer fails
        token.transferMock(dao, siloBalance); // dao gets all fees as transfer to deployer fails

        (,, bool redirectedDeployerFees) = Actions.withdrawFees(ISilo(address(this)));
        assertTrue(redirectedDeployerFees, "redirected fees");
    }

    function _withdrawFees_pass(
        uint256 _daoFee,
        uint256 _deployerFee,
        uint256 _transferDao,
        uint256 _transferDeployer
    ) internal {
        uint256 flashloanFeeInBp;
        address asset = token.ADDRESS();

        address dao = makeAddr("DAO");
        address deployer = makeAddr("Deployer");

        siloConfig.turnOnReentrancyProtectionMock();
        siloConfig.getFeesWithAssetMock(address(this), _daoFee, _deployerFee, flashloanFeeInBp, asset);
        siloFactory.getFeeReceiversMock(address(this), dao, deployer);
        siloConfig.turnOffReentrancyProtectionMock();

        token.balanceOfMock(address(this), 999e18);

        _$().daoAndDeployerRevenue = 1e18;

        if (_transferDao != 0) token.transferMock(dao, _transferDao);
        if (_transferDeployer != 0) token.transferMock(deployer, _transferDeployer);

        _setProtectedAssets(NO_PROTECTED_ASSETS);

        _withdrawFees(ISilo(address(this)));
        assertEq(_$().daoAndDeployerRevenue, 0, "fees cleared");
    }

    function _withdrawFees(ISilo _silo)
        internal
        returns (uint256 daoRevenue, uint256 deployerRevenue, bool redirectedDeployerFees)
    {
        return Actions.withdrawFees(_silo);
    }

    function _setProtectedAssets(uint256 _assets) internal {
        _$().totalAssets[ISilo.AssetType.Protected] = _assets;
    }

    function _reset() internal {
        _setProtectedAssets(NO_PROTECTED_ASSETS);

        config = ISiloConfig(address(0));
        factory = ISiloFactory(address(0));
        _$().daoAndDeployerRevenue = 0;
        _$().interestRateTimestamp = 0;
    }
}
