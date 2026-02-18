// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {VmSafe} from "forge-std/Vm.sol";
import {IERC20Permit} from "openzeppelin5/token/ERC20/extensions/IERC20Permit.sol";
import {MessageHashUtils} from "openzeppelin5//utils/cryptography/MessageHashUtils.sol";

import {MethodReentrancyTest} from "silo-core/test/foundry/Silo/reentrancy/methods/MethodReentrancyTest.sol";
import {TestStateLib} from "silo-vaults/test/foundry/call-and-reenter/TestState.sol";

contract PermitReentrancyTest is MethodReentrancyTest {
    bytes32 constant internal _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    bytes32 constant internal _TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 constant internal _HASHED_VERSION = keccak256(bytes("1"));

    function callMethod() external {
        emit log_string("\tEnsure it will not revert");
        _ensureItWillNotRevert();
    }

    function verifyReentrancy() external {
        _ensureItWillNotRevert();
    }

    function methodDescription() external pure returns (string memory description) {
        description = "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)";
    }

    function _ensureItWillNotRevert() internal {
        IERC20Permit vault = IERC20Permit(address(TestStateLib.vault()));

        VmSafe.Wallet memory signer = vm.createWallet("Proof signer");
        address spender = makeAddr("Spender");
        uint256 value = 100e18;
        uint256 nonce = vault.nonces(signer.addr);
        uint256 deadline = block.timestamp + 1000;

        (uint8 v, bytes32 r, bytes32 s) =
            _createPermit(signer, spender, value, nonce, deadline, vault);

        vault.permit(signer.addr, spender, value, deadline, v, r, s);
    }

    function _createPermit(
        VmSafe.Wallet memory _signer,
        address _spender,
        uint256 _value,
        uint256 _nonce,
        uint256 _deadline,
        IERC20Permit _vault
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash =
            keccak256(abi.encode(_PERMIT_TYPEHASH, _signer.addr, _spender, _value, _nonce, _deadline));

        bytes32 domainSeparator = _vault.DOMAIN_SEPARATOR();
        bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);

        (v, r, s) = vm.sign(_signer.privateKey, digest);
    }
}
