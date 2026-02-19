// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {MessageHashUtils} from "openzeppelin5/utils/cryptography/MessageHashUtils.sol";
import {ERC20PermitUpgradeable} from "openzeppelin5-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

import {IShareToken} from "silo-core/contracts/interfaces/IShareToken.sol";
import {IHookReceiver} from "silo-core/contracts/interfaces/IHookReceiver.sol";
import {ISilo} from "silo-core/contracts/interfaces/ISilo.sol";
import {ISiloConfig} from "silo-core/contracts/interfaces/ISiloConfig.sol";
import {SiloLittleHelper} from "silo-core/test/foundry/_common/SiloLittleHelper.sol";

// solhint-disable ordering

/*
FOUNDRY_PROFILE=core_test forge test -vv --ffi --mc ShareTokenCommonTest
*/
contract ShareTokenCommonTest is SiloLittleHelper, Test, ERC20PermitUpgradeable {
    address public user = makeAddr("someUser");
    address public otherUser = makeAddr("someOtherUser");
    uint256 public mintAmount = 100e18;

    string private constant _NAME = "SiloShareTokenEIP712Name";
    string private constant _VERSION = "1";
    bytes32 private constant _TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant TRANSFER_EVENT = keccak256(bytes("Transfer(address,address,uint256)"));
    bytes32 internal constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 internal constant _HASHED_NAME = keccak256(bytes(_NAME));
    bytes32 internal constant _HASHED_VERSION = keccak256(bytes(_VERSION));

    ISiloConfig public siloConfig;
    address public hookReceiver;

    function setUp() public {
        siloConfig = _setUpLocalFixture();
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_approveAndAllowance
    */
    function test_approveAndAllowance() public {
        _executeForAllShareTokens(_approveAndAllowance);
    }

    function _approveAndAllowance(IShareToken _shareToken) internal {
        uint256 allowance = _shareToken.allowance(user, otherUser);
        assertEq(allowance, 0, "allowance should be 0");

        uint256 approveAmount = 100e18;

        vm.prank(user);
        _shareToken.approve(otherUser, approveAmount);

        allowance = _shareToken.allowance(user, otherUser);
        assertEq(allowance, approveAmount, "allowance should be equal to approveAmount");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_balanceOfAndTotalSupply
    */
    function test_balanceOfAndTotalSupply() public {
        _executeForAllShareTokens(_balanceOfAndTotalSupply);
    }

    function _balanceOfAndTotalSupply(IShareToken _shareToken) internal {
        ISilo silo = _shareToken.silo();

        vm.prank(address(silo));
        _shareToken.mint(user, user, mintAmount);

        uint256 balance0 = _shareToken.balanceOf(user);
        uint256 totalSupply0 = _shareToken.totalSupply();

        assertEq(balance0, mintAmount, "balance should be equal to mintAmount");
        assertEq(totalSupply0, mintAmount, "totalSupply should be equal to mintAmount");

        (uint256 balance1, uint256 totalSupply1) = _shareToken.balanceOfAndTotalSupply(user);

        assertEq(balance0, balance1, "balances mismatch");
        assertEq(totalSupply0, totalSupply1, "totalSupply mismatch");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_shareTokenMintPermissions
    */
    function test_shareTokenMintPermissions() public {
        _executeForAllShareTokens(_shareTokenMintPermissions);
    }

    function _shareTokenMintPermissions(IShareToken _shareToken) internal {
        vm.expectRevert(IShareToken.OnlySilo.selector);
        _shareToken.mint(user, user, mintAmount);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_shareTokenMint
    */
    function test_shareTokenMint() public {
        _executeForAllShareTokens(_shareTokenMint);
    }

    function _shareTokenMint(IShareToken _shareToken) internal {
        ISilo silo = _shareToken.silo();

        vm.expectEmit(true, true, true, true, address(_shareToken));
        emit Transfer(address(0), user, mintAmount);

        vm.prank(address(silo));
        _shareToken.mint(user, user, mintAmount);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_burnPermissions
    */
    function test_burnPermissions() public {
        _executeForAllShareTokens(_burnPermissions);
    }

    function _burnPermissions(IShareToken _shareToken) internal {
        vm.expectRevert(IShareToken.OnlySilo.selector);
        _shareToken.burn(user, otherUser, 100e18);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_shareTokenBurn
    */
    function test_shareTokenBurn() public {
        _executeForAllShareTokens(_shareTokenBurn);
    }

    function _shareTokenBurn(IShareToken _shareToken) internal {
        ISilo silo = _shareToken.silo();

        vm.expectEmit(true, true, true, true, address(_shareToken));
        emit Transfer(address(0), user, mintAmount);

        vm.prank(address(silo));
        _shareToken.mint(user, user, mintAmount);

        vm.expectEmit(true, true, true, true, address(_shareToken));
        emit Transfer(user, address(0), mintAmount);

        vm.prank(address(silo));
        _shareToken.burn(user, user, mintAmount);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_shareTokenBurnAllowance
    */
    function test_shareTokenBurnAllowance() public {
        _executeForAllCollateralShareTokens(_shareTokenBurnAllowance);
    }

    function _shareTokenBurnAllowance(IShareToken _shareToken) internal {
        ISilo silo = _shareToken.silo();

        vm.prank(address(silo));
        _shareToken.mint(user, user, mintAmount);

        vm.prank(user);
        _shareToken.approve(otherUser, mintAmount);

        vm.expectEmit(true, true, true, false);
        emit Transfer(user, address(0), mintAmount);

        vm.prank(address(silo));
        _shareToken.burn(user, otherUser, mintAmount);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_domainSeparator
    */
    function test_domainSeparator() public {
        _executeForAllShareTokens(_domainSeparator);
    }

    function _domainSeparator(IShareToken _shareToken) internal view {
        bytes32 expectedDomainSeparator = keccak256(
            abi.encode(
                // forge-lint: disable-next-line(asm-keccak256)
                _TYPE_HASH, keccak256(bytes(_NAME)), keccak256(bytes(_VERSION)), block.chainid, address(_shareToken)
            )
        );

        bytes32 domainSeparator = ERC20PermitUpgradeable(address(_shareToken)).DOMAIN_SEPARATOR();

        assertEq(domainSeparator, expectedDomainSeparator, "unexpected domainSeparator");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_eip712Domain
    */
    function test_eip712Domain() public {
        _executeForAllShareTokens(_eip712Domain);
    }

    function _eip712Domain(IShareToken _shareToken) internal view {
        string memory name;
        string memory version;
        address verifyingContract;

        (, name, version,, verifyingContract,,) = ERC20PermitUpgradeable(address(_shareToken)).eip712Domain();

        assertEq(keccak256(bytes(name)), keccak256(bytes(_NAME)), "name should be equal to _NAME");
        assertEq(keccak256(bytes(version)), keccak256(bytes(_VERSION)), "version should be equal to _VERSION");
        assertEq(verifyingContract, address(_shareToken), "verifyingContract should be equal to _shareToken");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_hookReceiver
    */
    function test_hookReceiver() public {
        _executeForAllShareTokens(_hookReceiver);
    }

    function _hookReceiver(IShareToken _shareToken) internal view {
        address shareTokenHookReceiver = _shareToken.hookReceiver();
        assertEq(shareTokenHookReceiver, address(partialLiquidation), "wrong hookReceiver");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_synchronizeHooksPermissions
    */
    function test_synchronizeHooksPermissions() public {
        _executeForAllShareTokens(_synchronizeHooksPermissions);
    }

    function _synchronizeHooksPermissions(IShareToken _shareToken) internal {
        vm.expectRevert(IShareToken.OnlySilo.selector);
        _shareToken.synchronizeHooks(0, 0);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_hookReceiver
    */
    function test_hookSetupAndSynchronizeHooks() public {
        _executeForAllShareTokens(_hookSetupAndSynchronizeHooks);
    }

    function _hookSetupAndSynchronizeHooks(IShareToken _shareToken) internal {
        ISilo silo = _shareToken.silo();

        IShareToken.HookSetup memory setup = _shareToken.hookSetup();

        uint24 hooksBefore;
        uint24 hooksAfter;

        (hooksBefore, hooksAfter) = IHookReceiver(address(partialLiquidation)).hookReceiverConfig(address(silo));

        assertEq(setup.hooksBefore, hooksBefore, "Should be equal to hooksBefore");
        assertEq(setup.hooksAfter, hooksAfter, "Should be equal to hooksAfter");

        uint24 newBeforeConfig = 55;
        uint24 newAfterConfig = 66;

        vm.prank(address(silo));
        _shareToken.synchronizeHooks(newBeforeConfig, newAfterConfig);

        setup = _shareToken.hookSetup();

        assertEq(setup.hooksBefore, newBeforeConfig, "Should be equal to newBeforeConfig");
        assertEq(setup.hooksAfter, newAfterConfig, "Should be equal to newAfterConfig");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_shareTokenSilo
    */
    function test_shareTokenSilo() public view {
        (address protected0, address collateral0, address debt0) = siloConfig.getShareTokens(address(silo0));

        assertEq(address(IShareToken(protected0).silo()), address(silo0), "Should be equal to silo0");
        assertEq(address(IShareToken(collateral0).silo()), address(silo0), "Should be equal to silo0");
        assertEq(address(IShareToken(debt0).silo()), address(silo0), "Should be equal to silo0");

        (address protected1, address collateral1, address debt1) = siloConfig.getShareTokens(address(silo1));

        assertEq(address(IShareToken(protected1).silo()), address(silo1), "Should be equal to silo1");
        assertEq(address(IShareToken(collateral1).silo()), address(silo1), "Should be equal to silo1");
        assertEq(address(IShareToken(debt1).silo()), address(silo1), "Should be equal to silo1");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_shareTokenSiloConfig
    */
    function test_shareTokenSiloConfig() public {
        _executeForAllShareTokens(_shareTokenSiloConfig);
    }

    function _shareTokenSiloConfig(IShareToken _shareToken) internal view {
        ISiloConfig shareTokenSiloConfig = _shareToken.siloConfig();
        assertEq(address(shareTokenSiloConfig), address(siloConfig), "Should be equal to siloConfig");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_collateralShareTokenDecimals
    */
    function test_collateralShareTokenDecimals() public view {
        (address protected0, address collateral0,) = siloConfig.getShareTokens(address(silo0));
        (address protected1, address collateral1,) = siloConfig.getShareTokens(address(silo1));

        _collateralShareTokenDecimals(IShareToken(collateral0), address(token0));
        _collateralShareTokenDecimals(IShareToken(protected0), address(token0));

        _collateralShareTokenDecimals(IShareToken(collateral1), address(token1));
        _collateralShareTokenDecimals(IShareToken(protected1), address(token1));
    }

    function _collateralShareTokenDecimals(IShareToken _collateralToken, address _siloAsset) internal view {
        uint256 assetDecimals = IShareToken(_siloAsset).decimals();
        uint256 collateralDecimals = _collateralToken.decimals();

        assertEq(collateralDecimals - assetDecimals, 0, "not using offset for share decimals() method");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_shareTokenName
    */
    function test_shareTokenName() public view {
        uint256 siloId = siloConfig.SILO_ID();
        string memory siloIdString = string.concat("SiloId: ", vm.toString(siloId));
        (address protected0, address collateral0, address debt0) = siloConfig.getShareTokens(address(silo0));

        assertEq(IShareToken(protected0).name(), string.concat("Silo Finance Non-borrowable b Deposit, ", siloIdString));
        assertEq(IShareToken(collateral0).name(), string.concat("Silo Finance Borrowable b Deposit, ", siloIdString));
        assertEq(IShareToken(debt0).name(), string.concat("Silo Finance b Debt, ", siloIdString));

        (address protected1, address collateral1, address debt1) = siloConfig.getShareTokens(address(silo1));

        assertEq(IShareToken(protected1).name(), string.concat("Silo Finance Non-borrowable b Deposit, ", siloIdString));
        assertEq(IShareToken(collateral1).name(), string.concat("Silo Finance Borrowable b Deposit, ", siloIdString));
        assertEq(IShareToken(debt1).name(), string.concat("Silo Finance b Debt, ", siloIdString));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_shareTokenSymbol
    */
    function test_shareTokenSymbol() public view {
        uint256 siloId = siloConfig.SILO_ID();
        (address protected0, address collateral0, address debt0) = siloConfig.getShareTokens(address(silo0));

        assertEq(IShareToken(protected0).symbol(), string.concat("nbb-", vm.toString(siloId)));
        assertEq(IShareToken(collateral0).symbol(), string.concat("bb-", vm.toString(siloId)));
        assertEq(IShareToken(debt0).symbol(), string.concat("db-", vm.toString(siloId)));

        (address protected1, address collateral1, address debt1) = siloConfig.getShareTokens(address(silo1));

        assertEq(IShareToken(protected1).symbol(), string.concat("nbb-", vm.toString(siloId)));
        assertEq(IShareToken(collateral1).symbol(), string.concat("bb-", vm.toString(siloId)));
        assertEq(IShareToken(debt1).symbol(), string.concat("db-", vm.toString(siloId)));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_shareTokenPermitAndNonces
    */
    function test_shareTokenPermitAndNonces() public {
        _executeForAllShareTokens(_shareTokenPermitAndNonces);
    }

    function _shareTokenPermitAndNonces(IShareToken _shareToken) public {
        Vm.Wallet memory wallet = vm.createWallet("Signer");
        address spender = makeAddr("Spender");
        uint256 value = 100e18;
        uint256 nonce = ERC20PermitUpgradeable(address(_shareToken)).nonces(wallet.addr);
        uint256 deadline = block.timestamp + 1000;

        assertEq(nonce, 0, "expect nonce to be 0");

        (uint8 v, bytes32 r, bytes32 s) =
            _createPermit(wallet.addr, wallet.privateKey, spender, value, nonce, deadline, address(_shareToken));

        uint256 allowanceBefore = _shareToken.allowance(wallet.addr, spender);
        assertEq(allowanceBefore, 0, "expect no allowance");

        ERC20PermitUpgradeable(address(_shareToken)).permit(wallet.addr, spender, value, deadline, v, r, s);

        uint256 allowanceAfter = _shareToken.allowance(wallet.addr, spender);
        assertEq(allowanceAfter, value, "expect valid allowance");

        nonce = ERC20PermitUpgradeable(address(_shareToken)).nonces(wallet.addr);
        assertEq(nonce, 1, "expect nonce to be 1");
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_forwardTransferFromNoChecksPermissions
    */
    function test_forwardTransferFromNoChecksPermissions() public {
        _executeForAllShareTokens(_forwardTransferFromNoChecksPermissions);
    }

    function _forwardTransferFromNoChecksPermissions(IShareToken _shareToken) internal {
        vm.expectRevert(ISilo.OnlyHookReceiver.selector);
        _shareToken.forwardTransferFromNoChecks(address(0), address(0), 0);
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_forwardTransferFromNoChecks_silo0
    */
    function test_forwardTransferFromNoChecks_silo0() public {
        _executeForAllShareTokens(_forwardTransferFromNoChecks, address(silo0));
    }

    /*
    FOUNDRY_PROFILE=core_test forge test -vvv --ffi --mt test_forwardTransferFromNoChecks_silo1
    */
    function test_forwardTransferFromNoChecks_silo1() public {
        _executeForAllShareTokens(_forwardTransferFromNoChecks, address(silo1));
    }

    function _forwardTransferFromNoChecks(IShareToken _shareToken) internal {
        uint24 tokenType = _shareToken.hookSetup().tokenType;
        emit log_named_uint("[forwardTransferFromNoChecks] tokenType", tokenType);

        ISilo silo = _shareToken.silo();

        vm.prank(address(silo));
        _shareToken.mint(user, user, mintAmount);

        uint256 balance = _shareToken.balanceOf(user);
        assertEq(balance, mintAmount, "expect valid balance for a user");

        vm.prank(address(_shareToken.hookSetup().hookReceiver));
        _shareToken.forwardTransferFromNoChecks(user, otherUser, mintAmount);

        balance = _shareToken.balanceOf(otherUser);
        assertEq(balance, mintAmount, "expect valid balance for otherUser");

        balance = _shareToken.balanceOf(user);
        assertEq(balance, 0, "expect 0 balance for user");
    }

    function _executeForAllShareTokens(function(IShareToken) internal func) internal {
        _executeForAllShareTokens(func, address(silo0));
        _executeForAllShareTokens(func, address(silo1));
    }

    function _executeForAllShareTokens(function(IShareToken) internal func, address _silo) internal {
        (address protected0, address collateral0, address debt0) = siloConfig.getShareTokens(_silo);

        func(IShareToken(protected0));
        func(IShareToken(collateral0));
        func(IShareToken(debt0));
    }

    function _executeForAllCollateralShareTokens(function(IShareToken) internal func) internal {
        (address protected0, address collateral0,) = siloConfig.getShareTokens(address(silo0));
        (address protected1, address collateral1,) = siloConfig.getShareTokens(address(silo1));

        func(IShareToken(protected0));
        func(IShareToken(collateral0));

        func(IShareToken(protected1));
        func(IShareToken(collateral1));
    }

    function _createPermit(
        address _signer,
        uint256 _signerPrivateKey,
        address _spender,
        uint256 _value,
        uint256 _nonce,
        uint256 _deadline,
        address _shareToken
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        // forge-lint: disable-next-line(asm-keccak256)
        bytes32 structHash = keccak256(abi.encode(_PERMIT_TYPEHASH, _signer, _spender, _value, _nonce, _deadline));

        bytes32 domainSeparator = ERC20PermitUpgradeable(_shareToken).DOMAIN_SEPARATOR();
        bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);

        (v, r, s) = vm.sign(_signerPrivateKey, digest);
    }
}
