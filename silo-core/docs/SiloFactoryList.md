# How to discover pools in Silo

This document explains how to discover Silo pools (silos) programmatically, and
lists every `SiloFactory` per chain that has created at least one silo.

## Concepts

- A Silo **market** is a pair of assets. Every market is made of **two pools**,
  `silo0` and `silo1` - one pool per asset.
- Each pool is an **ERC-4626 compliant vault**, so standard vault methods
  (`asset()`, `totalAssets()`, `convertToAssets()`, ...) work on it.
- The **`SiloFactory` is permissionless**: anyone can deploy a silo with any
  configuration. This means test or junk silos can exist on-chain, so discovered
  silos always need to be validated/filtered before use.
- Multiple factories exist over the protocol's lifecycle: new versions ship new
  `SiloFactory` contracts, so a single chain can have **several factories**.
  New markets **should** be deployed using the **newest** `SiloFactory` available -
  its address is always published in this repository. However, **previous versions
  stay active**, so it is not impossible for someone to deploy a market through an
  older factory.
- Because of that, we **recommend monitoring all factories** on a chain, not just
  the newest one, whenever that is feasible. This is a recommendation, not a hard
  requirement: in practice the newest version is the one that will be used, and it
  is always available in the repository - so monitoring only the latest factory is
  usually enough, at the cost of potentially missing markets created via an older
  version.

## Discovering silos via events

The easiest way to discover silos is to scan/subscribe to the `SiloFactory` events.
Every silo creation emits `NewSilo` (see
[ISiloFactory.sol](../contracts/interfaces/ISiloFactory.sol)):

```solidity
event NewSilo(
    address indexed implementation,
    address indexed token0,
    address indexed token1,
    address silo0,
    address silo1,
    address siloConfig
);
```

A single `NewSilo` event already gives you everything needed to describe a market:

- `token0` / `token1` - the two underlying assets,
- `silo0` / `silo1` - the two pools (ERC-4626 vaults),
- `siloConfig` - the market's `SiloConfig`.

So iterating `NewSilo` logs across all factories on a chain yields the full set of
markets and pools.

## SiloFactory addresses per chain

The **newest (current) `SiloFactory`** address for every chain is stored in this
repository, on the **`master`** branch, at:

```
silo-core/deployments/<chain>/SiloFactory.sol.json
```

(the `address` field), for example `silo-core/deployments/mainnet/SiloFactory.sol.json`.
Always read it from the **`master`** branch to get the up-to-date address.

The list below enumerates the known `SiloFactory` contracts per chain, newest first.

### Ethereum (chainId: 1)

