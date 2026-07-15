#!/bin/bash
#
# Legacy Forge-based withdraw revenue runner (one forge script run per factory).
# The current solution is the Python pipeline in silo-core/scripts/withdrawFees/.
# Kept for reference and as a fallback.

source .env

# --- arbitrum_one ---

# arbitrum_one | factory 0x384DC7759d35313F0b567D42bf2f611B285B657C | silos: 75 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0x384DC7759d35313F0b567D42bf2f611B285B657C START_SILO_ID=100 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_ARBITRUM --broadcast

# arbitrum_one | factory 0x8C1b49B1A45d9FD50c5846a6Cd19a5ADaA376B1B | silos: 15 | as of 2026-07-15 (legacy layout)
FOUNDRY_PROFILE=core FACTORY=0x8C1b49B1A45d9FD50c5846a6Cd19a5ADaA376B1B START_SILO_ID=1 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_ARBITRUM --broadcast

# arbitrum_one | factory 0xb562b6CdEEE3ec10E4803B8dcfef81a32074e6B5 | silos: 14 | as of 2026-07-15 (legacy layout)
FOUNDRY_PROFILE=core FACTORY=0xb562b6CdEEE3ec10E4803B8dcfef81a32074e6B5 START_SILO_ID=1 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_ARBITRUM --broadcast

# arbitrum_one | factory 0xCb6CcBd979aa167b81411e672050c01826d715EC | silos: 14 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0xCb6CcBd979aa167b81411e672050c01826d715EC START_SILO_ID=1 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_ARBITRUM --broadcast

# arbitrum_one | factory 0xAFd8F792cb025A76C4916652CfC8e20eee3b6fe2 | silos: 13 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0xAFd8F792cb025A76C4916652CfC8e20eee3b6fe2 START_SILO_ID=3001 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_ARBITRUM --broadcast

# arbitrum_one | factory 0x408822E4E8682413666809b0655161093cd36f2b | silos: 11 | as of 2026-07-15 (legacy layout)
FOUNDRY_PROFILE=core FACTORY=0x408822E4E8682413666809b0655161093cd36f2b START_SILO_ID=1 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_ARBITRUM --broadcast

# arbitrum_one | factory 0x44347A91Cf3E9B30F80e2161438E0f10fCeDA0a0 | silos: 9 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0x44347A91Cf3E9B30F80e2161438E0f10fCeDA0a0 START_SILO_ID=1 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_ARBITRUM --broadcast

# arbitrum_one | factory 0xe376888fD6E5D5Afc12FEa0a8C18f283051c23aD | silos: 7 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0xe376888fD6E5D5Afc12FEa0a8C18f283051c23aD START_SILO_ID=1 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_ARBITRUM --broadcast

# arbitrum_one | factory 0x51824653425e40Cd6253B71AcC8Def602A21427f | silos: 5 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0x51824653425e40Cd6253B71AcC8Def602A21427f START_SILO_ID=1 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_ARBITRUM --broadcast

# arbitrum_one | factory 0x621Eacb756c7fa8bC0EA33059B881055d1693a33 | silos: 5 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0x621Eacb756c7fa8bC0EA33059B881055d1693a33 START_SILO_ID=1 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_ARBITRUM --broadcast

# arbitrum_one | factory 0xf7dc975C96B434D436b9bF45E7a45c95F0521442 | silos: 5 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0xf7dc975C96B434D436b9bF45E7a45c95F0521442 START_SILO_ID=1 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_ARBITRUM --broadcast

# arbitrum_one | factory 0x504B8ca9C664AFe72324388122caBAFb72F9269f | silos: 1 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0x504B8ca9C664AFe72324388122caBAFb72F9269f START_SILO_ID=3000 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_ARBITRUM --broadcast

# arbitrum_one | factory 0xb720078680Dc65B54568673410aBb81195E08122 | silos: 1 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0xb720078680Dc65B54568673410aBb81195E08122 START_SILO_ID=1 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_ARBITRUM --broadcast

# --- avalanche ---

# avalanche | factory 0x92cECB67Ed267FF98026F814D813fDF3054C6Ff9 | silos: 65 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0x92cECB67Ed267FF98026F814D813fDF3054C6Ff9 START_SILO_ID=100 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_AVALANCHE --broadcast

# avalanche | factory 0x9e64f0CD206cce2Da5dE08E7F482D62F57013D0e | silos: 7 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0x9e64f0CD206cce2Da5dE08E7F482D62F57013D0e START_SILO_ID=3001 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_AVALANCHE --broadcast

# --- base ---

# base | factory 0xeB3C9fcE37A355df8f4a01CdaFA75b370607a21f | silos: 0 | as of 2026-07-15 (latest factory, empty)
FOUNDRY_PROFILE=core FACTORY=0xeB3C9fcE37A355df8f4a01CdaFA75b370607a21f START_SILO_ID=3001 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_BASE --broadcast

# --- bnb ---

# bnb | factory 0x977e9b368E5aBEe020B5096A03cE6f78cb3439cf | silos: 1 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0x977e9b368E5aBEe020B5096A03cE6f78cb3439cf START_SILO_ID=3001 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_BNB --broadcast

# --- injective ---

# injective | factory 0x39021662EF7679845E6851E38E01912f556A861f | silos: 3 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0x39021662EF7679845E6851E38E01912f556A861f START_SILO_ID=3001 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_INJECTIVE --broadcast

# injective | factory 0xD2bf5845Ebc4d2b7966dD20Ad59Cb620F355A235 | silos: 3 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0xD2bf5845Ebc4d2b7966dD20Ad59Cb620F355A235 START_SILO_ID=3000 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_INJECTIVE --broadcast

