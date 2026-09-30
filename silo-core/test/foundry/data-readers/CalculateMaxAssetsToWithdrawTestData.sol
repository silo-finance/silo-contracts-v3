// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

contract CalculateMaxAssetsToWithdrawTestData {
    struct Input {
        uint256 sumOfCollateralsValue;
        uint256 debtValue;
        uint256 lt;
        uint256 borrowerCollateralAssets;
        uint256 borrowerProtectedAssets;
    }

    struct CMATWData {
        string name;
        Input input;
        uint256 maxAssets;
    }

    CMATWData[] allData;

    function getData() external returns (CMATWData[] memory data) {
        _add(0, 0, 0, 0, 0, 0, "when all zeros");
        _add(1, 0, 0, 1, 0, 1, "when no debt");
        _add(1, 0, 0, 0, 1, 1, "when no debt");
        _add(100, 1, 0, 0, 0, 0, "when over LT");
        _add(1e4, 1, 0.0001e18, 0, 0, 0, "LT is 0.01% and LTV is 0.01%");

        uint256 ourMax = 9900;
        _add(1e4, 1, 0.01e18, 0.5e4, 0.5e4, ourMax);
        _add(1e4, 1, 0.01e18, 0.8e4, 0.2e4, ourMax);
        _add(1e4, 1, 0.01e18, 1e4, 0, ourMax);
        _add(1e4, 1, 0.01e18, 0, 1e4, ourMax);
        _add(1e4 - ourMax, 0, 0.01e18, 101, 0, 100);

        ourMax = 2e4 - 200;
        _add(1e4, 1, 0.01e18, 1e4, 1e4, ourMax, "LT 1%, debt 1, so collateral must be 100 (e4)");
        _add(1e4 - ourMax / 2, 1, 0.01e18, 200, 0, 0, "based on prev, we expect 0");

        _add(100, 80, 0.8e18, 0, 0, 0, "exact LT");
        _add(101, 80, 0.8e18, 100, 1, 1);

        _add(10, 8, 0.8888e18, 10, 10, 0, "8/(10 - 1) = 100% > LT (!), only zero is acceptable");

        ourMax = 999099909990999099;
        _add(10e18, 8e18, 0.8888e18, 5e18, 5e18, ourMax, "LTV after => 88,88% (1)");
        _add(10e18 - ourMax, 8e18, 0.8888e18, 10e18 - ourMax, 0, 0, "based on above, we should expect 0");

        ourMax = uint256(999099909990999099) / 5;
        _add(10e18, 8e18, 0.8888e18, 1e18, 1e18, ourMax, "LTV after => 88,88% (2)");
        _add(10e18 - ourMax * 5, 8e18, 0.8888e18, 1e18 - ourMax, 0, 0, "^ LTV after => 88,88% (2)");

        //  0.1e18 / (3e18 - 2882352941176470589));
        ourMax = 2882352941176470588;
        _add(3e18, 0.1e18, 0.85e18, 2e18, 1e18, ourMax, "LTV after => 85%");
        _add(3e18 - ourMax, 0.1e18, 0.85e18, 0, 3e18 - ourMax, 0, "^ LTV after => 85%");

        return allData;
    }

    function _add(
        uint256 _sumOfCollateralsValue,
        uint256 _debtValue,
        uint256 _lt,
        uint256 _borrowerCollateralAssets,
        uint256 _borrowerProtectedAssets,
        uint256 _maxAssets
    ) private {
        _add(
            _sumOfCollateralsValue,
            _debtValue,
            _lt,
            _borrowerCollateralAssets,
            _borrowerProtectedAssets,
            _maxAssets,
            ""
        );
    }

    function _add(
        uint256 _sumOfCollateralsValue,
        uint256 _debtValue,
        uint256 _lt,
        uint256 _borrowerCollateralAssets,
        uint256 _borrowerProtectedAssets,
        uint256 _maxAssets,
        string memory _name
    ) private {
        uint256 i = allData.length;
        allData.push();
        allData[i].name = _name;
        allData[i].input.sumOfCollateralsValue = _sumOfCollateralsValue;
        allData[i].input.debtValue = _debtValue;
        allData[i].input.lt = _lt;
        allData[i].input.borrowerCollateralAssets = _borrowerCollateralAssets;
        allData[i].input.borrowerProtectedAssets = _borrowerProtectedAssets;
        allData[i].maxAssets = _maxAssets;
    }
}
