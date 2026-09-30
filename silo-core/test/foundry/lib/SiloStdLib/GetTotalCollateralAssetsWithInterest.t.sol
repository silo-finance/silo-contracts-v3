// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SiloStdLib} from "silo-core/contracts/lib/SiloStdLib.sol";

import {SiloMock} from "../../_mocks/SiloMock.sol";
import {InterestRateModelMock} from "../../_mocks/InterestRateModelMock.sol";

// forge test -vv --mc GetTotalAssetsWithInterestTest
contract GetTotalAssetsWithInterestTest is Test {
    uint256 constant DECIMALS_POINTS = 1e18;

    SiloMock immutable SILO;
    InterestRateModelMock immutable INTEREST_RATE_MODEL;

    constructor() {
        SILO = new SiloMock(address(0));
        INTEREST_RATE_MODEL = new InterestRateModelMock();
    }

    /*
    forge test -vv --mt test_getTotalCollateralAssetsWithInterest
    */
    function test_getTotalCollateralAssetsWithInterest() public {
        address silo = SILO.ADDRESS();
        address interestRateModel = INTEREST_RATE_MODEL.ADDRESS();
        uint256 daoFee;
        uint256 deployerFee;

        SILO.getCollateralAndDebtAssetsMock(0, 0);
        INTEREST_RATE_MODEL.getCompoundInterestRateMock(silo, block.timestamp, 0);
        assertEq(SiloStdLib.getTotalCollateralAssetsWithInterest(silo, interestRateModel, daoFee, deployerFee), 0);

        INTEREST_RATE_MODEL.getCompoundInterestRateMock(silo, block.timestamp, 0.01e18);
        assertEq(SiloStdLib.getTotalCollateralAssetsWithInterest(silo, interestRateModel, daoFee, deployerFee), 0);

        SILO.getCollateralAndDebtAssetsMock(1000e18, 0);
        assertEq(
            SiloStdLib.getTotalCollateralAssetsWithInterest(silo, interestRateModel, daoFee, deployerFee), 1000e18
        );

        SILO.getCollateralAndDebtAssetsMock(1000e18, 500e18);
        assertEq(
            SiloStdLib.getTotalCollateralAssetsWithInterest(silo, interestRateModel, daoFee, deployerFee), 1005e18
        );

        SILO.getCollateralAndDebtAssetsMock(1000e18, 1000e18);
        daoFee = 0.01e18;
        assertEq(
            SiloStdLib.getTotalCollateralAssetsWithInterest(silo, interestRateModel, daoFee, deployerFee),
            1009.9e18,
            "with daoFee"
        );

        deployerFee = 0.03e18;
        assertEq(
            SiloStdLib.getTotalCollateralAssetsWithInterest(silo, interestRateModel, daoFee, deployerFee),
            1009.6e18,
            "with daoFee + deployerFee"
        );

        daoFee = 0;
        deployerFee = 0.03e18;
        assertEq(
            SiloStdLib.getTotalCollateralAssetsWithInterest(silo, interestRateModel, daoFee, deployerFee),
            1009.7e18,
            "with deployerFee"
        );
    }
}