# --- ink ---

# ink | factory 0xD13921239e3832FDC4141FDE544D3D058B529A5D | silos: 8 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0xD13921239e3832FDC4141FDE544D3D058B529A5D START_SILO_ID=100 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_INK --broadcast

# --- mainnet ---

# mainnet | factory 0x22a3cF6149bFa611bAFc89Fd721918EC3Cf7b581 | silos: 89 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0x22a3cF6149bFa611bAFc89Fd721918EC3Cf7b581 START_SILO_ID=100 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_MAINNET --broadcast

# mainnet | factory 0x1DAb4A310447185144467076b116DAC7aec3b48F | silos: 29 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0x1DAb4A310447185144467076b116DAC7aec3b48F START_SILO_ID=3001 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_MAINNET --broadcast

# --- mantle ---

# mantle | factory 0xe5b39b0b2173caA82BaEa368952c6183cA2DA3Ac | silos: 1 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0xe5b39b0b2173caA82BaEa368952c6183cA2DA3Ac START_SILO_ID=3001 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_MANTLE --broadcast

# --- megaeth ---

# megaeth | factory 0x95a7bC57c738C7f64103B93D04f49cbCa566afFD | silos: 3 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0x95a7bC57c738C7f64103B93D04f49cbCa566afFD START_SILO_ID=3001 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_MEGAETH --broadcast

# --- okx ---

# okx | factory 0x650b50E16A703e53A7944CCad513ad21670F0D09 | silos: 0 | as of 2026-07-15 (latest factory, empty)
FOUNDRY_PROFILE=core FACTORY=0x650b50E16A703e53A7944CCad513ad21670F0D09 START_SILO_ID=3001 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_OKX --broadcast

# --- optimism ---

# optimism | factory 0x01c6dc3bD8B175a9494F00b6D224b14EdC67CD34 | silos: 13 | as of 2026-07-15 (legacy layout)
FOUNDRY_PROFILE=core FACTORY=0x01c6dc3bD8B175a9494F00b6D224b14EdC67CD34 START_SILO_ID=1 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_OPTIMISM --broadcast

# optimism | factory 0x17B0FD3eB9CFbdA5B46A0C896e28b3F0c5a7F61d | silos: 13 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0x17B0FD3eB9CFbdA5B46A0C896e28b3F0c5a7F61d START_SILO_ID=1 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_OPTIMISM --broadcast

# optimism | factory 0xb58B331b9cf46c597A34F9e198e8bB9ec5f17ADf | silos: 10 | as of 2026-07-15 (legacy layout)
FOUNDRY_PROFILE=core FACTORY=0xb58B331b9cf46c597A34F9e198e8bB9ec5f17ADf START_SILO_ID=1 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_OPTIMISM --broadcast

# optimism | factory 0x4D43E78E669eD90bb125eF161F530E173f03834b | silos: 5 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0x4D43E78E669eD90bb125eF161F530E173f03834b START_SILO_ID=1 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_OPTIMISM --broadcast

# optimism | factory 0x55a4983949f8a3156Ad483c4003218a7F33D466b | silos: 2 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0x55a4983949f8a3156Ad483c4003218a7F33D466b START_SILO_ID=1 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_OPTIMISM --broadcast

# optimism | factory 0x047801ED4F53Ad3dc28649ab972b3C949f27505c | silos: 1 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0x047801ED4F53Ad3dc28649ab972b3C949f27505c START_SILO_ID=1 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_OPTIMISM --broadcast

# optimism | factory 0xB25255036f210D7E32FC96e25460aB121FF0C25d | silos: 1 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0xB25255036f210D7E32FC96e25460aB121FF0C25d START_SILO_ID=1 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_OPTIMISM --broadcast

# optimism | factory 0xFa773e2c7df79B43dc4BCdAe398c5DCA94236BC5 | silos: 1 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0xFa773e2c7df79B43dc4BCdAe398c5DCA94236BC5 START_SILO_ID=100 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_OPTIMISM --broadcast

# optimism | factory 0x8ab5D81d342f14e594c65a6B33582b57e78E4a9d | silos: 0 | as of 2026-07-15 (latest factory, empty)
FOUNDRY_PROFILE=core FACTORY=0x8ab5D81d342f14e594c65a6B33582b57e78E4a9d START_SILO_ID=3001 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_OPTIMISM --broadcast

# --- sonic ---

# sonic | factory 0x4e9dE3a64c911A37f7EB2fCb06D1e68c3cBe9203 | silos: 65 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0x4e9dE3a64c911A37f7EB2fCb06D1e68c3cBe9203 START_SILO_ID=100 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_SONIC --broadcast

# sonic | factory 0xa42001D6d2237d2c74108FE360403C4b796B7170 | silos: 55 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0xa42001D6d2237d2c74108FE360403C4b796B7170 START_SILO_ID=1 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_SONIC --broadcast

# sonic | factory 0xf81d90DF1B63d48536E78564d24d5DD8F2BE58aD | silos: 2 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0xf81d90DF1B63d48536E78564d24d5DD8F2BE58aD START_SILO_ID=3001 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_SONIC --broadcast

# --- xdc ---

# xdc | factory 0xf81d90DF1B63d48536E78564d24d5DD8F2BE58aD | silos: 9 | as of 2026-07-15
FOUNDRY_PROFILE=core FACTORY=0xf81d90DF1B63d48536E78564d24d5DD8F2BE58aD START_SILO_ID=3001 \
  forge script silo-core/scripts/withdrawFeesForge/WithdrawFees.s.sol \
  --ffi --rpc-url $RPC_XDC --broadcast
