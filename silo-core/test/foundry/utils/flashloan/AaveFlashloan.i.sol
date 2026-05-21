// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {console2} from "forge-std/console2.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";
import {IPool} from "aave-v3-origin/interfaces/IPool.sol";

import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {AddrKey} from "common/addresses/AddrKey.sol";

import {IERC3156FlashLender} from "silo-core/contracts/interfaces/IERC3156FlashLender.sol";
import {AaveFlashloanDeploy} from "silo-core/deploy/AaveFlashloanDeploy.s.sol";
import {AaveFlashloan} from "silo-core/contracts/utils/flashloan/AaveFlashloan.sol";
import {IERC3156FlashBorrower} from "silo-core/contracts/interfaces/IERC3156FlashBorrower.sol";

bytes32 constant FLASHLOAN_CALLBACK = keccak256("ERC3156FlashBorrower.onFlashLoan");

contract FlashLoanReceiverMock is IERC3156FlashBorrower {
    uint256 public callbackCount;
    address public lastInitiator;
    address public lastToken;
    uint256 public lastInputAmount;
    uint256 public lastBalanceOf;
    uint256 public lastFee;

    function onFlashLoan(address _initiator, address _token, uint256 _amount, uint256 _fee, bytes calldata)
        external
        returns (bytes32)
    {
        console2.log("[onFlashLoan]", _token, _amount, _fee);
        console2.log("[onFlashLoan] balance of", IERC20(_token).balanceOf(address(this)));

        callbackCount++;
        lastInitiator = _initiator;
        lastToken = _token;
        lastInputAmount = _amount;
        lastBalanceOf = IERC20(_token).balanceOf(address(this));
        lastFee = _fee;

        IERC20(_token).approve({spender: msg.sender, value: _amount + _fee});
        return FLASHLOAN_CALLBACK;
    }
}

/*
    FOUNDRY_PROFILE=core_test forge test --ffi -vv --mc AaveFlashloanTest
*/
contract AaveFlashloanTest is Test {
    IERC3156FlashLender aaveFlashloan;
    IPool pool;
    FlashLoanReceiverMock receiver;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_SONIC"), 71073457);

        AaveFlashloanDeploy aaveFlashloanDeploy = new AaveFlashloanDeploy();
        aaveFlashloanDeploy.disableDeploymentsSync();
        aaveFlashloan = aaveFlashloanDeploy.run();

        pool = AaveFlashloan(address(aaveFlashloan)).POOL();
        receiver = new FlashLoanReceiverMock();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_aave_maxFlashLoan
    */
    function test_aave_maxFlashLoan() public {
        uint256 maxLoan = aaveFlashloan.maxFlashLoan(AddrLib.getAddress(AddrKey.USDC_E));
        assertEq(maxLoan, 1_356_675.402753e6, "[usdc] max flashloan");

        maxLoan = aaveFlashloan.maxFlashLoan(AddrLib.getAddress(AddrKey.wS));
        assertEq(maxLoan, 94_773_670.936519159805995873e18, "[ws] max flashloan");

        maxLoan = aaveFlashloan.maxFlashLoan(address(0));
        assertEq(maxLoan, 0, "[address(0)] max flashloan 0 for empty address");

        maxLoan = aaveFlashloan.maxFlashLoan(address(1));
        assertEq(maxLoan, 0, "[address(1)] max flashloan 0 for not supported token address");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_aave_flashFee
    */
    function test_aave_flashFee() public {
        address asset = AddrLib.getAddress(AddrKey.USDC_E);
        uint256 amount = aaveFlashloan.maxFlashLoan(asset);

        uint256 fee = aaveFlashloan.flashFee(asset, amount);
        uint256 expected = uint256(pool.FLASHLOAN_PREMIUM_TOTAL()) * amount / 10_000 + 1; // rounding up

        assertEq(fee, expected, "flashFee should match Aave premium");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_aave_flashLoan_usdc
    */
    function test_aave_flashLoan_usdc() public {
        _aaveFlashLoan(AddrLib.getAddress(AddrKey.USDC_E));
    }

    function test_aave_flashLoan_ws() public {
        _aaveFlashLoan(AddrLib.getAddress(AddrKey.wS));
    }

    function _aaveFlashLoan(address _asset) internal {
        console2.log("[_flashLoan] for asset", _asset, IERC20Metadata(_asset).symbol());

        uint256 amount = aaveFlashloan.maxFlashLoan(_asset);
        uint256 fee = aaveFlashloan.flashFee(_asset, amount);
        deal(_asset, address(receiver), fee);

        bool success = aaveFlashloan.flashLoan({
            _receiver: IERC3156FlashBorrower(address(receiver)), _token: _asset, _amount: amount, _data: ""
        });

        assertTrue(success, "flashLoan should return true");
        assertEq(receiver.callbackCount(), 1, "onFlashLoan should be called once");
        assertEq(receiver.lastInitiator(), address(this), "receiver should get test as initiator");
        assertEq(receiver.lastToken(), _asset, "receiver should get market asset");
        assertEq(receiver.lastInputAmount(), amount, "receiver should get borrowed amount");
        assertEq(receiver.lastBalanceOf(), amount + fee, "balance of should be full amount + fee");
        assertEq(receiver.lastFee(), fee, "receiver should get computed fee");
    }
}
