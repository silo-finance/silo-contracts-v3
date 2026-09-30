// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {TokenWithReentrancy} from "silo-core/test/foundry/_mocks/SiloLendingLib/TokenWithReentrancy.sol";

import {SiloLendingLibConsumerVulnerable} from
    "silo-core/test/foundry/_mocks/SiloLendingLib/SiloLendingLibConsumerVulnerable.sol";

import {SiloLendingLibConsumerNonVulnerable} from
    "silo-core/test/foundry/_mocks/SiloLendingLib/SiloLendingLibConsumerNonVulnerable.sol";

// FOUNDRY_PROFILE=core_test forge test -vv --mc ReentrancyOnRepayTest --ffi
contract ReentrancyOnRepayTest is Test {
    SiloLendingLibConsumerVulnerable internal _vulnerable;
    SiloLendingLibConsumerNonVulnerable internal _nonVulnerable;

    address internal _token;
    address internal _borrower = makeAddr("_borrower");
    address internal _repayer = makeAddr("_repayer");
    IShareToken internal _debtShareToken = IShareToken(makeAddr("_debtShareToken"));

    uint256 internal constant _ASSETS = 100;
    uint256 internal constant _SHARES = 50;

    event SiloAssetState(uint256 assets);

    function setUp() public {
        _vulnerable = new SiloLendingLibConsumerVulnerable();
        _nonVulnerable = new SiloLendingLibConsumerNonVulnerable();
        _token = address(new TokenWithReentrancy());

        _mockCalls();
    }

    // solhint-disable-next-line func-name-mixedcase
    function test_SiloLendingLib_vulnerable() public {
        uint256 totalDebt = _vulnerable.getTotalDebt();

        // This event is emitted from the reentrancy call.
        // And is triggered by this call:
        // IERC20(_configData.token).safeTransferFrom(_repayer, address(this), assets);
        //
        // As we are testing the vulnerable version of the library,
        // we expect to have the same state as we had before the reentrancy call.
        uint256 expectedDebt = totalDebt;

        vm.expectEmit(false, false, false, true);
        emit TokenWithReentrancy.SiloAssetState(expectedDebt);

        _vulnerable.repay(_getConfigData(), 0, /* assets */ _SHARES, _borrower, _repayer);
    }

    // solhint-disable-next-line func-name-mixedcase
    /*
    FOUNDRY_PROFILE=core_test forge test -vv --mt test_SiloLendingLib_non_vulnerable --ffi
    */
    function test_SiloLendingLib_non_vulnerable() public {
        uint256 totalDebtBefore = _nonVulnerable.getTotalDebt();

        // This event is emitted from the reentrancy call.
        // And is triggered by this call:
        // IERC20(_configData.token).safeTransferFrom(_repayer, address(this), assets);
        //
        // As we are testing the non-vulnerable version of the library,
        // we expect to have an updated state during the reentrancy call.
        uint256 expectedDebt = totalDebtBefore - _ASSETS;

        vm.expectEmit(false, false, false, true);
        emit TokenWithReentrancy.SiloAssetState(expectedDebt);

        _nonVulnerable.repay(_getConfigData(), _ASSETS, 0, /* shares */ _borrower, _repayer);
    }

    // config data fn
    function _getConfigData() internal view returns (ISiloConfig.ConfigData memory config) {
        config.token = _token;
        config.debtShareToken = address(_debtShareToken);
    }

    function _mockCalls() internal {
        vm.mockCall(address(_debtShareToken), abi.encodePacked(IERC20.totalSupply.selector), abi.encode(1000));

        vm.mockCall(
            address(_debtShareToken),
            abi.encodePacked(IShareToken.balanceOfAndTotalSupply.selector),
            abi.encode(991, 1000)
        );

        vm.mockCall(
            address(_debtShareToken), abi.encodeCall(IShareToken.burn, (_borrower, _repayer, 991)), abi.encode(true)
        );
    }
}
