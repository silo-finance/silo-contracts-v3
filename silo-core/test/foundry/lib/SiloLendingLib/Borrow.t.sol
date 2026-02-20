// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

import {TokenMock} from "silo-core/test/foundry/_mocks/TokenMock.sol";
import {SiloLendingLibBorrowTestData} from "../../data-readers/SiloLendingLibBorrowTestData.sol";
import {SiloLendingLibImpl} from "../../_common/SiloLendingLibImpl.sol";

// solhint-disable func-name-mixedcase

/*
   forge test -vv --mc BorrowTest
*/
contract BorrowTest is Test {
    // solhint-disable immutable-vars-naming
    TokenMock public immutable PROTECTED_SHARE_TOKEN;
    TokenMock public immutable COLLATERAL_SHARE_TOKEN;
    TokenMock public immutable DEBT_SHARE_TOKEN;
    TokenMock public immutable DEBT_TOKEN;

    SiloLendingLibBorrowTestData public immutable TESTS;
    // solhint-enable immutable-vars-naming

    constructor() {
        PROTECTED_SHARE_TOKEN = new TokenMock(makeAddr("PROTECTED_SHARE_TOKEN"));
        COLLATERAL_SHARE_TOKEN = new TokenMock(makeAddr("COLLATERAL_SHARE_TOKEN"));
        DEBT_SHARE_TOKEN = new TokenMock(makeAddr("DEBT_SHARE_TOKEN"));
        DEBT_TOKEN = new TokenMock(makeAddr("DEBT_TOKEN"));

        TESTS = new SiloLendingLibBorrowTestData(
            PROTECTED_SHARE_TOKEN.ADDRESS(),
            COLLATERAL_SHARE_TOKEN.ADDRESS(),
            DEBT_SHARE_TOKEN.ADDRESS(),
            DEBT_TOKEN.ADDRESS()
        );
    }

    /*
    forge test -vv --mt test_borrow_zeros
    */
    function test_borrow_zeros() public {
        SiloLendingLibImpl impl = new SiloLendingLibImpl();

        ISiloConfig.ConfigData memory configData;
        configData.debtShareToken = makeAddr("DEBT_SHARE_TOKEN");

        vm.mockCall(configData.debtShareToken, abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(0));

        vm.expectRevert(ISilo.InputZeroShares.selector);

        impl.borrow({
            _debtShareToken: configData.debtShareToken,
            _token: configData.token,
            _assets: 0,
            _shares: 0,
            _receiver: address(0),
            _borrower: address(0),
            _spender: address(0),
            _totalDebt: 0,
            _totalCollateralAssets: 0
        });
    }

    /*
    forge test -vv --mt test_borrow_loop
    */
    function test_borrow_loop() public {
        SiloLendingLibBorrowTestData.SLLBData[] memory testDatas = TESTS.getData();
        SiloLendingLibImpl impl = new SiloLendingLibImpl();

        for (uint256 i; i < testDatas.length; i++) {
            vm.clearMockedCalls();
            emit log_string(testDatas[i].name);
            bool txReverts = testDatas[i].output.reverts != bytes4(0);

            if (testDatas[i].mocks.debtSharesTotalSupplyMock) {
                DEBT_SHARE_TOKEN.totalSupplyMock(testDatas[i].mocks.debtSharesTotalSupply, !txReverts);
            }

            if (testDatas[i].output.borrowedShare != 0) {
                DEBT_TOKEN.transferMock(testDatas[i].input.receiver, testDatas[i].output.borrowedAssets);

                DEBT_SHARE_TOKEN.mintMock(
                    testDatas[i].input.borrower, testDatas[i].input.spender, testDatas[i].output.borrowedShare
                );
            }

            if (txReverts) {
                vm.expectRevert(testDatas[i].output.reverts);
            }

            (uint256 borrowedAssets, uint256 borrowedShares) = impl.borrow(
                testDatas[i].input.configData.debtShareToken,
                testDatas[i].input.configData.token,
                testDatas[i].input.assets,
                testDatas[i].input.shares,
                testDatas[i].input.receiver,
                testDatas[i].input.borrower,
                testDatas[i].input.spender,
                testDatas[i].input.initTotalDebt,
                testDatas[i].input.totalCollateralAssets
            );

            assertEq(
                borrowedAssets,
                testDatas[i].output.borrowedAssets,
                string(abi.encodePacked(testDatas[i].name, " > borrowedAssets"))
            );
            assertEq(
                borrowedShares,
                testDatas[i].output.borrowedShare,
                string(abi.encodePacked(testDatas[i].name, " > borrowedShare"))
            );
        }
    }
}
