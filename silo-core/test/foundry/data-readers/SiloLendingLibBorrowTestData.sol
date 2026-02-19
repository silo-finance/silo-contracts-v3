// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";

contract SiloLendingLibBorrowTestData {
    struct Input {
        ISiloConfig.ConfigData configData;
        uint256 assets;
        uint256 shares;
        address receiver;
        address borrower;
        address spender;
        uint256 initTotalDebt;
        uint256 totalCollateralAssets;
    }

    struct Mocks {
        uint256 protectedShareTokenBalanceOf;
        uint256 collateralShareTokenBalanceOf;
        uint256 debtSharesTotalSupply;
        bool debtSharesTotalSupplyMock;
    }

    struct Output {
        uint256 borrowedAssets;
        uint256 borrowedShare;
        bytes4 reverts;
    }

    struct SllbData {
        string name;
        Input input;
        Mocks mocks;
        Output output;
    }

    address immutable protectedShareToken;
    address immutable collateralShareToken;
    address immutable debtShareToken;
    address immutable debtToken;

    constructor(
        address _protectedShareToken,
        address _collateralShareToken,
        address _debtShareToken,
        address _debtToken
    ) {
        protectedShareToken = _protectedShareToken;
        collateralShareToken = _collateralShareToken;
        debtShareToken = _debtShareToken;
        debtToken = _debtToken;
    }

    function getData() external view returns (SllbData[] memory data) {
        data = new SllbData[](12);
        uint256 i;

        _init(data[i], "#0 all zeros");
        data[i].output.reverts = ISilo.InputZeroShares.selector;
        data[i].mocks.debtSharesTotalSupplyMock = true;

        i++;
        _init(data[i], "#1 NotEnoughLiquidity if no collateral");
        data[i].input.assets = 1;
        data[i].output.reverts = ISilo.NotEnoughLiquidity.selector;

        i++;
        _init(data[i], "#2 NotEnoughLiquidity if not enough collateral");
        data[i].input.assets = 3;
        data[i].input.totalCollateralAssets = 3;
        data[i].input.initTotalDebt = 1;
        data[i].output.reverts = ISilo.NotEnoughLiquidity.selector;

        i++;
        _init(data[i], "#3 NotEnoughLiquidity if not enough collateral (2)");
        data[i].input.assets = 3;
        data[i].input.totalCollateralAssets = 3;
        data[i].input.initTotalDebt = 3;
        data[i].output.reverts = ISilo.NotEnoughLiquidity.selector;

        i++;
        _init(data[i], "#4 NotEnoughLiquidity if not enough collateral (3)");
        data[i].input.assets = 3;
        data[i].input.totalCollateralAssets = 3;
        data[i].input.initTotalDebt = 5;
        data[i].output.reverts = ISilo.NotEnoughLiquidity.selector;

        i++;
        _init(data[i], "#5 can borrow if borrow amount under liquidity");
        data[i].input.assets = 4;
        data[i].input.totalCollateralAssets = 5;
        data[i].input.initTotalDebt = 1;
        data[i].mocks.debtSharesTotalSupply = 100;
        data[i].output.borrowedAssets = 4;
        data[i].output.borrowedShare = 400;

        i++;
        _init(data[i], "#6 input can be assets or shares");
        data[i].input.assets = 2;
        data[i].input.shares = 444444;
        data[i].output.reverts = ISilo.InputCanBeAssetsOrShares.selector;

        i++;
        _init(data[i], "#7 1st borrow: 100");
        data[i].input.assets = 100;
        data[i].input.totalCollateralAssets = 10000;
        data[i].input.initTotalDebt = 0;
        data[i].mocks.debtSharesTotalSupply = 0;
        data[i].output.borrowedAssets = 100;
        data[i].output.borrowedShare = 100;

        i++;
        _init(data[i], "#8 2nd borrow: 100, 200");
        data[i].input.assets = 200;
        data[i].input.totalCollateralAssets = data[i - 1].input.totalCollateralAssets;
        data[i].input.initTotalDebt = 100;
        data[i].mocks.debtSharesTotalSupply = 100;
        data[i].output.borrowedAssets = 200;
        data[i].output.borrowedShare = 200;

        i++;
        _init(data[i], "#9 3rd borrow: 100, 200, 5000s");
        data[i].input.shares = 5000;
        data[i].input.totalCollateralAssets = data[i - 1].input.totalCollateralAssets;
        data[i].input.initTotalDebt = 100 + 200;
        data[i].mocks.debtSharesTotalSupply = (100 + 200);
        data[i].output.borrowedAssets = 5000;
        data[i].output.borrowedShare = 5000;

        i++;
        _init(data[i], "#10 4th borrow: 100, 200, 5000s, all the rest");
        uint256 allTheRest = 5000 - 100 - 200 - 50;
        data[i].input.assets = allTheRest;
        data[i].input.totalCollateralAssets = data[i - 1].input.totalCollateralAssets;
        data[i].input.initTotalDebt = 100 + 200 + 50;
        data[i].mocks.debtSharesTotalSupply = (100 + 200 + 50);
        data[i].output.borrowedAssets = allTheRest;
        data[i].output.borrowedShare = allTheRest;

        i++;
        _init(data[i], "#11 can borrow with fee");
        data[i].input.assets = 4e18;
        data[i].input.totalCollateralAssets = 5e18;
        data[i].input.initTotalDebt = 1e18;
        data[i].input.configData.daoFee = 0.01e18;
        data[i].input.configData.deployerFee = 0.03e18;
        data[i].mocks.debtSharesTotalSupply = 100e18;
        data[i].output.borrowedAssets = 4e18;
        data[i].output.borrowedShare = 400e18;
    }

    function _init(SllbData memory _src, string memory _name) private view {
        _src.name = _name;

        _src.input.configData.protectedShareToken = protectedShareToken;
        _src.input.configData.collateralShareToken = collateralShareToken;
        _src.input.configData.debtShareToken = debtShareToken;
        _src.input.configData.token = debtToken;

        _src.input.configData.maxLtv = 0.8e4;

        _src.input.receiver = address(0x123333333);
        _src.input.borrower = address(0x345555555);
        _src.input.spender = address(0x567777777);

        _src.mocks.debtSharesTotalSupplyMock = true;
    }

    function _clone(SllbData memory _src) private pure returns (SllbData memory dst) {
        dst.input = Input({
            configData: ISiloConfig.ConfigData({
                daoFee: _src.input.configData.daoFee,
                deployerFee: _src.input.configData.deployerFee,
                silo: _src.input.configData.silo,
                token: _src.input.configData.token,
                protectedShareToken: _src.input.configData.protectedShareToken,
                collateralShareToken: _src.input.configData.collateralShareToken,
                debtShareToken: _src.input.configData.debtShareToken,
                solvencyOracle: _src.input.configData.solvencyOracle,
                maxLtvOracle: _src.input.configData.maxLtvOracle,
                interestRateModel: _src.input.configData.interestRateModel,
                maxLtv: _src.input.configData.maxLtv,
                lt: _src.input.configData.lt,
                liquidationTargetLtv: _src.input.configData.liquidationTargetLtv,
                liquidationFee: _src.input.configData.liquidationFee,
                flashloanFee: _src.input.configData.flashloanFee,
                hookReceiver: _src.input.configData.hookReceiver,
                callBeforeQuote: _src.input.configData.callBeforeQuote
            }),
            assets: _src.input.assets,
            shares: _src.input.shares,
            receiver: _src.input.receiver,
            borrower: _src.input.borrower,
            spender: _src.input.spender,
            initTotalDebt: _src.input.initTotalDebt,
            totalCollateralAssets: _src.input.totalCollateralAssets
        });
        dst.mocks = Mocks({
            protectedShareTokenBalanceOf: _src.mocks.protectedShareTokenBalanceOf,
            collateralShareTokenBalanceOf: _src.mocks.collateralShareTokenBalanceOf,
            debtSharesTotalSupply: _src.mocks.debtSharesTotalSupply,
            debtSharesTotalSupplyMock: _src.mocks.debtSharesTotalSupplyMock
        });
        dst.output = Output({
            borrowedAssets: _src.output.borrowedAssets,
            borrowedShare: _src.output.borrowedShare,
            reverts: _src.output.reverts
        });
    }
}
