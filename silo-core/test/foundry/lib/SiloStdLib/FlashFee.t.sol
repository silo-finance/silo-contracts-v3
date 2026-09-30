// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {SiloStdLib} from "silo-core/contracts/lib/SiloStdLib.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {SiloConfigMock} from "../../_mocks/SiloConfigMock.sol";

/*
forge test -vv --mc FlashFeeTest
*/
contract FlashFeeTest is Test {
    struct FeeTestCase {
        uint256 flashloanFee;
        uint256 amount;
        uint256 fee;
    }

    SiloConfigMock immutable SILO_CONFIG;

    uint256 daoFee;
    uint256 deployerFee;

    mapping(uint256 => FeeTestCase) public feeTestCases;
    uint256 feeTestCasesIndex;

    constructor() {
        SILO_CONFIG = new SiloConfigMock(address(1));
    }

    /*
    forge test -vv --mt test_flashFee_fuzz
    */
    function test_flashFee_fuzz(address _asset) public {
        vm.assume(_asset != address(0));

        ISiloConfig siloConfig = ISiloConfig(SILO_CONFIG.ADDRESS());

        feeTestCases[feeTestCasesIndex++] = FeeTestCase({flashloanFee: 0.1e18, amount: 1e18, fee: 0.1e18});
        feeTestCases[feeTestCasesIndex++] = FeeTestCase({flashloanFee: 0, amount: 1e18, fee: 0});
        feeTestCases[feeTestCasesIndex++] = FeeTestCase({flashloanFee: 1, amount: 1, fee: 1});
        feeTestCases[feeTestCasesIndex++] = FeeTestCase({flashloanFee: 0.125e18, amount: 1e18, fee: 0.125e18});
        feeTestCases[feeTestCasesIndex++] = FeeTestCase({flashloanFee: 0.65e18, amount: 1e18, fee: 0.65e18});

        for (uint256 index = 0; index < feeTestCasesIndex; index++) {
            if (feeTestCases[index].amount != 0) {
                SILO_CONFIG.getFeesWithAssetMock(address(this), 0, 0, feeTestCases[index].flashloanFee, _asset);
            }

            assertEq(SiloStdLib.flashFee(siloConfig, _asset, feeTestCases[index].amount), feeTestCases[index].fee);
        }
    }
}
