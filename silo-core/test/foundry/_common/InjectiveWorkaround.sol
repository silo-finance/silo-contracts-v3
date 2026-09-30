// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {IBankModule} from "./IBankModule.sol";
import {ChainsLib} from "silo-foundry-utils/lib/ChainsLib.sol";
import {AddrLib} from "silo-foundry-utils/lib/AddrLib.sol";
import {AddrKey} from "common/addresses/AddrKey.sol";
import {InjectiveTokenAdapter} from "./InjectiveTokenAdapter.sol";
import {IERC20} from "openzeppelin5/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "openzeppelin5/token/ERC20/extensions/IERC20Metadata.sol";

contract InjectiveWorkaround is Test {
    IBankModule public constant BANK_MODULE = IBankModule(address(0x64));
    mapping(address => address) internal _injectiveMetadataAdapters;

    function _customMocksOnInjective() internal {
        if (ChainsLib.getChainId() != ChainsLib.INJECTIVE_CHAIN_ID) return;

        AddrLib.init();

        vm.mockCall(
            0x072fB925014B45dec604A6c44f85DAf837653056, // vault for oracle on Silo#3003
            abi.encodeWithSignature("getExchangeRate()"),
            abi.encode(1.03e18)
        );

        vm.prank(AddrLib.getAddress(AddrKey.WINJ));
        BANK_MODULE.setMetadata("WINJ", "WINJ", 18);
        
        vm.prank(AddrLib.getAddress(AddrKey.YINJ));
        BANK_MODULE.setMetadata("yINJ", "yINJ", 18);
    }

    function _registerInjectiveMetadataHook(address _token) internal {
        if (ChainsLib.getChainId() != ChainsLib.INJECTIVE_CHAIN_ID) return;

        address adapter = _injectiveMetadataAdapters[_token];

        if (adapter == address(0)) {
            adapter = address(new InjectiveTokenAdapter(_token));
            _injectiveMetadataAdapters[_token] = adapter;
        }

        vm.mockFunction(_token, adapter, abi.encodeWithSelector(IERC20.balanceOf.selector));
        vm.mockFunction(_token, adapter, abi.encodeWithSelector(IERC20Metadata.decimals.selector));
        vm.mockFunction(_token, adapter, abi.encodeWithSelector(IERC20Metadata.symbol.selector));
        vm.mockFunction(_token, adapter, abi.encodeWithSelector(IERC20.totalSupply.selector));
    }
}