- [0x1DAb4A310447185144467076b116DAC7aec3b48F](https://etherscan.io/address/0x1DAb4A310447185144467076b116DAC7aec3b48F)
- [0x22a3cF6149bFa611bAFc89Fd721918EC3Cf7b581](https://etherscan.io/address/0x22a3cF6149bFa611bAFc89Fd721918EC3Cf7b581)

### Arbitrum (chainId: 42161)

- [0xAFd8F792cb025A76C4916652CfC8e20eee3b6fe2](https://arbiscan.io/address/0xAFd8F792cb025A76C4916652CfC8e20eee3b6fe2)
- [0x504B8ca9C664AFe72324388122caBAFb72F9269f](https://arbiscan.io/address/0x504B8ca9C664AFe72324388122caBAFb72F9269f)
- [0x384DC7759d35313F0b567D42bf2f611B285B657C](https://arbiscan.io/address/0x384DC7759d35313F0b567D42bf2f611B285B657C)
- [0xf7dc975C96B434D436b9bF45E7a45c95F0521442](https://arbiscan.io/address/0xf7dc975C96B434D436b9bF45E7a45c95F0521442)
- [0x621Eacb756c7fa8bC0EA33059B881055d1693a33](https://arbiscan.io/address/0x621Eacb756c7fa8bC0EA33059B881055d1693a33)
- [0xb720078680Dc65B54568673410aBb81195E08122](https://arbiscan.io/address/0xb720078680Dc65B54568673410aBb81195E08122)
- [0x44347A91Cf3E9B30F80e2161438E0f10fCeDA0a0](https://arbiscan.io/address/0x44347A91Cf3E9B30F80e2161438E0f10fCeDA0a0)
- [0x51824653425e40Cd6253B71AcC8Def602A21427f](https://arbiscan.io/address/0x51824653425e40Cd6253B71AcC8Def602A21427f)
- [0xe376888fD6E5D5Afc12FEa0a8C18f283051c23aD](https://arbiscan.io/address/0xe376888fD6E5D5Afc12FEa0a8C18f283051c23aD)
- [0xCb6CcBd979aa167b81411e672050c01826d715EC](https://arbiscan.io/address/0xCb6CcBd979aa167b81411e672050c01826d715EC)
- [0x8C1b49B1A45d9FD50c5846a6Cd19a5ADaA376B1B](https://arbiscan.io/address/0x8C1b49B1A45d9FD50c5846a6Cd19a5ADaA376B1B)
- [0xb562b6CdEEE3ec10E4803B8dcfef81a32074e6B5](https://arbiscan.io/address/0xb562b6CdEEE3ec10E4803B8dcfef81a32074e6B5)
- [0x408822E4E8682413666809b0655161093cd36f2b](https://arbiscan.io/address/0x408822E4E8682413666809b0655161093cd36f2b)

### Optimism (chainId: 10)

- [0xFa773e2c7df79B43dc4BCdAe398c5DCA94236BC5](https://optimistic.etherscan.io/address/0xFa773e2c7df79B43dc4BCdAe398c5DCA94236BC5)
- [0x55a4983949f8a3156Ad483c4003218a7F33D466b](https://optimistic.etherscan.io/address/0x55a4983949f8a3156Ad483c4003218a7F33D466b)
- [0xB25255036f210D7E32FC96e25460aB121FF0C25d](https://optimistic.etherscan.io/address/0xB25255036f210D7E32FC96e25460aB121FF0C25d)
- [0x047801ED4F53Ad3dc28649ab972b3C949f27505c](https://optimistic.etherscan.io/address/0x047801ED4F53Ad3dc28649ab972b3C949f27505c)
- [0x4D43E78E669eD90bb125eF161F530E173f03834b](https://optimistic.etherscan.io/address/0x4D43E78E669eD90bb125eF161F530E173f03834b)
- [0x17B0FD3eB9CFbdA5B46A0C896e28b3F0c5a7F61d](https://optimistic.etherscan.io/address/0x17B0FD3eB9CFbdA5B46A0C896e28b3F0c5a7F61d)
- [0x01c6dc3bD8B175a9494F00b6D224b14EdC67CD34](https://optimistic.etherscan.io/address/0x01c6dc3bD8B175a9494F00b6D224b14EdC67CD34)
- [0xb58B331b9cf46c597A34F9e198e8bB9ec5f17ADf](https://optimistic.etherscan.io/address/0xb58B331b9cf46c597A34F9e198e8bB9ec5f17ADf)

### Base (chainId: 8453)

- [0xeB3C9fcE37A355df8f4a01CdaFA75b370607a21f](https://basescan.org/address/0xeB3C9fcE37A355df8f4a01CdaFA75b370607a21f)

### BNB Chain (chainId: 56)

- [0x977e9b368E5aBEe020B5096A03cE6f78cb3439cf](https://bscscan.com/address/0x977e9b368E5aBEe020B5096A03cE6f78cb3439cf)

### Avalanche (chainId: 43114)

- [0x9e64f0CD206cce2Da5dE08E7F482D62F57013D0e](https://avalanche.routescan.io/address/0x9e64f0CD206cce2Da5dE08E7F482D62F57013D0e)
- [0x92cECB67Ed267FF98026F814D813fDF3054C6Ff9](https://avalanche.routescan.io/address/0x92cECB67Ed267FF98026F814D813fDF3054C6Ff9)

### Sonic (chainId: 146)

- [0xf81d90DF1B63d48536E78564d24d5DD8F2BE58aD](https://sonicscan.org/address/0xf81d90DF1B63d48536E78564d24d5DD8F2BE58aD)
- [0x4e9dE3a64c911A37f7EB2fCb06D1e68c3cBe9203](https://sonicscan.org/address/0x4e9dE3a64c911A37f7EB2fCb06D1e68c3cBe9203)
- [0xa42001D6d2237d2c74108FE360403C4b796B7170](https://sonicscan.org/address/0xa42001D6d2237d2c74108FE360403C4b796B7170)

### Mantle (chainId: 5000)

- [0xe5b39b0b2173caA82BaEa368952c6183cA2DA3Ac](https://mantlescan.xyz/address/0xe5b39b0b2173caA82BaEa368952c6183cA2DA3Ac)

### Ink (chainId: 57073)

- [0xD13921239e3832FDC4141FDE544D3D058B529A5D](https://explorer.inkonchain.com/address/0xD13921239e3832FDC4141FDE544D3D058B529A5D)

### Injective (chainId: 1776)

- [0x39021662EF7679845E6851E38E01912f556A861f](https://blockscout.injective.network/address/0x39021662EF7679845E6851E38E01912f556A861f)
- [0xD2bf5845Ebc4d2b7966dD20Ad59Cb620F355A235](https://blockscout.injective.network/address/0xD2bf5845Ebc4d2b7966dD20Ad59Cb620F355A235)

### MegaETH (chainId: 4326)

- [0x95a7bC57c738C7f64103B93D04f49cbCa566afFD](https://mega.etherscan.io/address/0x95a7bC57c738C7f64103B93D04f49cbCa566afFD)

### OKX X Layer (chainId: 196)

- [0x650b50E16A703e53A7944CCad513ad21670F0D09](https://www.oklink.com/x-layer/address/0x650b50E16A703e53A7944CCad513ad21670F0D09)

### XDC (chainId: 50)

- [0xf81d90DF1B63d48536E78564d24d5DD8F2BE58aD](https://xdcscan.com/address/0xf81d90DF1B63d48536E78564d24d5DD8F2BE58aD)

---

For the authoritative, always up-to-date current factory address of each chain, read
`silo-core/deployments/<chain>/SiloFactory.sol.json` on the **`master`** branch.
