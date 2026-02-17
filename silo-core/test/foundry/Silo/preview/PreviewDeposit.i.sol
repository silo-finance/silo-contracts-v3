// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {SiloConfigsNames} from "silo-core/deploy/silo/SiloDeployments.sol";
import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";

import {SiloLittleHelper} from "../../_common/SiloLittleHelper.sol";

/*
    forge test -vv --ffi --mc PreviewDepositTest
*/
contract PreviewDepositTest is SiloLittleHelper, Test {
    address immutable depositor;
    address immutable borrower;

    constructor() {
        depositor = makeAddr("Depositor");
        borrower = makeAddr("Borrower");
    }

    function setUp() public {
        _setUpLocalFixture(SiloConfigsNames.SILO_LOCAL_NO_ORACLE_NO_LTV_SILO);
    }

    /*
    forge test -vv --ffi --mt test_previewDeposit_beforeInterest_fuzz
    */
    /// forge-config: core_test.fuzz.runs = 10000
    function test_previewDeposit_beforeInterest_fuzz(uint128 _assets, bool _defaultType, uint8 _type) public {
        vm.assume(_assets > 0);
        vm.assume(_type == uint8(ISilo.AssetType.Collateral) || _type == uint8(ISilo.AssetType.Protected));

        (ISilo.CollateralType cType, ISilo.AssetType aType) = _castToTypes(_defaultType, _type);

        uint256 previewShares = _defaultType ? silo0.previewDeposit(_assets) : silo0.previewDeposit(_assets, cType);
        uint256 shares = _defaultType ? _deposit(_assets, depositor) : _deposit(_assets, depositor, cType);

        assertEq(previewShares, shares, "previewDeposit must return as close but NOT more");
        assertEq(previewShares, silo0.convertToShares(_assets, aType), "previewDeposit == convertToShares");
    }

    /*
    forge test -vv --ffi --mt test_previewDeposit_afterNoInterest
    */
    /// forge-config: core_test.fuzz.runs = 10000
    function test_previewDeposit_afterNoInterest_fuzz(uint128 _assets, bool _defaultType, uint8 _type) public {
        vm.assume(_assets > 0);
        vm.assume(_type == uint8(ISilo.AssetType.Collateral) || _type == uint8(ISilo.AssetType.Protected));

        (ISilo.CollateralType cType, ISilo.AssetType aType) = _castToTypes(_defaultType, _type);

        uint256 sharesBefore = _defaultType ? _deposit(_assets, depositor) : _deposit(_assets, depositor, cType);

        vm.warp(block.timestamp + 365 days);
        silo0.accrueInterest();

        uint256 previewShares = _defaultType ? silo0.previewDeposit(_assets) : silo0.previewDeposit(_assets, cType);
        uint256 gotShares = _defaultType ? _deposit(_assets, depositor) : _deposit(_assets, depositor, cType);

        assertEq(previewShares, gotShares, "previewDeposit must return as close but NOT more");
        assertEq(previewShares, sharesBefore, "without interest shares must be the same");
        assertEq(previewShares, silo0.convertToShares(_assets, aType), "previewDeposit == convertToShares");
    }

    /*
    forge test -vv --ffi --mt test_previewDeposit_withInterest
    */
    /// forge-config: core_test.fuzz.runs = 10000
    function test_previewDeposit_withInterest_fuzz(uint256 _assets, bool _protected) public {
        vm.assume(_assets < type(uint128).max);
        vm.assume(_assets > 0);

        ISilo.CollateralType cType = _protected ? ISilo.CollateralType.Protected : ISilo.CollateralType.Collateral;
        ISilo.AssetType aType = _protected ? ISilo.AssetType.Protected : ISilo.AssetType.Collateral;

        uint256 sharesBefore = _deposit(_assets, depositor, cType);
        _depositForBorrow(_assets, depositor);

        if (_protected) {
            _makeDeposit(silo1, token1, _assets, depositor, ISilo.CollateralType.Protected);
        }

        _deposit(_assets / 10 == 0 ? 2 : _assets, borrower);
        _borrow(_assets / 10 + 1, borrower); // +1 ensure we not borrowing 0

        vm.warp(block.timestamp + 365 days);

        uint256 previewShares0 = silo0.previewDeposit(_assets, cType);
        uint256 previewShares1 = silo1.previewDeposit(_assets, cType);

        assertLe(
            previewShares1,
            previewShares0,
            "you can get less shares on silo1 than on silo0, because we have interests here"
        );

        if (previewShares1 == 0) {
            // if preview is zero for `_assets`, then deposit should also reverts
            _depositForBorrowRevert(_assets, depositor, cType, ISilo.InputZeroShares.selector);
        } else {
            assertEq(
                previewShares1,
                _makeDeposit(silo1, token1, _assets, depositor, cType),
                "previewDeposit with interest on the fly - must be as close but NOT more"
            );
        }

        silo0.accrueInterest();
        silo1.accrueInterest();

        assertEq(
            silo0.previewDeposit(_assets, cType),
            sharesBefore,
            "no interest in silo0, so preview should be the same"
        );
        assertEq(
            silo0.previewDeposit(_assets, cType),
            silo0.convertToShares(_assets, aType),
            "previewDeposit0 == convertToShares"
        );

        previewShares1 = silo1.previewDeposit(_assets, cType);
        assertEq(previewShares1, silo1.convertToShares(_assets, aType), "previewDeposit1 == convertToShares");

        // we have different rounding direction for general conversion method nad preview deposit
        // so it can produce slight different result on precision level, that's why we divide by precision
        assertLe(
            previewShares1 / SiloMathLib._DECIMALS_OFFSET_POW,
            _assets,
            "with interests, we can receive less shares than assets amount"
        );

        emit log_named_uint("previewShares1", previewShares1);

        if (previewShares1 == 0) {
            _depositForBorrowRevert(_assets, depositor, cType, ISilo.InputZeroShares.selector);
        } else {
            assertEq(
                previewShares1,
                _makeDeposit(silo1, token1, _assets, depositor, cType),
                "previewDeposit after accrueInterest() - as close, but NOT more"
            );
        }
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
