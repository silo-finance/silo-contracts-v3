// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {DefaultingRepayLib} from "silo-core/contracts/hooks/defaulting/DefaultingRepayLib.sol";
import {Actions} from "silo-core/contracts/lib/Actions.sol";
import {Hook} from "silo-core/contracts/lib/Hook.sol";
import {SiloStorageLib} from "silo-core/contracts/lib/SiloStorageLib.sol";
import {ShareTokenLib} from "silo-core/contracts/lib/ShareTokenLib.sol";

import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ShareDebtToken} from "silo-core/contracts/utils/ShareDebtToken.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {MintableToken} from "silo-core/test/foundry/_common/MintableToken.sol";

uint256 constant OFFSET = 1e3;

contract ShareDebtTokenMock is ShareDebtToken {
    function mockIt(ISilo _silo) external {
        ShareTokenLib.__ShareToken_init({_silo: _silo, _hookReceiver: address(0), _tokenType: uint24(Hook.DEBT_TOKEN)});
    }

    function overrideSilo(ISilo _silo) external {
        ShareTokenLib.getShareTokenStorage().silo = _silo;
    }
}

contract SiloAndConfigMock {
    ShareDebtTokenMock public immutable DEBT_SHARE_TOKEN;
    MintableToken public immutable DEBT_ASSET;

    constructor() {
        DEBT_SHARE_TOKEN = new ShareDebtTokenMock();
        DEBT_ASSET = new MintableToken(18);
        DEBT_ASSET.setOnDemand(true);
    }

    function config() external view returns (ISiloConfig) {
        return ISiloConfig(address(this));
    }

    function turnOnReentrancyProtection() external pure {}

    function turnOffReentrancyProtection() external pure {}

    function accrueInterestForSilo(address /* _silo */ ) external pure {}

    function getDebtShareTokenAndAsset(address /* _silo */ ) external view returns (address, address) {
        return (address(DEBT_SHARE_TOKEN), address(DEBT_ASSET));
    }
}

contract LibImpl {
    function init(address _silo) external {
        IShareToken.ShareTokenStorage storage $ = ShareTokenLib.getShareTokenStorage();
        $.siloConfig = ISiloConfig(_silo);
    }

    function createDebtForBorrower(address _borrower, uint256 _assets) external {
        ShareDebtTokenMock(address(getDebtShareToken())).overrideSilo(ISilo(address(this)));
        IShareToken(getDebtShareToken()).mint(_borrower, _borrower, _assets * OFFSET);

        SiloStorageLib.getSiloStorage().totalAssets[ISilo.AssetType.Debt] = _assets;
    }

    function debtShareTokenSilo() public view returns (ISilo) {
        return IShareToken(getDebtShareToken()).silo();
    }

    function getDebtShareToken() public view returns (address debtShareToken) {
        IShareToken.ShareTokenStorage storage $ = ShareTokenLib.getShareTokenStorage();
        (debtShareToken,) = $.siloConfig.getDebtShareTokenAndAsset(address(this));
    }
}

contract DefaultingRepayLibImpl is LibImpl {
    function actionsRepay(uint256 _assets, uint256 _shares, address _borrower, address _repayer)
        external
        returns (uint256 assets, uint256 shares)
    {
        ShareDebtTokenMock(address(getDebtShareToken())).overrideSilo(ISilo(address(this)));
        return DefaultingRepayLib.actionsRepay(_assets, _shares, _borrower, _repayer);
    }
}

contract ActionsLibImpl is LibImpl {
    function repay(uint256 _assets, uint256 _shares, address _borrower, address _repayer)
        external
        returns (uint256 assets, uint256 shares)
    {
        ShareDebtTokenMock(address(getDebtShareToken())).overrideSilo(ISilo(address(this)));
        return Actions.repay(_assets, _shares, _borrower, _repayer);
    }
}

/*
FOUNDRY_PROFILE=core_test forge test --ffi --mc DefaultingRepayLibTest -vvv

tests to ensure copied code behave in exacly same way as original one
*/
contract DefaultingRepayLibTest is Test {
    address borrower = makeAddr("borrower");

    DefaultingRepayLibImpl defaultingRepayLibImpl = new DefaultingRepayLibImpl();
    ActionsLibImpl actionsLibImpl = new ActionsLibImpl();

    SiloAndConfigMock siloAndConfigMockActions = new SiloAndConfigMock();
    SiloAndConfigMock siloAndConfigMockDefaulting = new SiloAndConfigMock();

    function setUp() public {
        siloAndConfigMockActions.DEBT_SHARE_TOKEN().mockIt(ISilo(address(siloAndConfigMockActions)));
        siloAndConfigMockDefaulting.DEBT_SHARE_TOKEN().mockIt(ISilo(address(siloAndConfigMockDefaulting)));

        defaultingRepayLibImpl.init(address(siloAndConfigMockActions));
        actionsLibImpl.init(address(siloAndConfigMockDefaulting));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_dafaulting_actionsRepay_assets -vvv
    */
    function test_dafaulting_actionsRepay_assets(uint128 _debtAmount, uint128 _repayAmount) public {
        vm.assume(_debtAmount >= _repayAmount);
        _checkIfLibsMathMatch(_debtAmount, _repayAmount, 0);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_dafaulting_actionsRepay_shares -vvv
    */
    function test_dafaulting_actionsRepay_shares(uint128 _repayShares) public {
        _checkIfLibsMathMatch(uint256(_repayShares) * OFFSET, 0, _repayShares);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_dafaulting_actionsRepay_additionalBorrower -vvv
    */
    function test_dafaulting_actionsRepay_additionalBorrower(uint128 _debtAmount, uint128 _repayAmount) public {
        vm.assume(_debtAmount >= _repayAmount);
        vm.assume(_repayAmount > 0);

        address borrower2 = makeAddr("borrower2");
        require(borrower2 != borrower, "borrower2 cannot be the same as borrower");

        defaultingRepayLibImpl.createDebtForBorrower(borrower2, _debtAmount);
        actionsLibImpl.createDebtForBorrower(borrower2, _debtAmount);

        _checkIfLibsMathMatch(_debtAmount, _repayAmount, 0);
    }

    function _checkIfLibsMathMatch(uint256 _debtAmount, uint256 _repayAmount, uint256 _repayShares) private {
        vm.assume(_repayAmount > 0 || _repayShares > 0);

        _createDebtForBorrower(_debtAmount);

        (uint256 assetsRepaid1, uint256 sharesRepaid1) =
            defaultingRepayLibImpl.actionsRepay(_repayAmount, _repayShares, borrower, borrower);
        (uint256 assetsRepaid2, uint256 sharesRepaid2) =
            actionsLibImpl.repay(_repayAmount, _repayShares, borrower, borrower);

        assertEq(assetsRepaid1, assetsRepaid2, "[assets] expect same result because repay is a copy");
        assertEq(sharesRepaid1, sharesRepaid2, "[shares] expect same result because repay is a copy");
    }

    function _createDebtForBorrower(uint256 _assets) internal {
        defaultingRepayLibImpl.createDebtForBorrower(borrower, _assets);
        actionsLibImpl.createDebtForBorrower(borrower, _assets);
    }
}
