// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {VmSafe} from "forge-std/Vm.sol";
import {MessageHashUtils} from "openzeppelin5//utils/cryptography/MessageHashUtils.sol";

import {ICrossReentrancyGuard} from "silo-core/contracts/interfaces/ICrossReentrancyGuard.sol";
import {ShareToken} from "silo-core/contracts/utils/ShareToken.sol";
import {ShareTokenMethodReentrancyTest} from "./_ShareTokenMethodReentrancyTest.sol";

contract PermitReentrancyTest is ShareTokenMethodReentrancyTest {
    bytes32 internal constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    bytes32 internal constant _TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 internal constant _HASHED_VERSION = keccak256(bytes("1"));

    function callMethod() external {
        emit log_string(_tabs(1, "Ensure it will not revert (all share tokens)"));
        _executeForAllShareTokens(_ensureItWillNotRevert);
    }

    function verifyReentrancy() external {
        _executeForAllShareTokens(_ensureItWillRevertReentrancy);
    }

    function _ensureItWillRevertReentrancy(address _token) internal {
        VmSafe.Wallet memory signer = vm.createWallet("Proof signer");
        address spender = makeAddr("Spender");
        uint256 value = 100e18;
        uint256 nonce = ShareToken(_token).nonces(signer.addr);
        uint256 deadline = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = _createPermit(signer, spender, value, nonce, deadline, address(_token));

        vm.expectRevert(ICrossReentrancyGuard.CrossReentrantCall.selector);
        ShareToken(_token).permit(signer.addr, spender, value, deadline, v, r, s);
    }

    function methodDescription() external pure returns (string memory description) {
        description = "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)";
    }

    function _ensureItWillNotRevert(address _token) internal {
        VmSafe.Wallet memory signer = vm.createWallet("Proof signer");
        address spender = makeAddr("Spender");
        uint256 value = 100e18;
        uint256 nonce = ShareToken(_token).nonces(signer.addr);
        uint256 deadline = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) = _createPermit(signer, spender, value, nonce, deadline, address(_token));

        ShareToken(_token).permit(signer.addr, spender, value, deadline, v, r, s);
    }

    function _createPermit(
        VmSafe.Wallet memory _signer,
        address _spender,
        uint256 _value,
        uint256 _nonce,
        uint256 _deadline,
        address _shareToken
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash =
            // forge-lint: disable-next-line(asm-keccak256)
            keccak256(abi.encode(_PERMIT_TYPEHASH, _signer.addr, _spender, _value, _nonce, _deadline));

        bytes32 domainSeparator = ShareToken(_shareToken).DOMAIN_SEPARATOR();
        bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);

        (v, r, s) = vm.sign(_signer.privateKey, digest);
    }
}
