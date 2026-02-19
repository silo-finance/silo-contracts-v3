// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

contract MaxBorrowValueToAssetsAndSharesTestData {
    struct Input {
        uint256 maxBorrowValue;
        address debtToken;
        bool oracleSet;
        uint256 debtOracleQuote;
        uint256 totalDebtAssets;
        uint256 totalDebtShares;
    }

    struct Output {
        uint256 assets;
        uint256 shares;
    }

    struct MbvData {
        string name;
        Input input;
        Output output;
    }

    address immutable debtToken;

    MbvData[] allData;

    constructor(address _debtToken) {
        debtToken = _debtToken;
    }

    function getData() external returns (MbvData[] memory data) {
        uint256 i;

        i = _init("all zeros");

        i = _init("no borrow yet");
        allData[i].input.maxBorrowValue = 1;
        allData[i].output.assets = 1;
        allData[i].output.shares = 1;

        i = _init("no borrow yet case2");
        allData[i].input.maxBorrowValue = 100;
        allData[i].output.assets = 100;
        allData[i].output.shares = 100;

        i = _init("with some debt, 1value=1assets (but undervalued by totalDebt++)");
        allData[i].input.maxBorrowValue = 100;
        allData[i].input.totalDebtShares = 9;
        allData[i].input.totalDebtAssets = 9;
        allData[i].output.assets = 88;
        allData[i].output.shares = 100;

        i = _init("has some debt, assets:shares is 1:2");
        allData[i].input.maxBorrowValue = 100;
        allData[i].input.totalDebtShares = 18;
        allData[i].input.totalDebtAssets = 9; // 18 / (9 + 1) => 1:1,8 - this is undervaluation
        allData[i].output.assets = 88; // for no oracle, value == assets, undervalued by totalDebt++
        allData[i].output.shares = 200;

        i = _init("has some debt, assets:shares is 1:2, with oracle (1e18) => 3e18");
        allData[i].input.maxBorrowValue = 100;
        allData[i].input.totalDebtShares = 18;
        allData[i].input.totalDebtAssets = 9;
        allData[i].input.oracleSet = true;
        allData[i].input.debtOracleQuote = 3e18;
        allData[i].output.assets = 29;
        allData[i].output.shares = uint256(100) / 3 * 2; // *2 because of ratio

        i = _init("has some debt, assets:shares is 2:1");
        allData[i].input.maxBorrowValue = 5e18;
        allData[i].input.totalDebtShares = 400e18;
        allData[i].input.totalDebtAssets = 200e18;
        allData[i].output.assets = 5e18 - 1;
        allData[i].output.shares = 5e18 * 2;

        i = _init("has some debt, assets:shares is 2:1, with oracle (1e18) => 1e18");
        allData[i].input.maxBorrowValue = 5e18;
        allData[i].input.totalDebtShares = 400e18;
        allData[i].input.totalDebtAssets = 200e18;
        allData[i].input.oracleSet = true;
        allData[i].input.debtOracleQuote = 1e18;
        allData[i].output.assets = 5e18 - 1;
        allData[i].output.shares = 5e18 * 2;

        i = _init("has some debt, assets:shares is 2:1, with oracle (1e18) => 0.5e18");
        allData[i].input.maxBorrowValue = 5e18;
        allData[i].input.totalDebtShares = 400e18;
        allData[i].input.totalDebtAssets = 200e18;
        allData[i].input.oracleSet = true;
        allData[i].input.debtOracleQuote = 0.5e18;
        allData[i].output.assets = (5e18 * 2) - 1;
        allData[i].output.shares = (5e18 * 2) * 2;

        i = _init("has some debt, assets:shares is 2:1, with oracle (1e18) => 1e6 eg different decimals");
        allData[i].input.maxBorrowValue = 5e6; // value is in quote token, so 6 decimals
        allData[i].input.totalDebtShares = 400e18;
        allData[i].input.totalDebtAssets = 200e18;
        allData[i].input.oracleSet = true;
        allData[i].input.debtOracleQuote = 1e6;
        allData[i].output.assets = 5e18 - 1;
        allData[i].output.shares = 5e18 * 2;

        return allData;
    }

    function _init(string memory _name) private returns (uint256 i) {
        i = allData.length;
        allData.push();

        allData[i].name = string(abi.encodePacked("#", toString(i), " ", _name));

        allData[i].input.debtToken = debtToken;
    }

    function _clone(MbvData memory _src) private pure returns (MbvData memory dst) {
        dst.input = Input({
            maxBorrowValue: _src.input.maxBorrowValue,
            debtToken: _src.input.debtToken,
            oracleSet: _src.input.oracleSet,
            debtOracleQuote: _src.input.debtOracleQuote,
            totalDebtAssets: _src.input.totalDebtAssets,
            totalDebtShares: _src.input.totalDebtShares
        });
        dst.output = Output({assets: _src.output.assets, shares: _src.output.shares});
    }

    function toString(uint256 _i) internal pure returns (string memory str) {
        if (_i == 0) return "0";

        while (_i != 0) {
            uint256 r = _i % 10;
            str = string(abi.encodePacked(str, r + 48));
            _i /= 10;
        }
    }
}
