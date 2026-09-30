// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {SiloStdLib} from "silo-core/contracts/lib/SiloStdLib.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {SiloMock} from "../../_mocks/SiloMock.sol";
import {InterestRateModelMock} from "../../_mocks/InterestRateModelMock.sol";
import {TokenMock} from "../../_mocks/TokenMock.sol";

contract SiloStdLibImpl {
    function getTotalAssetsAndTotalSharesWithInterest(ISilo.AssetType _assetType) external view {
        ISiloConfig.ConfigData memory configData;
        SiloStdLib.getTotalAssetsAndTotalSharesWithInterest(configData, _assetType);
    }
}

/*
forge test -vv --mc GetTotalAssetsAndTotalSharesWithInterestTest
*/
contract GetTotalAssetsAndTotalSharesWithInterestTest is Test {
    struct DebtTestCases {
        uint256 rcomp;
        uint256 debtAssets;
        uint256 totalAssets;
    }

    struct CollateralTestCases {
        uint256 rcomp;
        uint256 debtAssets;
        uint256 collateralAssets;
        uint256 daoFee;
        uint256 deployerFee;
        uint256 totalAssets;
    }

    SiloMock immutable SILO;
    InterestRateModelMock immutable INTEREST_RATE_MODEL;
    TokenMock immutable PROTECTED_SHARE_TOKEN;
    TokenMock immutable COLLATERAL_SHARE_TOKEN;
    TokenMock immutable DEBT_SHARE_TOKEN;
    uint256 daoFee;
    uint256 deployerFee;

    mapping(uint256 => DebtTestCases) public debtTestCases;
    uint256 debtTestCasesIndex;

    mapping(uint256 => CollateralTestCases) public collateralTestCases;
    uint256 collateralTestCasesIndex;

    constructor() {
        SILO = new SiloMock(address(1));
        INTEREST_RATE_MODEL = new InterestRateModelMock();
        PROTECTED_SHARE_TOKEN = new TokenMock(address(2));
        COLLATERAL_SHARE_TOKEN = new TokenMock(address(3));
        DEBT_SHARE_TOKEN = new TokenMock(address(4));
    }

    /*
    forge test -vv --mt test_getTotalAssetsAndTotalSharesWithInterest_WrongType
    */
    function test_getTotalAssetsAndTotalSharesWithInterest_WrongType() public {
        SiloStdLibImpl impl = new SiloStdLibImpl();

        (bool success,) = address(impl).call(
            abi.encodeWithSelector(SiloStdLibImpl.getTotalAssetsAndTotalSharesWithInterest.selector, uint8(5))
        );

        assertTrue(!success, "call should fail for invalid asset type");
    }

    /*
    forge test -vv --mt test_getTotalAssetsAndTotalSharesWithInterest_zero
    */
    function test_getTotalAssetsAndTotalSharesWithInterest_zero() public {
        address silo = SILO.ADDRESS();

        uint256 totalAssets;
        uint256 totalShares;

        SILO.getProtectedAssetsMock(0);
        PROTECTED_SHARE_TOKEN.totalSupplyMock(0);

        (totalAssets, totalShares) =
            SiloStdLib.getTotalAssetsAndTotalSharesWithInterest(_config(), ISilo.AssetType.Protected);

        assertEq(totalAssets, 0);
        assertEq(totalShares, 0);

        SILO.getCollateralAndDebtAssetsMock(0, 0);
        COLLATERAL_SHARE_TOKEN.totalSupplyMock(0);
        INTEREST_RATE_MODEL.getCompoundInterestRateMock(silo, block.timestamp, 0);
        (totalAssets, totalShares) =
            SiloStdLib.getTotalAssetsAndTotalSharesWithInterest(_config(), ISilo.AssetType.Collateral);

        assertEq(totalAssets, 0);
        assertEq(totalShares, 0);

        DEBT_SHARE_TOKEN.totalSupplyMock(0);
        SILO.totalMock(ISilo.AssetType.Debt, 0);
        (totalAssets, totalShares) =
            SiloStdLib.getTotalAssetsAndTotalSharesWithInterest(_config(), ISilo.AssetType.Debt);

        assertEq(totalAssets, 0);
        assertEq(totalShares, 0);
    }

    /*
    forge test -vv --mt test_getTotalAssetsAndTotalSharesWithInterest_totalSupply_fuzz
    */
    function test_getTotalAssetsAndTotalSharesWithInterest_totalSupply_fuzz(uint256 _totalSupply) public {
        address silo = SILO.ADDRESS();

        uint256 totalAssets;
        uint256 totalShares;

        SILO.getProtectedAssetsMock(0);
        PROTECTED_SHARE_TOKEN.totalSupplyMock(_totalSupply);

        (totalAssets, totalShares) =
            SiloStdLib.getTotalAssetsAndTotalSharesWithInterest(_config(), ISilo.AssetType.Protected);

        assertEq(totalAssets, 0);
        assertEq(totalShares, _totalSupply);

        SILO.getCollateralAndDebtAssetsMock(0, 0);
        COLLATERAL_SHARE_TOKEN.totalSupplyMock(_totalSupply);
        INTEREST_RATE_MODEL.getCompoundInterestRateMock(silo, block.timestamp, 0);
        (totalAssets, totalShares) =
            SiloStdLib.getTotalAssetsAndTotalSharesWithInterest(_config(), ISilo.AssetType.Collateral);

        assertEq(totalAssets, 0);
        assertEq(totalShares, _totalSupply);

        DEBT_SHARE_TOKEN.totalSupplyMock(_totalSupply);
        SILO.totalMock(ISilo.AssetType.Debt, 0);
        (totalAssets, totalShares) =
            SiloStdLib.getTotalAssetsAndTotalSharesWithInterest(_config(), ISilo.AssetType.Debt);

        assertEq(totalAssets, 0);
        assertEq(totalShares, _totalSupply);
    }

    /*
    forge test -vv --mt test_getTotalAssetsAndTotalSharesWithInterest_protected_fuzz
    */
    function test_getTotalAssetsAndTotalSharesWithInterest_protected_fuzz(
        uint256 _totalSupply,
        uint256 _protectedAssets
    ) public {
        uint256 totalAssets;
        uint256 totalShares;

        SILO.getProtectedAssetsMock(_protectedAssets);
        PROTECTED_SHARE_TOKEN.totalSupplyMock(_totalSupply);

        (totalAssets, totalShares) =
            SiloStdLib.getTotalAssetsAndTotalSharesWithInterest(_config(), ISilo.AssetType.Protected);

        assertEq(totalAssets, _protectedAssets);
        assertEq(totalShares, _totalSupply);
    }

    /*
    forge test -vv --mt test_getTotalAssetsAndTotalSharesWithInterest_debt_fuzz
    */
    function test_getTotalAssetsAndTotalSharesWithInterest_debt_fuzz(uint256 _totalSupply) public {
        debtTestCases[debtTestCasesIndex++] = DebtTestCases({rcomp: 0.1e18, debtAssets: 1e18, totalAssets: 1.1e18});
        debtTestCases[debtTestCasesIndex++] = DebtTestCases({rcomp: 0e18, debtAssets: 1e18, totalAssets: 1e18});
        debtTestCases[debtTestCasesIndex++] = DebtTestCases({rcomp: 10e18, debtAssets: 1e18, totalAssets: 11e18});
        debtTestCases[debtTestCasesIndex++] = DebtTestCases({rcomp: 0, debtAssets: 1e18, totalAssets: 1e18});
        debtTestCases[debtTestCasesIndex++] = DebtTestCases({rcomp: 0.1e18, debtAssets: 0, totalAssets: 0});
        debtTestCases[debtTestCasesIndex++] =
            DebtTestCases({rcomp: 0.05e18, debtAssets: 100e18, totalAssets: 105e18});

        address silo = SILO.ADDRESS();

        uint256 totalAssets;
        uint256 totalShares;

        for (uint256 index = 0; index < debtTestCasesIndex; index++) {
            SILO.totalMock(ISilo.AssetType.Debt, debtTestCases[index].debtAssets);
            DEBT_SHARE_TOKEN.totalSupplyMock(_totalSupply);
            INTEREST_RATE_MODEL.getCompoundInterestRateMock(silo, block.timestamp, debtTestCases[index].rcomp);

            (totalAssets, totalShares) =
                SiloStdLib.getTotalAssetsAndTotalSharesWithInterest(_config(), ISilo.AssetType.Debt);

            assertEq(totalAssets, debtTestCases[index].totalAssets);
            assertEq(totalShares, _totalSupply);
        }
    }

    /*
    forge test -vv --mt test_getTotalAssetsAndTotalSharesWithInterest_collateral_fuzz
    */
    function test_getTotalAssetsAndTotalSharesWithInterest_collateral_fuzz(uint256 _totalSupply) public {
        collateralTestCases[collateralTestCasesIndex++] = CollateralTestCases({
            rcomp: 0.1e18,
            debtAssets: 1e18,
            collateralAssets: 1e18,
            daoFee: 0.2e18,
            deployerFee: 0.1e18,
            totalAssets: 1.07e18
        });

        collateralTestCases[collateralTestCasesIndex++] = CollateralTestCases({
            rcomp: 0.1e18,
            debtAssets: 0,
            collateralAssets: 1e18,
            daoFee: 0.2e18,
            deployerFee: 0.1e18,
            totalAssets: 1e18
        });

        collateralTestCases[collateralTestCasesIndex++] = CollateralTestCases({
            rcomp: 0,
            debtAssets: 1e18,
            collateralAssets: 1e18,
            daoFee: 0.2e18,
            deployerFee: 0.1e18,
            totalAssets: 1e18
        });

        collateralTestCases[collateralTestCasesIndex++] = CollateralTestCases({
            rcomp: 0.35e18,
            debtAssets: 100e18,
            collateralAssets: 250e18,
            daoFee: 0.25e18,
            deployerFee: 0.05e18,
            totalAssets: 274.5e18
        });

        collateralTestCases[collateralTestCasesIndex++] = CollateralTestCases({
            rcomp: 0.35e18,
            debtAssets: 100e18,
            collateralAssets: 0,
            daoFee: 0.25e18,
            deployerFee: 0.05e18,
            totalAssets: 24.5e18
        });

        collateralTestCases[collateralTestCasesIndex++] = CollateralTestCases({
            rcomp: 0.35e18,
            debtAssets: 100e18,
            collateralAssets: 250e18,
            daoFee: 0.3e18,
            deployerFee: 0,
            totalAssets: 274.5e18
        });

        collateralTestCases[collateralTestCasesIndex++] = CollateralTestCases({
            rcomp: 0.35e18,
            debtAssets: 100e18,
            collateralAssets: 250e18,
            daoFee: 0,
            deployerFee: 0.3e18,
            totalAssets: 274.5e18
        });

        address silo = SILO.ADDRESS();

        uint256 totalAssets;
        uint256 totalShares;

        for (uint256 index = 0; index < collateralTestCasesIndex; index++) {
            SILO.getCollateralAndDebtAssetsMock(
                collateralTestCases[index].collateralAssets, collateralTestCases[index].debtAssets
            );
            COLLATERAL_SHARE_TOKEN.totalSupplyMock(_totalSupply);
            INTEREST_RATE_MODEL.getCompoundInterestRateMock(silo, block.timestamp, collateralTestCases[index].rcomp);
            daoFee = collateralTestCases[index].daoFee;
            deployerFee = collateralTestCases[index].deployerFee;

            (totalAssets, totalShares) =
                SiloStdLib.getTotalAssetsAndTotalSharesWithInterest(_config(), ISilo.AssetType.Collateral);

            assertEq(totalAssets, collateralTestCases[index].totalAssets);
            assertEq(totalShares, _totalSupply);
        }
    }

    function _config() internal view returns (ISiloConfig.ConfigData memory configData) {
        configData.silo = SILO.ADDRESS();
        configData.collateralShareToken = COLLATERAL_SHARE_TOKEN.ADDRESS();
        configData.protectedShareToken = PROTECTED_SHARE_TOKEN.ADDRESS();
        configData.debtShareToken = DEBT_SHARE_TOKEN.ADDRESS();
        configData.interestRateModel = INTEREST_RATE_MODEL.ADDRESS();
        configData.daoFee = daoFee;
        configData.deployerFee = deployerFee;
    }
}
