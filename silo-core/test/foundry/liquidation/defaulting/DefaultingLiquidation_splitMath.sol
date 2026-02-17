// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {Math} from "openzeppelin5/utils/math/Math.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {IPartialLiquidationByDefaulting} from "silo-core/contracts/interfaces/IPartialLiquidationByDefaulting.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";

import {SiloHookV2} from "silo-core/contracts/hooks/SiloHookV2.sol";
import {SiloMathLib} from "silo-core/contracts/lib/SiloMathLib.sol";
import {Rounding} from "silo-core/contracts/lib/Rounding.sol";

import {CloneHookV2} from "./common/CloneHookV2.sol";
import {OneWeiTotalAssetsNegativeRatioData, SplitInputData} from "./common/OneWeiTotalAssetsNegativeRatioData.sol";
import {OneWeiTotalAssetsPositiveRatioData} from "./common/OneWeiTotalAssetsPositiveRatioData.sol";
import {PositiveRatioData} from "./common/PositiveRatioData.sol";

/*
FOUNDRY_PROFILE=core_test forge test --ffi --mc DefaultingLiquidationSplitMathTest -vv
*/
contract DefaultingLiquidationSplitMathTest is CloneHookV2 {
    ISiloConfig.ConfigData collateralConfig;

    function setUp() public {
        ISiloConfig.ConfigData memory config1;

        collateralConfig.lt = 1;
        collateralConfig.liquidationFee = 0.1e18;
        collateralConfig.silo = silo0;
        collateralConfig.collateralShareToken = collateralShareToken;
        collateralConfig.protectedShareToken = protectedShareToken;
        collateralConfig.debtShareToken = debtShareToken;

        defaulting = _cloneHook(collateralConfig, config1);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_getKeeperAndLenderSharesSplit_zeros -vv
    */
    function test_getKeeperAndLenderSharesSplit_zeros() public view {
        _singleCheck({
            _id: 0,
            _assetsToLiquidate: 0,
            _collateralType: ISilo.CollateralType.Collateral,
            _expectedKeeperShares: 0,
            _expectedLendersShares: 0
        });

        _singleCheck({
            _id: 1,
            _assetsToLiquidate: 0,
            _collateralType: ISilo.CollateralType.Protected,
            _expectedKeeperShares: 0,
            _expectedLendersShares: 0
        });
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_getKeeperAndLenderSharesSplit_positive_protected_pass -vv
    */
    function test_getKeeperAndLenderSharesSplit_positive_protected_pass() public {
        assertEq(defaulting.KEEPER_FEE(), 0.2e18, "this math expect 20% keeper fee, so 1/5 of liquidation fee");

        SplitInputData[] memory data = new OneWeiTotalAssetsPositiveRatioData().getData();

        for (uint256 i = 0; i < data.length; i++) {
            _singleCheckWithMock({
                _id: data[i].id,
                _assetsToLiquidate: data[i].assetsToLiquidate,
                _collateralType: ISilo.CollateralType.Protected,
                _expectedKeeperShares: data[i].expectedKeeperShares,
                _expectedLendersShares: data[i].expectedLendersShares,
                _totalAssets: data[i].totalAssets,
                _totalShares: data[i].totalShares
            });
        }
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_getKeeperAndLenderSharesSplit_collateral_pass -vv
    */
    function test_getKeeperAndLenderSharesSplit_collateral_pass() public {
        assertEq(defaulting.KEEPER_FEE(), 0.2e18, "this math expect 20% keeper fee, so 1/5 of liquidation fee");

        SplitInputData[] memory data = new OneWeiTotalAssetsPositiveRatioData().getData();

        for (uint256 i = 0; i < data.length; i++) {
            _singleCheckWithMock({
                _id: data[i].id,
                _assetsToLiquidate: data[i].assetsToLiquidate,
                _collateralType: ISilo.CollateralType.Collateral,
                _expectedKeeperShares: data[i].expectedKeeperShares,
                _expectedLendersShares: data[i].expectedLendersShares,
                _totalAssets: data[i].totalAssets,
                _totalShares: data[i].totalShares
            });
        }
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_getKeeperAndLenderSharesSplit_negative_pass -vv
    */
    function test_getKeeperAndLenderSharesSplit_negative_pass() public {
        assertEq(defaulting.KEEPER_FEE(), 0.2e18, "this math expect 20% keeper fee, so 1/5 of liquidation fee");

        SplitInputData[] memory data = new OneWeiTotalAssetsNegativeRatioData().getData();

        for (uint256 i = 0; i < data.length; i++) {
            _singleCheckWithMock({
                _id: data[i].id,
                _assetsToLiquidate: data[i].assetsToLiquidate,
                _collateralType: ISilo.CollateralType.Protected,
                _expectedKeeperShares: data[i].expectedKeeperShares,
                _expectedLendersShares: data[i].expectedLendersShares,
                _totalAssets: data[i].totalAssets,
                _totalShares: data[i].totalShares
            });
        }
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_getKeeperAndLenderSharesSplit_collateralEqProtected_fuzz -vv
    */
    function test_getKeeperAndLenderSharesSplit_collateralEqProtected_fuzz(uint128 _assets, uint128 _shares) public {
        _ensureNoOverflowsAndMockCall({
            _assetsToLiquidate: _assets,
            _useProtected: true,
            _totalAssets: _assets,
            _totalShares: _shares
        });

        _ensureNoOverflowsAndMockCall({
            _assetsToLiquidate: _assets,
            _useProtected: false,
            _totalAssets: _assets,
            _totalShares: _shares
        });

        (uint256 totalSharesToLiquidate1, uint256 keeperShares1, uint256 lendersShares1) = defaulting
            .getKeeperAndLenderSharesSplit({_assetsToLiquidate: _assets, _collateralType: ISilo.CollateralType.Protected});

        (uint256 totalSharesToLiquidate2, uint256 keeperShares2, uint256 lendersShares2) = defaulting
            .getKeeperAndLenderSharesSplit({_assetsToLiquidate: _assets, _collateralType: ISilo.CollateralType.Collateral});

        assertEq(totalSharesToLiquidate1, totalSharesToLiquidate2, "total shares to liquidate should be the same");
        assertEq(keeperShares1, keeperShares2, "keeper shares should be the same");
        assertEq(lendersShares1, lendersShares2, "lenders shares should be the same");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_getKeeperAndLenderSharesSplit_distributeAllShares_protected_fuzz -vv
    */
    /// forge-config: core_test.fuzz.runs = 10000
    function test_getKeeperAndLenderSharesSplit_distributeAllShares_protected_fuzz(uint128 _assets, uint128 _shares)
        public
    {
        _getKeeperAndLenderSharesSplit_distributeAllShares(_assets, _shares, ISilo.CollateralType.Protected);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_getKeeperAndLenderSharesSplit_distributeAllShares_collateral_fuzz -vv
    */
    /// forge-config: core_test.fuzz.runs = 10000
    function test_getKeeperAndLenderSharesSplit_distributeAllShares_collateral_fuzz(uint128 _assets, uint128 _shares)
        public
    {
        _getKeeperAndLenderSharesSplit_distributeAllShares(_assets, _shares, ISilo.CollateralType.Collateral);
    }

    function _getKeeperAndLenderSharesSplit_distributeAllShares(
        uint128 _assets,
        uint128 _shares,
        ISilo.CollateralType _collateralType
    ) internal {
        vm.assume(_assets > 0);
        vm.assume(_shares > 0);

        _ensureNoOverflowsAndMockCall({
            _assetsToLiquidate: _assets,
            _useProtected: _collateralType == ISilo.CollateralType.Protected,
            _totalAssets: _assets,
            _totalShares: _shares
        });

        (uint256 totalSharesToLiquidate, uint256 keeperShares, uint256 lendersShares) =
            defaulting.getKeeperAndLenderSharesSplit({_assetsToLiquidate: _assets, _collateralType: _collateralType});

        // in extreame cases, when ration is way off, we can expect math to produce higher shares than total shares,
        // this case will revert tx, so we expliding it here
        vm.assume(totalSharesToLiquidate <= _shares);

        uint256 sharesLeft = _shares - totalSharesToLiquidate;
        console2.log("shares diff", sharesLeft);

        // because of offset, this rule can be violated, so instead of expecting all shares to be distributed,
        // we allow for dust that can not ve converted to assets,
        // and distributed shares must be converted to liquidated assets

        if (sharesLeft > 0) {
            uint256 dustAssets = SiloMathLib.convertToAssets({
                _shares: sharesLeft,
                _totalAssets: _assets,
                _totalShares: _shares,
                _rounding: Rounding.WITHDRAW_TO_ASSETS,
                _assetType: ISilo.AssetType(uint8(_collateralType))
            });

            assertEq(dustAssets, 0, "dust can not be converted to assets");
        }

        uint256 backToAssets = SiloMathLib.convertToAssets({
            _shares: totalSharesToLiquidate,
            _totalAssets: _assets,
            _totalShares: _shares,
            _rounding: Rounding.WITHDRAW_TO_ASSETS,
            _assetType: ISilo.AssetType(uint8(_collateralType))
        });

        uint256 diff = _assets - backToAssets;
        assertLe(
            diff,
            1,
            "all assets should be distributed when assets to liquidate == total (we allow for 1 wei less for rounding error on withdraw)"
        );

        assertEq(keeperShares + lendersShares, totalSharesToLiquidate, "we should split 100%");
        assertLt(keeperShares, lendersShares, "keeper shares should be less than lenders shares");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_getKeeperAndLenderSharesSplit_positive_pass -vv
    */
    function test_getKeeperAndLenderSharesSplit_positive_pass() public {
        SplitInputData[] memory data = new PositiveRatioData().getData();

        for (uint256 i = 0; i < data.length; i++) {
            _singleCheckWithMock({
                _id: data[i].id,
                _assetsToLiquidate: data[i].assetsToLiquidate,
                _collateralType: ISilo.CollateralType.Protected,
                _expectedKeeperShares: data[i].expectedKeeperShares,
                _expectedLendersShares: data[i].expectedLendersShares,
                _totalAssets: data[i].totalAssets,
                _totalShares: data[i].totalShares
            });
        }
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_getKeeperAndLenderSharesSplit_sumUp_fuzz -vv
    */
    /// forge-config: core_test.fuzz.runs = 10000
    function test_getKeeperAndLenderSharesSplit_sumUp_fuzz(
        uint256 _assetsToLiquidate,
        bool _useProtected,
        uint256 _totalAssets,
        uint256 _totalShares
    ) public {
        _ensureNoOverflowsAndMockCall(_assetsToLiquidate, _useProtected, _totalAssets, _totalShares);

        ISilo.CollateralType collateralType =
            _useProtected ? ISilo.CollateralType.Protected : ISilo.CollateralType.Collateral;

        (uint256 totalSharesToLiquidate, uint256 keeperShares, uint256 lendersShares) = defaulting
            .getKeeperAndLenderSharesSplit({_assetsToLiquidate: _assetsToLiquidate, _collateralType: collateralType});

        if (lendersShares == 0) assertEq(keeperShares, 0, "if lenders are 0, keeper should be 0");
        else assertLt(keeperShares, lendersShares, "keeper part is always less than lenders part");

        assertEq(keeperShares + lendersShares, totalSharesToLiquidate, "we should split 100%");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_getKeeperAndLenderSharesSplit_neverReverts -vv
    */
    /// forge-config: core_test.fuzz.runs = 10000
    function test_getKeeperAndLenderSharesSplit_neverReverts_fuzz(
        uint256 _assetsToLiquidate,
        bool _useProtected,
        uint256 _totalAssets,
        uint256 _totalShares
    ) public {
        _ensureNoOverflowsAndMockCall(_assetsToLiquidate, _useProtected, _totalAssets, _totalShares);

        ISilo.CollateralType collateralType =
            _useProtected ? ISilo.CollateralType.Protected : ISilo.CollateralType.Collateral;

        defaulting.getKeeperAndLenderSharesSplit({
            _assetsToLiquidate: _assetsToLiquidate,
            _collateralType: collateralType
        });
    }

    /*
    FOUNDRY_PROFILE=core_test forge test --ffi --mt test_getKeeperAndLenderSharesSplit_neverReverts -vv
    */
    /// forge-config: core_test.fuzz.runs = 10000
    function test_getKeeperAndLenderSharesSplit_neverGaveUpMoreAssets_fuzz(
        uint256 _assetsToLiquidate,
        bool _useProtected,
        uint256 _totalAssets,
        uint256 _totalShares
    ) public {
        _ensureNoOverflowsAndMockCall(_assetsToLiquidate, _useProtected, _totalAssets, _totalShares);

        // if ratio if way off we will be able to generate more assets that input assets to liquidate,
        // so we excluding this case here
        vm.assume(_totalAssets <= _totalShares);

        ISilo.CollateralType collateralType =
            _useProtected ? ISilo.CollateralType.Protected : ISilo.CollateralType.Collateral;

        (uint256 totalSharesToLiquidate,,) = defaulting.getKeeperAndLenderSharesSplit({
            _assetsToLiquidate: _assetsToLiquidate,
            _collateralType: collateralType
        });

        uint256 backToAssets = SiloMathLib.convertToAssets({
            _shares: totalSharesToLiquidate,
            _totalAssets: _totalAssets,
            _totalShares: _totalShares,
            _rounding: Rounding.WITHDRAW_TO_ASSETS,
            _assetType: ISilo.AssetType(uint8(collateralType))
        });

        console2.log("     backToAssets", backToAssets);
        console2.log("assetsToLiquidate", _assetsToLiquidate);

        assertLe(
            backToAssets, _assetsToLiquidate, "withdraw shares should gave us not more then input assets to liquidate"
        );
    }

    function _singleCheckWithMock(
        uint8 _id,
        uint256 _assetsToLiquidate,
        ISilo.CollateralType _collateralType,
        uint256 _expectedKeeperShares,
        uint256 _expectedLendersShares,
        uint256 _totalAssets,
        uint256 _totalShares
    ) internal {
        _mockTotalsCalls({_collateralType: _collateralType, _totalAssets: _totalAssets, _totalShares: _totalShares});

        _singleCheck({
            _id: _id,
            _assetsToLiquidate: _assetsToLiquidate,
            _collateralType: _collateralType,
            _expectedKeeperShares: _expectedKeeperShares,
            _expectedLendersShares: _expectedLendersShares
        });
    }

    function _singleCheck(
        uint8 _id,
        uint256 _assetsToLiquidate,
        ISilo.CollateralType _collateralType,
        uint256 _expectedKeeperShares,
        uint256 _expectedLendersShares
    ) internal view {
        string memory id = vm.toString(_id);
        console2.log("\t ------", id);

        (uint256 totalShares, uint256 keeperShares, uint256 lendersShares) = defaulting.getKeeperAndLenderSharesSplit({
            _assetsToLiquidate: _assetsToLiquidate,
            _collateralType: _collateralType
        });

        assertEq(lendersShares, _expectedLendersShares, string.concat("lenders shares failed for id: ", id));
        assertEq(keeperShares, _expectedKeeperShares, string.concat("keeper shares failed for id: ", id));
        assertEq(keeperShares + lendersShares, totalShares, string.concat("sum failed for id: ", id));
    }

    function _ensureNoOverflowsAndMockCall(
        uint256 _assetsToLiquidate,
        bool _useProtected,
        uint256 _totalAssets,
        uint256 _totalShares
    ) internal {
        ISilo.CollateralType collateralType =
            _useProtected ? ISilo.CollateralType.Protected : ISilo.CollateralType.Collateral;

        ///////////// prevent overflows START /////////////

        // we can revert in few places here actually eg when muldiv reverts, so when result will be oner 256 bits
        // but we do not want to cover extreamly high assets/shares in code, we care more about common cases and edge cases

        // in `_commonConverTo` we have: _totalAssets + 1
        vm.assume(_totalAssets <= type(uint256).max - 1);
        // in _commonConverTo: _totalShares + _DECIMALS_OFFSET_POW
        vm.assume(_totalShares <= type(uint256).max - SiloMathLib._DECIMALS_OFFSET_POW);

        uint256 totalAssetsCap = _totalShares == 0 ? 1 : _totalAssets + 1;
        uint256 totalSharesCap = _totalShares + SiloMathLib._DECIMALS_OFFSET_POW;

        // in convertToShares: _assets.mulDiv(totalShares, totalAssets, _rounding);
        vm.assume(_assetsToLiquidate / totalAssetsCap < type(uint256).max / totalSharesCap);

        // precalculate totalSharesToLiquidate
        uint256 totalSharesToLiquidate = SiloMathLib.convertToShares({
            _assets: _assetsToLiquidate,
            _totalAssets: _totalAssets,
            _totalShares: _totalShares,
            _rounding: Rounding.UP,
            _assetType: ISilo.AssetType(uint8(collateralType))
        });

        //  muldiv in `_getKeeperAndLenderSharesSplit`
        if (totalSharesToLiquidate != 0) {
            vm.assume(
                uint256(collateralConfig.liquidationFee) * defaulting.KEEPER_FEE()
                    < type(uint256).max / totalSharesToLiquidate
            );
        }

        ///////////// prevent overflows END /////////////

        _mockTotalsCalls(collateralType, _totalAssets, _totalShares);
    }

    function _mockTotalsCalls(ISilo.CollateralType _collateralType, uint256 _totalAssets, uint256 _totalShares)
        internal
    {
        vm.mockCall(
            silo0,
            abi.encodeWithSelector(ISilo.getTotalAssetsStorage.selector, ISilo.AssetType(uint8(_collateralType))),
            abi.encode(_totalAssets)
        );

        address shareToken =
            _collateralType == ISilo.CollateralType.Protected ? protectedShareToken : collateralShareToken;

        vm.mockCall(shareToken, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(_totalShares));
    }
}
