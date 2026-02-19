// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {TokensGenerator} from "./TokensGenerator.sol";
import {IERC20} from "../interfaces/IERC20.sol";

contract Whales is TokensGenerator {
    // asset => whale
    mapping(IERC20 => address) public whales;

    constructor(BlockChain _chain) TokensGenerator(_chain) {
        if (isEthereum(_chain)) {
            whales[tokens["WETH"]] = address(0x6B44ba0a126a2A1a8aa6cD1AdeeD002e141Bcd44);
            whales[tokens["1INCH"]] = address(0x23360d94C13C1508bDA63BeB5A404b9e2E3f62b5);
            whales[tokens["BAL"]] = address(0xcEacc82ddCdB00BFE19A9D3458db3e6b8aEF542B);
            whales[tokens["cbETH"]] = address(0xBC64BDE4C3b70147C47c16dD9277a6Aaef7e0f02);
            whales[tokens["gOHM"]] = address(0x168fa4917e7cD18f4eD3dc313c4975851cA9E5E7);
            whales[tokens["OHM"]] = address(0xD3D086B36d5502122F275F4Bc18e04c844Bd6E2e);
            whales[tokens["USDC"]] = address(0x1B7BAa734C00298b9429b518D621753Bb0f6efF2);
            whales[tokens["USDT"]] = address(0x68841a1806fF291314946EebD0cdA8b348E73d6D);
            whales[tokens["stETH"]] = address(0x7153D2ef9F14a6b1Bb2Ed822745f65E58d836C3F);
            whales[tokens["wstETH"]] = address(0xa0456eaAE985BDB6381Bd7BAac0796448933f04f);
            whales[tokens["XAI"]] = address(0xC8CD77d4cd9511f2822f24aD14FE9e3C97C57836);
        } else if (isArbitrum(_chain)) {
            whales[tokens["WETH"]] = address(0xC59836FEC63Cfb2E48b0aa00515056436D74Dc03);
        }
    }

    function _doTokens(address _asset, uint256 _amount, address _recipient) internal override {
        address whale = whales[IERC20(_asset)];

        if (whale == address(0)) {
            emit log("no whale - modify storage");
            super._doTokens(_asset, _amount, _recipient);
        } else {
            emit log_named_address("whale", whale);
            vm.prank(whale);
            // forge-lint: disable-next-line(erc20-unchecked-transfer)
            IERC20(_asset).transfer(_recipient, _amount);
        }
    }
}
