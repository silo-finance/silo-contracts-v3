// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";

contract MaxWithdrawToAssetsAndSharesTestData {
    struct Input {
        uint256 maxAssets;
        uint256 borrowerCollateralAssets;
        uint256 borrowerProtectedAssets;
        ISilo.CollateralType assetType;
        uint256 totalAssets;
        uint256 assetTypeShareTokenTotalSupply;
        uint256 liquidity;
    }

    struct Output {
        uint256 assets;
        uint256 shares;
    }

    struct MWTASData {
        string name;
        Input input;
        Output output;
    }

    MWTASData[] allData;

    function getData() external returns (MWTASData[] memory data) {
        uint256 i;

        i = _init("all zeros");

        i = _init("if only maxAssets is 0, we still returns 0");
        allData[i].input.maxAssets = 1;

        i = _init("[protected] if only maxAssets is 0, we still returns 0");
        allData[i].input.assetType = ISilo.CollateralType.Protected;
        allData[i].input.maxAssets = 1;

        i = _init("[protected] if total share supply 0, we should get 0");
        allData[i].input.assetType = ISilo.CollateralType.Protected;
        allData[i].input.maxAssets = 1;
        allData[i].input.borrowerProtectedAssets = 1;

        i = _init("[protected] 1s");
        allData[i].input.assetType = ISilo.CollateralType.Protected;
        allData[i].input.maxAssets = 1;
        allData[i].input.borrowerProtectedAssets = 1;
        allData[i].input.totalAssets = 1;
        allData[i].input.assetTypeShareTokenTotalSupply = 1;

        allData[i].output.assets = 1;
        allData[i].output.shares = 500;

        i = _init("[protected] maxAssets=10 but cap=1");
        _clone(allData[i - 1], allData[i]);
        allData[i].input.maxAssets = 10;

        i = _init("[protected] when below borrowerProtectedAssets");
        allData[i].input.assetType = ISilo.CollateralType.Protected;
        allData[i].input.maxAssets = 0.1e18;
        allData[i].input.borrowerProtectedAssets = 0.5e18;
        allData[i].input.totalAssets = 1e18;
        allData[i].input.assetTypeShareTokenTotalSupply = 1e18;

        allData[i].output.assets = 0.1e18;
        allData[i].output.shares = 100000000000000099;

        i = _init("[protected] when above borrowerProtectedAssets");
        allData[i].input.assetType = ISilo.CollateralType.Protected;
        allData[i].input.maxAssets = 1e18;
        allData[i].input.borrowerProtectedAssets = 0.5e18;
        allData[i].input.totalAssets = 1e18;
        allData[i].input.assetTypeShareTokenTotalSupply = 1e18;

        allData[i].output.assets = 0.5e18;
        allData[i].output.shares = 500000000000000499;

        // ==================================================

        i = _init("[collateral] 1s, without liquidity");
        allData[i].input.assetType = ISilo.CollateralType.Collateral;
        allData[i].input.maxAssets = 1;
        allData[i].input.borrowerCollateralAssets = 1;
        allData[i].input.totalAssets = 1;
        allData[i].input.assetTypeShareTokenTotalSupply = 1;

        i = _init("[collateral] 1s, with liquidity");
        allData[i].input.assetType = ISilo.CollateralType.Collateral;
        allData[i].input.maxAssets = 1;
        allData[i].input.borrowerCollateralAssets = 1;
        allData[i].input.totalAssets = 1;
        allData[i].input.assetTypeShareTokenTotalSupply = 1;
        allData[i].input.liquidity = 1;

        allData[i].output.assets = 1;
        allData[i].output.shares = 500;

        i = _init("[collateral] maxAssets=10 but cap=1");
        _clone(allData[i - 1], allData[i]);
        allData[i].input.maxAssets = 10;

        i = _init("[collateral] 1s, without borrowerCollateralAssets");
        _clone(allData[i - 1], allData[i]);
        allData[i].input.borrowerCollateralAssets = 0;

        allData[i].output.assets = 0;
        allData[i].output.shares = 0;

        i = _init("[collateral] when below borrowerCollateralAssets");
        allData[i].input.assetType = ISilo.CollateralType.Collateral;
        allData[i].input.maxAssets = 0.1e18;
        allData[i].input.borrowerCollateralAssets = 0.5e18;
        allData[i].input.totalAssets = 1e18;
        allData[i].input.assetTypeShareTokenTotalSupply = 1e18;
        allData[i].input.liquidity = 100e18;

        allData[i].output.assets = 0.1e18;
        allData[i].output.shares = 100000000000000099;

        i = _init("[collateral] when borrowerCollateralAssets < MAX < liquidity");
        _clone(allData[i - 1], allData[i]);
        allData[i].input.maxAssets = 0.8e18;

        allData[i].output.assets = 0.5e18;
        allData[i].output.shares = 500000000000000499;

        i = _init("[collateral] when liquidity < borrowerCollateralAssets < X");
        _clone(allData[i - 1], allData[i]);
        allData[i].input.maxAssets = 200.8e18;
        allData[i].input.borrowerCollateralAssets = 150e18;

        allData[i].output.assets = 100e18;
        allData[i].output.shares = 100000000000000099899;

        return allData;
    }

    function _init(string memory _name) private returns (uint256 i) {
        i = allData.length;
        allData.push();

        allData[i].name = string(abi.encodePacked("#", toString(i), " ", _name));
    }

    function _clone(MWTASData memory _src, MWTASData storage _dst) private {
        _dst.input = Input({
            maxAssets: _src.input.maxAssets,
            borrowerCollateralAssets: _src.input.borrowerCollateralAssets,
            borrowerProtectedAssets: _src.input.borrowerProtectedAssets,
            assetType: _src.input.assetType,
            totalAssets: _src.input.totalAssets,
            assetTypeShareTokenTotalSupply: _src.input.assetTypeShareTokenTotalSupply,
            liquidity: _src.input.liquidity
        });
        _dst.output = Output({assets: _src.output.assets, shares: _src.output.shares});
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
