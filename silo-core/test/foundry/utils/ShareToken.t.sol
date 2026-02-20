// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Clones} from "openzeppelin5/proxy/Clones.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";

import {Hook} from "silo-core/contracts/lib/Hook.sol";
import {ShareDebtToken} from "silo-core/contracts/utils/ShareDebtToken.sol";
import {ShareProtectedCollateralToken} from "silo-core/contracts/utils/ShareProtectedCollateralToken.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {IShareTokenInitializable} from "silo-core/contracts/interfaces/IShareTokenInitializable.sol";

import {HookReceiverMock} from "../_mocks/HookReceiverMock.sol";
import {SiloMock} from "../_mocks/SiloMock.sol";
import {MintableToken as Token} from "../_common/MintableToken.sol";
import {SiloConfigMock} from "../_mocks/SiloConfigMock.sol";
import {ERC20UpgradableMock} from "../_mocks/ERC20UpgradableMock.sol";

// solhint-disable func-name-mixedcase
// FOUNDRY_PROFILE=core_test forge test -vv --mc ShareTokenTest
contract ShareTokenTest is Test {
    uint256 internal constant _DEBT_TOKE_BEFORE_ACTION = 0;
    uint256 internal constant _DEBT_TOKE_AFTER_ACTION = Hook.DEBT_TOKEN | Hook.SHARE_TOKEN_TRANSFER;

    ShareDebtToken public sToken;
    SiloMock public silo;
    SiloConfigMock public siloConfig;
    HookReceiverMock public hookReceiverMock;
    address public owner;

    function setUp() public {
        sToken = ShareDebtToken(Clones.clone(address(new ShareDebtToken())));
        silo = new SiloMock(address(0));
        siloConfig = new SiloConfigMock(address(0));
        hookReceiverMock = new HookReceiverMock(address(0));
        owner = makeAddr("Owner");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --mt test_ShareToken_decimals
    function test_ShareToken_decimals() public {
        uint8 decimals = 8;
        Token token = new Token(decimals);

        ISiloConfig.ConfigData memory configData;
        configData.token = address(token);

        silo.configMock(siloConfig.ADDRESS());
        siloConfig.getConfigMock(silo.ADDRESS(), configData);

        sToken.initialize(ISilo(silo.ADDRESS()), address(0), uint24(Hook.DEBT_TOKEN));

        // offset for the debt token is 1
        assertEq(sToken.decimals(), token.decimals(), "expect valid decimals");
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --mt test_notRevertWhenNoHook
    function test_notRevertWhenNoHook() public {
        silo.configMock(siloConfig.ADDRESS());
        sToken.initialize(ISilo(silo.ADDRESS()), address(0), uint24(Hook.DEBT_TOKEN));

        vm.prank(silo.ADDRESS());
        sToken.mint(owner, owner, 1);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --mt test_hookCall
    function test_hookCall() public {
        address siloAddr = silo.ADDRESS();

        silo.configMock(siloConfig.ADDRESS());
        address hookAddr = hookReceiverMock.ADDRESS();

        sToken.initialize(ISilo(siloAddr), hookAddr, uint24(Hook.DEBT_TOKEN));

        vm.prank(siloAddr);
        // forge-lint: disable-next-line(unsafe-typecast)
        sToken.synchronizeHooks(uint24(_DEBT_TOKE_BEFORE_ACTION), uint24(_DEBT_TOKE_AFTER_ACTION));

        uint256 amount = 1;

        _afterTokenTransferMockOnMint(amount);

        vm.prank(siloAddr);
        sToken.mint(owner, owner, amount);
    }

    // FOUNDRY_PROFILE=core_test forge test -vvv --mt test_decreaseAllowance
    function test_decreaseAllowance() public {
        uint256 allowance = 100e18;
        address recipient = makeAddr("Recipient");
        address siloAddr = silo.ADDRESS();

        silo.configMock(siloConfig.ADDRESS());
        siloConfig.reentrancyGuardEnteredMock(false);
        address hookAddr = hookReceiverMock.ADDRESS();
        sToken.initialize(ISilo(siloAddr), hookAddr, uint24(Hook.DEBT_TOKEN));

        vm.prank(recipient);
        sToken.increaseReceiveAllowance(owner, allowance);

        assertEq(sToken.receiveAllowance(owner, recipient), allowance, "expect valid allowance");

        // decrease in value more than allowed
        vm.prank(recipient);
        sToken.decreaseReceiveAllowance(owner, type(uint256).max);

        assertEq(sToken.receiveAllowance(owner, recipient), 0, "expect have no allowance");
    }

    /// FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_CallOnBehalfOfShareToken
    function test_CallOnBehalfOfShareToken() public {
        address upgradableMock = address(new ERC20UpgradableMock());
        address siloAddr = silo.ADDRESS();

        silo.configMock(siloConfig.ADDRESS());
        address hookAddr = hookReceiverMock.ADDRESS();

        IShareTokenInitializable protectedShareToken = IShareTokenInitializable(
            ShareProtectedCollateralToken(Clones.clone(address(new ShareProtectedCollateralToken())))
        );

        protectedShareToken.initialize(ISilo(siloAddr), hookAddr, uint24(Hook.PROTECTED_TOKEN));

        IShareTokenInitializable debtShareToken =
            IShareTokenInitializable(ShareDebtToken(Clones.clone(address(new ShareDebtToken()))));

        debtShareToken.initialize(ISilo(siloAddr), hookAddr, uint24(Hook.DEBT_TOKEN));

        address someUser = makeAddr("SomeUser");

        uint256 amountOfEth = 0;
        bytes memory data = abi.encodeWithSelector(ERC20UpgradableMock.mockUserBalance.selector, someUser);

        vm.expectRevert(ISilo.OnlyHookReceiver.selector);
        protectedShareToken.callOnBehalfOfShareToken(upgradableMock, amountOfEth, ISilo.CallType.Delegatecall, data);

        vm.expectRevert(ISilo.OnlyHookReceiver.selector);
        debtShareToken.callOnBehalfOfShareToken(upgradableMock, amountOfEth, ISilo.CallType.Delegatecall, data);

        assertEq(IERC20(address(protectedShareToken)).balanceOf(someUser), 0);
        assertEq(IERC20(address(debtShareToken)).balanceOf(someUser), 0);

        vm.prank(hookAddr);
        protectedShareToken.callOnBehalfOfShareToken(upgradableMock, amountOfEth, ISilo.CallType.Delegatecall, data);

        assertEq(
            IERC20(address(protectedShareToken)).balanceOf(someUser),
            ERC20UpgradableMock(upgradableMock).USER_BALANCE(),
            "expect valid balance"
        );

        vm.prank(hookAddr);
        debtShareToken.callOnBehalfOfShareToken(upgradableMock, amountOfEth, ISilo.CallType.Delegatecall, data);

        assertEq(
            IERC20(address(debtShareToken)).balanceOf(someUser),
            ERC20UpgradableMock(upgradableMock).USER_BALANCE(),
            "expect valid balance"
        );
    }

    function _afterTokenTransferMockOnMint(uint256 _amount) internal {
        uint256 balance = sToken.balanceOf(owner);

        hookReceiverMock.afterTokenTransferMock( // solhint-disable-line func-named-parameters
            silo.ADDRESS(),
            _DEBT_TOKE_AFTER_ACTION,
            address(0), // zero address for mint
            0, // initial total supply 0
            owner,
            balance + _amount, // owner balance after
            sToken.totalSupply() + _amount, // total supply after mint
            _amount
        );
    }
}
