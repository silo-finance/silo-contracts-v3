// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {IUniswapV3Pool} from "uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {TokensGenerator} from "./TokensGenerator.sol";

contract UniswapPools is TokensGenerator {
    mapping(string => IUniswapV3Pool) public pools;

    constructor(BlockChain _chain) TokensGenerator(_chain) {
        if (isEthereum(_chain)) {
            pools["USDC_WETH"] = IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
            pools["UKY_WETH"] = IUniswapV3Pool(0xbFa6C8a6BcaBb10574068037142ae7e8a7Fa6228);
            pools["CRV_ETH"] = IUniswapV3Pool(0x4c83A7f819A5c37D64B4c5A2f8238Ea082fA1f4e);
            pools["SP500_WETH"] = IUniswapV3Pool(0x4532aC4F53871697CbFaE2d86517823c1E68B016);
        } else if (isArbitrum(_chain)) {}
    }
}
