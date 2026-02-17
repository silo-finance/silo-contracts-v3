#!/bin/bash

source .env

FOUNDRY_PROFILE=core FACTORY=0x384DC7759d35313F0b567D42bf2f611B285B657C\
  forge script silo-core/scripts/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_ARBITRUM --broadcast

FOUNDRY_PROFILE=core FACTORY=0x621Eacb756c7fa8bC0EA33059B881055d1693a33\
  forge script silo-core/scripts/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_ARBITRUM --broadcast

FOUNDRY_PROFILE=core FACTORY=0x44347A91Cf3E9B30F80e2161438E0f10fCeDA0a0\
  forge script silo-core/scripts/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_ARBITRUM --broadcast

  
FOUNDRY_PROFILE=core FACTORY=0x92cECB67Ed267FF98026F814D813fDF3054C6Ff9 \
    forge script silo-core/scripts/WithdrawFees.s.sol \
    --ffi --rpc-url $RPC_AVALANCHE --broadcast

FOUNDRY_PROFILE=core FACTORY=0x22a3cF6149bFa611bAFc89Fd721918EC3Cf7b581\
    forge script silo-core/scripts/WithdrawFees.s.sol \
    --ffi --rpc-url $RPC_MAINNET --broadcast

FOUNDRY_PROFILE=core FACTORY=0xFa773e2c7df79B43dc4BCdAe398c5DCA94236BC5\
    forge script silo-core/scripts/WithdrawFees.s.sol \
    --ffi --rpc-url $RPC_OPTIMISM --broadcast

# sonic 

FOUNDRY_PROFILE=core FACTORY=0x4e9dE3a64c911A37f7EB2fCb06D1e68c3cBe9203\
    forge script silo-core/scripts/WithdrawFees.s.sol \
    --ffi --rpc-url $RPC_SONIC --broadcast


FOUNDRY_PROFILE=core FACTORY=0xa42001D6d2237d2c74108FE360403C4b796B7170\
    forge script silo-core/scripts/WithdrawFees.s.sol \
    --ffi --rpc-url $RPC_SONIC --broadcast