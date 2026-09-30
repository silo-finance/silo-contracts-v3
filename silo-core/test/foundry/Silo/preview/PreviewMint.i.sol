// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
    forge test -vv --ffi --mc PreviewMintTest
*/
contract PreviewMintTest is SiloLittleHelper, Test {
    uint256 constant DEPOSIT_BEFORE = 1e18 + 9876543211;

    ISiloConfig siloConfig;
    address immutable DEPOSITOR;
    address immutable BORROWER;

    constructor() {
        DEPOSITOR = makeAddr("Depositor");
        BORROWER = makeAddr("Borrower");
    }

    function setUp() public {
        siloConfig = _setUpLocalFixture(SiloConfigsNames.SILO_LOCAL_NO_ORACLE_NO_LTV_SILO);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vv --ffi --mt test_previewMint_beforeInterest
    */
    /// forge-config: core_test.fuzz.runs = 10000
    function test_previewMint_beforeInterest_fuzz(uint256 _shares, bool _defaultType, uint8 _type) public {
        vm.assume(_shares > 0);

        _assertPreviewMint(_shares, _defaultType, _type);
    }

    /*
    forge test -vv --ffi --mt test_previewMint_afterNoInterest_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 10000
    function test_previewMint_afterNoInterest_fuzz(
        uint128 _depositAmount,
        uint128 _shares,
        bool _defaultType,
        uint8 _type
    ) public {
        _previewMint_afterNoInterest(_depositAmount, _shares, _defaultType, _type);
        _assertPreviewMint(_shares, _defaultType, _type);
    }

    /// forge-config: core_test.fuzz.runs = 10000
    function test_previewMint_withInterest_fuzz(uint128 _shares, bool _defaultType, uint8 _type) public {
        vm.assume(_shares > 0);

        _createInterest();

        _assertPreviewMint(_shares, _defaultType, _type);
    }

    function _createInterest() internal {
        uint256 assets = 1e18 + 123456789; // some not even number

        _deposit(assets, DEPOSITOR);
        _depositForBorrow(assets, DEPOSITOR);

        _deposit(assets, BORROWER);
        _borrow(assets / 10, BORROWER);

        vm.warp(block.timestamp + 365 days);

        silo0.accrueInterest();
        silo1.accrueInterest();
    }

    function _previewMint_afterNoInterest(uint128 _depositAmount, uint128 _shares, bool _defaultType, uint8 _type)
        internal
    {
        vm.assume(_depositAmount > 0);
        vm.assume(_shares > 0);
        vm.assume(_type == 0 || _type == 1);

        // deposit something
        _deposit(_depositAmount, makeAddr("any"));

        vm.warp(block.timestamp + 365 days);
        silo0.accrueInterest();

        _assertPreviewMint(_shares, _defaultType, _type);
    }

    function _assertPreviewMint(uint256 _shares, bool _defaultType, uint8 _type) internal {
        // we can get overflow on numbers closed to max
        vm.assume(_shares < type(uint256).max / 1e3);
        vm.assume(_type == uint8(ISilo.AssetType.Collateral) || _type == uint8(ISilo.AssetType.Protected));

        (ISilo.CollateralType cType, ISilo.AssetType aType) = _castToTypes(_defaultType, _type);

        uint256 previewMint = _defaultType ? silo0.previewMint(_shares) : silo0.previewMint(_shares, cType);

        token0.mint(DEPOSITOR, previewMint);

        vm.startPrank(DEPOSITOR);
        token0.approve(address(silo0), previewMint);

        uint256 depositedAssets =
            _defaultType ? silo0.mint(_shares, DEPOSITOR) : silo0.mint(_shares, DEPOSITOR, cType);

        assertEq(previewMint, depositedAssets, "previewMint == depositedAssets, NOT fewer");
        assertEq(previewMint, silo0.convertToAssets(_shares, aType), "previewMint == convertToAssets");
    }

    function _castToTypes(bool _defaultType, uint8 _type)
        private
        pure
        returns (ISilo.CollateralType collateralType, ISilo.AssetType assetType)
    {
        collateralType = _defaultType ? ISilo.CollateralType.Collateral : ISilo.CollateralType(_type);
        assetType = _defaultType ? ISilo.AssetType.Collateral : ISilo.AssetType(_type);
    }
}
