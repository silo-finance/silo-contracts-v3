# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## Unreleased

## [4.1.0] - 2026-02-18
### Added
- Injective deployment for Silo V3
- `getVerions()` to `ISiloLens` interface 

## [4.0.0] - 2026-02-17
### Added
- silo-core: Liquidation by defaulting (#1694)
- add additional events for external app integration (#1737)

### Fixed
- silo-core: handle 999 share case in liquidation (#1696)
- silo-core: fix rounding direction in `valueToAssetsByRatio` (#1701)
- fix: silo incentive backwards compatible (#1710)
- silo-core: fix limitation of rewards amount for immediate  (#1740)
- silo-core: fix max withdraw - totalAssets underestimation (#1735)

### Removed
- silo-core: remove same borrow functionality (#1703)

## [3.19.0] - 2026-02-16
### Markets
- rsETH / WETH new market on Mainnet

## [3.18.0] - 2026-02-11
### Markets
- sUSDp / USDC new market on Avalanche
- ezETH / WETH new market on Arbitrum

## [3.17.0] - 2026-01-30
### Markets
- agETH / WETH new market on Mainnet
- hgETH / WETH new market on Mainnet
- PT-sw-avUSDx(avUSD)-2026-05-15 / USDC new market on Avalanche
- PT-savUSD(avUSD)-2026-05-15 / USDC new market on Avalanche
- PT-savUSD(avUSD)-2026-05-15 / USDC new market on Avalanche

### Added
- static-4-6 IRM config

## [3.16.0] - 2026-01-13
### Markets
- weETH / WETH V2 new market on Arbitrum
- PGOLD / PUSD new market on Arbitrum

## [3.15.0] - 2025-12-19
### Added
- More configs to DKinkIRMConfigs.json

### Markets
- rsETH / WETH with new IRM on Arbitrum
- siUSD / USDC with new IRM on Mainnet
- PT-reUSD-25JUN2026 / USDC with new IRM on Mainnet

## [3.14.0] - 2025-12-18
### Added
- added `IVersioned` inerface

## [3.13.2] - 2025-12-11
### Added
- silo-core: calculate debt to cover for profitable liquidation (#1693)
- rescue WAVAX from vault (#1691)

### Changed
- known issues: Liquidation collateral underestimation (#1578)
- silo-coracles: cleanup for PTLinear oracle
- silo-core: compare SiloDeployer addresses to previous deployment (#1688)
- silo-vaults: fix broadcast path (#1689)
- silo-core: fix search for IRM config name
- silo-core: run deployer check on deployment (#1686)

### Markets
- silo-core: `sYUSD/USDC`` market on Avalanche (#1678)
- silo-core: `sUSDp/USDC market on Avalanche (#1677)
- silo-core: `savUSD / USDC` Avalanche market (#1683)
- silo-core: `savBTC / BTC` Avalanche market (#1684)
- silo-core: `mAPOLLO/USDC` market on Mainnet (#1669)

## [3.13.1] - 2025-12-11
### Removed
- remove deprecated `FixedPricePTAMMOracle`

## [3.13.0] - 2025-12-05
### Markets
- silo-core: `PT-iUSD-19FEB2026 / USDC` new market on Mainnet
- silo-core: `PT-sUSDai-19FEB2026 / USDC` new market on Arbitrum
- silo-core: `PT-USDai-19FEB2026 / USDC` new market on Arbitrum
- silo-core: `PT-thBILL-19FEB2026 / USDC` new market on Arbitrum

## [3.12.0] - 2025-10-28
### Updated
- silo-core: calculate debt to cover for profitable liquidation (#1693)
- `SiloLens` redeployment

## [3.11.1] - 2025-10-20
### Updated
- redeploy SiloDeployer with audited version of Kink

## [3.11.0] - 2025-10-20
### Added
- silo-core: Dynamic Kink Factory deployment
- silo-core: add support for PT linear to silo deployer script (#1676)
- silo-core: new kink configs
- silo-core: add support for kink predefined configs (#1679)
- Pendle linear oracle support  (#1660)
- fix warnings in code and add CI to check for warnings (#1450)
- Include local broadcast files for latest run (#1635)

### Changed
- silo-oracles: redeploy CHAINLINK_USDC_USD to use newest chainlink (#1653)
- silo-core: replace irm with factory name in market configs
- silo-core: update incentive factories

#### Markets
- silo-core: `PT-siUSD-8JAN2026/USDC` market on Mainnet (#1671)
- silo-core: `PT wstUSR (USR) / USDC` Ethereum market (#1652)
- silo-core: `PT-iUSD 4 DEC25 / USDC` Ethereum market (#1650)
- external market verification: Silo `RYT/USDC` (147) on Arbitrum (#1640)

### Removed
- silo-core: remove cache from CI (#1637)
- remove irm zero file and additional tests for new market (#1661)

## [3.10.0] - 2025-09-30
### Added
- silo-oracles: wstETH adapter
- silo-core: debt share token approvals issue with leverage documented (#1457)
- add `getOracleAddresses` to SiloLens 
- silo-core: Leverage router (#1479)
- silo-core: SiloLens `maxLiquidation` fn (#1488)
- common: global pause (#1455)
- silo-core: Two watchlists in Hypernative (#1502)
- silo-oracles: PT AMM Oracle (#1586)

#### Markets
- silo-core: tETH/WETH new market on Mainnet (#1459)
- silo-core: PT-tETH-8JAN2026/WETH new market on Mainnet (#1460)
- silo-core: RLP/USDC V2 new market on Mainnet (#1465)
- silo-core: savUSD/USDC v2 on Avalanche (#1469)
- silo-core: xUSD/USDC new market on Mainnet (#1471)
- silo-core: xETH/scETH new market on Sonic (#1475)
- silo-core: xBTC/scBTC new market on Sonic (#1476)
- silo-core: scBTC/scUSD V2 new market on Sonic (#1478)
- silo-core: slvlUSD/USDC new market on Mainnet (#1485)
- silo-core: PT-slvlUSD-25SEP2025/USDC new market on Mainnet (#1486)
- silo-core: xUSD/USDC new market on Avalanche (#1489)
- silo-core: xBTC/BTC.b new market on Avalanche (#1491)
- silo-core: yUTY/USDC new market on Avalanche (#1527)
- silo-core: wstETH/WETH new market on mainnet (#1534)
- silo-core: weETH/WETH V2 new market on Mainnet (#1535)
- silo-core: yUTY/USDT new market on Avalanche (#1528)
- silo-core: xUSD/USDT new market on Avalanche (#1532)
- silo-core: savUSD/USDT new market on Avalanche (#1533)
- silo-core: xUSD/AUSD new market on Avalanche (#1529)
- silo-core: savUSD/AUSD new market on Avalanche (#1531)
- silo-core: smsUSD/USDC.e new market on Sonic (#1538)
- silo-core: ETH+/WETH new market on mainnet (#1557)
- silo-core: PT-tUSDe-25SEP2025/USDC new market on mainnet (#1556)
- silo-core: ARM-WETH-stETH/WETH new market on mainnet (#1555)
- silo-core: yUSD/USDC new market on Avalanche (#1558)
- silo-core: wOS wS new market on Sonic (#1564)
- silo-core: reUSD/USDC new market on Avalanche (#1579)
- silo-core: savUSD/USDC new market on Avalanche (#1581)
- silo-core: sAVAX/WAVAX (borrowable sAVAX) new market on Avalanche (#1583)
- silo-core: market PT-USDe-25SEP2025 (cross-chain) / USDC on Avalanche (#1575)
- silo-core: sUSDS/USDC market arbitrum (#1592)
- silo-core: sUSDe/USDC market arbitrum (#1594)
- silo-core: weETH/ETH market on Arbitrum (#1591)
- silo-core: wstETH-WETH market on Arbitrum (#1585)
- silo-core: deploy liquidator helper (#1595)
- silo-core: rsETH/ETH market on Arbitrum (#1593)
- silo-core: syrupUSDC/USDC market arbitrum (#1597)
- silo-core: PTsUSDai 19nov25 / USDC Arbitrum market (#1596)
- silo-core: siUSD/USDC Ethereum market (#1614)
- silo-core: PT-siUSD (9 OCT 25)/USDC on Ethereum (#1615)
- silo-core: xUSD/USDC on Arbitrum (#1616)
- silo-core: wstUSR/USDC market on Arbitrum (#1617)
- silo-core: USDC/USDai on Arbitrum (#1619)
- silo-core: `sUSDe / USDC` on Avalanche (#1623)
- silo-core: `PT_sw_esdeUSD_3_deUSD_2026_02_06 / USDC` on Avalanche (#1624)
- silo-core: `PT_Ethena_USDe_27Nov2025 / USDC` Avalanche market (#1622)
- silo-core: `PT-USDf-29JAN2026 / USDC` mainnet market (#1628)
- silo-core: `PT-sUSDf29Jan26 / USDC` mainnet market (#1627)
- silo-core: `savETH / ETH` mainnet market (#1629)

### Changed
- fix SiloLens and tests warnings
- silo-core: add reentrancy check for rescue tokens in leverage (#1470)
- silo-core: approve exact amount in leverage
- silo-core: resetting leverage transient variables
- silo-oracles: Revert for zero price in OracleScaler (#1496)
- silo-core: make fee be less or equal the MAX_LEVERAGE_FEE (leverage)
- silo-core: ensure closing leverage with permit supports protected token
- silo-oracles: optional underlying asset in ERC4626OracleHardcodeQuote (#1547)
- certora: disable failing check for router

### Fixed
- silo-core: backwards compatible SiloIncentivesController (#1550)

### Removed
- silo-core: Removed deprecated silo router (#1543)

### Updated
- silo-core: re-deploy SiloLens (#1466)
- silo-core: LeverageRouter deploy mainnet, sonic (#1493)
- silo-core: LeverageRouter deployment avalance (#1495)
- silo-core: leverage deployment
- silo-core: USDC gauge for savUSD Silo on Avalanche (#1513)
- silo-core: Global pause deployment (#1521)
- silo-core: gauge for BTC.b in savBTC market on Avalanche (#1526)
- silo-oracles: ERC4626OracleHardcodeQuoteFactory redeploy (#1554)
- liquidator helper for enso and odos on arbitrum (#1574)
- silo-core: incentive controller for xSilo (#1600)
- silo-core: new gauge for xSilo

## [3.9.0] - 2025-07-03
### Added
- silo-core: Silo hook deployment (#1453)
- silo-core: GaugeHookReceiver with Ownable 1-step transfer (#1447)
- silo-core: Manual liquidation helper accepts native tokens (#1439)
- silo-core: Allow multiple instances of liquidation helper (#1436)
- new markets:
  - silo-core: wmetaS/wS market on Sonic (#1437)
  - silo-core: Anon/USDC.e market on Sonic (#1438)
  - silo-core: yUSD/USDC Silo on Arbitrum (#1446)
  - silo-core: sACRED/USDC market on Avalanche (#1452)
  - silo-core: USDf/USDC market on mainnet (#1442)

### Fixed
- silo-core: fix leverage bug with swap abusing debt share token receive allowance and ERC-20 approval (#1434)

### [3.8.0] - 2025-06-26
### Added
- silo-core: Ethereum mainnet deployment
- silo-core: Avalanche deployment  
- silo-vaults: Avalanche deployment
- silo-oracles: Avalanche deployment
- silo-oracles: Wrapped Pendle LP tokens price providers
- silo-oracles: WrappedMetaVaultOracleAdapter
- silo-oracles: ERC4626Oracle with hardcoded quote token
- silo-oracles: ERC4626OracleWithUnderlying
- silo-oracles: Oracle scaler factory mainnet deployment
- silo-oracles: PT oracles deployments
- silo-oracles: Adjust PT oracles for different decimals case
- silo-core: SiloIncentivesControllerFactory deployment
- silo-core: SiloHookV1 deployment
- silo-core: SiloVerifier for the Pendle LPT markets
- silo-core: SiloRouterV2 deployment with Pendle LP tokens wrap/unwrap support
- silo-core: leverage live deployment for sonic, mainnet
- silo-core: certora rules for leverage debt token approvals
- silo-core: protect permit in leverage from frontrun
- new markets:
  - silo-core: PT-stS-18DEC2025 wS market on Sonic
  - silo-core: xUSD scUSD Silo on Sonic
  - silo-core: sUSDX USDC Silo on Arbitrum
  - silo-core: ARB USDC Silo on Arbitrum
  - silo-core: WBTC USDC Silo on Arbitrum
  - silo-core: sUSDf/USDC mainnet market
  - silo-core: PT-sUSDf-25SEP2025/USDC mainnet market
  - silo-core: wmetaUSD/USDC Sonic market
  - silo-core: USR/USD market on mainnet
  - silo-core: ezETH/WETH mainnet market
  - silo-core: weETH WETH Silo on mainnet
  - silo-core: LPT-sUSDE-25SEP2025/USD mainnet market
  - silo-core: LPT-sUSDE-31JUL2025/USD mainnet market
  - silo-core: LPT-eUSDe-14AUG25/USD mainnet market
  - silo-core: PT-eUSDE-14AUG2025/USDC mainnet market
  - silo-core: PT-cUSDO-20NOV2025/USDC mainnet market
  - silo-core: PT-sUSDE-25SEP2025/USDC mainnet market
  - silo-core: PT-USDS-14AUG2025/USDC mainnet market
  - silo-core: PT-eUSDE-14AUG2025/USDf mainnet market
  - silo-core: WBTC/USDC market on mainnet
  - silo-core: RLP/USDC market on mainnet
  - silo-core: wsrUSD/USDC mainnet market
  - silo-core: USR/USDC mainnet market redeployment
  - silo-core: wstUSR/USD mainnet market
  - silo-core: PT-USDe 25 Sep 2025 / USDC mainnet market
  - silo-core: mMEV/USDC mainnet market
  - silo-core: PT-USR-4SEP2025/USDC mainnet market
  - silo-core: PT-wstUSR-25SEP2025/USDC mainnet market
  - silo-core: PT-RLP-4SEP2025/USDC mainnet market
  - silo-core: WAVAX/USDC avalanche market
  - silo-core: sdeUSD/USDC avalanche market
  - silo-core: deUSD/USDC avalanche market
  - silo-core: BTC.b/WAVAX Avalanche market
  - silo-core: ggAVAX/WAVAX Avalanche market
  - silo-core: sBUIDL/USDC Avalanche market
  - silo-core: sAVAX/WAVAX Avalanche market
  - silo-core: scBTC/scUSD sonic market
  - silo-core: savBTC/WBTC.b avalanche market
  - silo-core: AUSD/USDC avalanche market
  - silo-core: savUSD/USDC avalanche market
  - silo-core: wsrUSD/USDC sonic market
  - silo-core: wmetaUSD/scUSD sonic market

### Removed
- silo-oracles: remove heartbeat check from DIA oracle
- silo-oracles: remove heartbeat check from Chainlink oracle
- Removed ve-silo and proposals

### [3.7.0] - 2025-06-10
### Added
- silo-core: Ethereum deployment
- silo-vaults: Ethereum deployment
- silo-oracles: DIA price provider deployments
- x-silo: XSilo and Stream
- x-silo: production deployment
- silo-vaults: fixed decimals offset 
- silo-core: enigma invariant suite core
- new markets:
  - silo-core: PT-Silo-46-scUSD-14AUG2025 USDC.e market on Sonic
  - silo-core: PT-aSonUSDC-14AUG2025 USDC.e Silo on Sonic
  - silo-core: PT-Silo-20-USDC.e-17JUL2025 USDC.e new market on Sonic
  - silo-core: WBTC USDC new market on Arbitrum
  - silo-core: wstETH WETH new market on Arbitrum
  - silo-core: kBTC USDT0 Silo on Ink
  - silo-core: kBTC WETH Silo on Ink
  - silo-core: ezETH WETH market on Arbitrum
  - silo-core: WBTC WETH market on Arbitrum
  - silo-core: ARB WETH market on Arbitrum
  - silo-core: ETH+ WETH market on Arbitrum
  - silo-core: PEAS USDC on Arbitrum
  - silo-core: GRAIL USDC market on Arbitrum
  - silo-core: PT-wstkscUSD-18DEC2025 USDC.e market on Sonic
  - silo-core: PT-wOS-18DEC2025 wS silo on Sonic 
  - silo-core: PT-wstkscETH-18DEC2025 WETH market on Sonic
  - silo-core: yUSD USDC.e silo on Sonic
  - silo-core: OS scUSD market on Sonic
  - silo-core: xUSD USDC.e market on Sonic

### [3.6.0] - 2025-05-19
#Added 
- certora specs for the Silo Vaults
- silo-core: incentive program name conversion
- silo-core: liquidation helper deployment ink
- silo-oracles: revert on zero price in DIA
- silo-oracles: pyth deployment
- SiloIncentivesController and SiloVaultDeployer deployment
- new markets:
  - silo-core: WETH USDC market on Arbitrum
  - silo-core: sUSDX USDC new market Arbitrum
  - silo-core: ARB USDC new market on Arbitrum
  - silo-core: WETH USDT market on Ink

### [3.5.0] - 2025-05-15
- silo-core: fix `maxBorrow`, see explanation in code, method `maxBorrowValueToAssetsAndShares()`
- silo-core: Silo implementation redeploy
- silo-core: SiloLens isTokenAddress fn check code size
- silo-core: wstkscUSD USDC.e new market
- silo-core: wOS wS borrowable new market
- silo-core: EURC.e USDC.e new market

### [3.4.0] - 2025-05-09
- silo-core: prioritize DAO fee to ensure it is not zero-out by precision error
- silo-core: count for fractions when calculate maxBorrow
- silo-core: underestimate `maxWithdraw` to count for interest fractions
- silo-core: fix maxRedeem for dust
- silo-core: proper name conversion in the getProgramName fn
- silo-core: silo lens getter for programs names
- silo-core: Incentives controller for ws in beS / wS Silo
- silo-vaults: helper contract to deploy claiming logics
- x-silo: Silo Token V2
- sonic deployment: silo-core, silo-oracles
- arbitrum deployment: silo-core, silo-oracles, silo-vaults
- optimism deployment: silo-core, silo-oracles, silo-vaults
- ink deployment: silo-core, silo-oracles, silo-vaults

## [3.3.0] - 2025-05-01
- silo-vaults: SiloIncentivesControllerCLDeployer helper contract to deploy claiming logics
- silo-core: moved hooks into silo-core/contracts/hooks

## [3.2.0] - 2025-04-30
- Revert "silo-vaults: deployment sonic 1 min timelock"
- silo-core: silo lens getter for programs names

## [3.1.0-rc.3] - 2025-04-23
- silo-vaults: deployment sonic 1 min timelock

## [3.1.0] - 2025-04-23
- silo-vaults: deployment sonic
- silo-core: SiloDeployer hook and config reorg
- silo-core: InterestRateModelV2Factory reorg protection
- silo-oracles: factories reorg protection

## [3.1.0-rc.2] - 2025-04-18
- silo-vaults: deployment min timelock 1 day

## [3.1.0-rc.1] - 2025-04-18
- silo-vaults: deployment min timelock 1 min

## [3.0.0] - 2025-04-17
- silo-vaults: Silo Vaults Deployer
- silo-vaults: Incentives claiming logics trusted factories
- silo-vaults: Deflation attack
- silo-vaults: Wrong calculation of toSupply which is supplied to a market will lead to less supply for some markets
- silo-vaults: Fee not Accrued In Transfer Functions Leads to Reward Loss
- silo-vaults: Supply function doesn't account for market maxDeposit when providing assets to it
- silo-vaults: SiloVault.sol :: Markets with assets that revert on zero approvals cannot be removed
- silo-vaults: SiloVault.maxDeposit and SiloVault.maxMint don't comply with ERC4626 
- silo-vaults: L-01 Factories using CREATE opcode create contracts vulnerable to reorgs
- silo-vaults: Improvement: exact approvals on deposit
- silo-vaults: Improvement: Incentives module owner is the silo vault owner (Ownable2Step removed)
- silo-vaults: Changed permissions: setArbitraryLossThreshold fn and syncBalanceTracker fn only guardian 
- silo-vaults: Acceptable loss configuration
- silo-vaults: internal balances sync
- silo-vaults: syncBalanceTracker fn require valid override input
- silo-vaults: approval on deposit
- silo-vaults: create2 factories
- silo-vaults: Incentives module owner is the silo vault owner
- silo-core: [M-01] catch when fee transfer is not successful
- silo-core: address as programId on immediate rewards distribution
- silo-core: store fraction of interest and fraction of fees
- silo-core: add reentrancy protection for liquidation call
- silo-core: PT-aSonUSDC-14AUG2025 / scUSD market
- silo-core: PT-wstkscETH/scETH market
- silo-core: sfrxUSD / scUSD new market
- silo-core: WBTC / USDC Silo
- silo-core: x33 asset adapter
- silo-core: x33 new Silo
- silo-core: add bulk methods for APR in SiloLens
- silo-core: ERC4626 price provider update
- silo-core: SiloFactory initial silo id 100
- silo-core: restore current router deployments
- silo-core: DebtShareToken with receive approval on mint
- bump: solidity to 0.8.29

## [2.1.0] - 2025-04-16
### Fixed
- silo-core: [Restore current router deployments, SiloRouterV2 renaming](https://github.com/silo-finance/silo-contracts-v2/commit/4d4b2c24e2c111e6b00efe25a76618499a271417)

## [2.0.1] - 2025-03-19
### Fixed
- silo-vaults: [Guardian role in the vault incentives module](https://github.com/silo-finance/silo-contracts-v2/commit/389b0575d01f33d745876f6cc26747c082de860b)

## [2.0.0] - 2025-03-19
### Added
- silo-vaults: [Internal tracker for market allocations](https://github.com/silo-finance/silo-contracts-v2/commit/99d7ccd0ac1bc84e6667bae30bc5aa8e1f064bef)

### Changed
- silo-vaults: require asset decimals to be up to 18
- silo-core: accrue fees on claiming rewards
- silo-core: [fee receiver per silo per asset](https://github.com/silo-finance/silo-contracts-v2/pull/1114/commits/d476473bdd090516752988ee065a0c369733beec)
- silo-vaults: [add reentrancy protection on transfer](https://github.com/silo-finance/silo-contracts-v2/pull/1114/commits/3ad3508a84c963e86476db3772fc2c7939185e93)
- silo-vaults: [reset approval on market removal](https://github.com/silo-finance/silo-contracts-v2/pull/1114/commits/2828124f549b8fefa6b577a20bf6d756a451a258)
- silo-vaults: [vault incentives module timelock and permissions](https://github.com/silo-finance/silo-contracts-v2/pull/1114/commits/ca9fe593fbc08fd33f3ce36c3729ad8dee630cd9)
- silo-vaults: [revert action when zero assets or shares](https://github.com/silo-finance/silo-contracts-v2/pull/1114/commits/313753ca599a66dade8e074ccdc6498a07651c73)
- silo-vaults: [use offset 6](https://github.com/silo-finance/silo-contracts-v2/pull/1114/commits/f9344efdec25f9afdf99595b1b1fe7128d572f8c)

### Fixed
- silo-core: allow to burn NFT only by owner
- silo-core: revert on invalid token type in `Hook.shareTokenTransfer()`
- silo-vaults: [M-01 VaultIncentivesModule initialization](https://github.com/silo-finance/silo-contracts-v2/pull/1114/commits/8405901a68e8c85d2f543a48c7c0defdc3abf265)
- incentives: [L-1 The function `_transferRewards` does not check return value](https://github.com/silo-finance/silo-contracts-v2/pull/1114/commits/ac4afd92aaaae93ac0cf9387c7fc825055d6505a)
- silo-vaults: [use `previewRedeem` instead of the `convertToAssets`](https://github.com/silo-finance/silo-contracts-v2/pull/1114/commits/7cbc420472babe86d9e3ef70b4dbe50f18b6eb1c)
- silo-vaults: [factory with reorgs protection](https://github.com/silo-finance/silo-contracts-v2/pull/1114/commits/3c950ac432fa8a773868c9101fac2c1ebe2cc486)
- silo-vaults: [L-06 Vault could be vulnerable to an inflation attack, add offset 3](https://github.com/silo-finance/silo-contracts-v2/pull/1114/commits/2bf1a139485bf5f85676aca94a5c64e36f86a049)
- silo-core: [immediate incentives distribution only notifier](https://github.com/silo-finance/silo-contracts-v2/pull/1114/commits/3ba8d5673cf3d0e70e7b50022e2cecca4f847685)
- silo-core: [require existing programs on rewards claims](https://github.com/silo-finance/silo-contracts-v2/pull/1114/commits/79ada63f9544c9ec9cb6dc11e3105e60eb3f90e9)
- silo-core: [fix daoRevenue value when fee receiver empty](https://github.com/silo-finance/silo-contracts-v2/pull/1114/commits/58f6bc20cafcd0fce00d65f3d43db5a0853d9283)
- silo-core: [GaugeHookReceiver send notifications even if killed](https://github.com/silo-finance/silo-contracts-v2/pull/1114/commits/92f4975556afb3c5044cbdacb31a9c0b522e3ab0)
- silo-core: [protected collateral protection](https://github.com/silo-finance/silo-contracts-v2/pull/1114/commits/c84af3db2c0fa2568c941520292894f72b3ad40d)
- silo-core: [Handling revert on deployer fee transfer](https://github.com/silo-finance/silo-contracts-v2/pull/1114/commits/9f7de9c87c9a1a9feb1dba1685ec1c2ad8b66518)
- silo-core: [SiloFactory reorg protection](https://github.com/silo-finance/silo-contracts-v2/pull/1114/commits/2f328a82eef769f259a6ff0b2113524f6eae5544)
- silo-vaults: setCap fn in the SiloVaultActionsLib

### Updated
- silo-core: Router with multicall
- Silo hooks refactoring
- silo-vaults: [use 18 decimals offset in idle vault](https://github.com/silo-finance/silo-contracts-v2/pull/1114/commits/528bded8c406517fa5faf8a782be2b68e0a39a51)
- silo-vaults: replace .transfer with low level call
- silo-core: [switch collateral event on borrow](https://github.com/silo-finance/silo-contracts-v2/pull/1114/commits/9e4afb3483ac5782c74191b3019cebca96d38321)

### Removed
- silo-vaults: [remove skim method](https://github.com/silo-finance/silo-contracts-v2/pull/1114/commits/b6bc1e397e6d7bb7a0091ccc2cfad7293af98827)
- silo-vaults: [remove loss check](https://github.com/silo-finance/silo-contracts-v2/pull/1114/commits/f9344efdec25f9afdf99595b1b1fe7128d572f8c)

## [1.9.0] - 2025-02-28
### Added
- add method `getUsersHealth` to SiloLens

## [1.8.0] - 2025-02-25
### Added
- SiloLens redeployment

## [1.7.0] - 2025-02-26
### Added
- LBTC / scBTC market on Sonic
- LBTC / WBTC market on Sonic

## [1.6.0] - 2025-02-25
### Added
- SiloRouter deployment

## [1.5.0] - 2025-02-19
### Added
- SiloLens deployment

## [1.4.0] - 2025-02-18
### Added
- Router with multicall

## [1.3.5] - 2025-02-07
### Updated
- stS/S market with 18 decimals share token on Sonic

## [1.3.4] - 2025-02-07
### Updated
- deploy new `LiquidationHelper` 

## [1.3.3] - 2025-02-06
### Updated
- adjustment for coverage to work

## [1.3.2] - 2025-02-04
### Added
- Anon/USDC.e market sonic

## [1.3.1] - 2025-02-04
### Added
- wstkscETH/ETH market sonic

## [1.3.0] - 2025-02-04
### Added
- wanS/S market sonic

## [1.2.0] - 2025-02-03
### Added
- silo-coracle: silo virtual asset name and symbol
- silo-core: add flag that informs about full liquidation
- silo lens redeployment
- silo-oracles: ERC4626 price oracle
- silo-oracles: Pyth aggregator factory
- silo-oracles: OracleScaler to normalize amounts for 18 decimal
- silo-core: manual liquidation helper
- wS/USDC.e borrowable S market sonic
- woS/S market sonic
- wstkscUSD/USDC.e market sonic

## [1.1.0] - 2025-01-27
### Added
- solvBTC.BNN/solvBTC market sonic
- wS/scUSD market sonic
- Redeployment SiloDeployer
- silo-core: use underlying token decimals in collateral share token
- silo-oracles: invert flag

## [1.0.0] - 2025-01-20
### Added
- add rescue function to incentive controller

### Updated
- allow to restart incentive program after some time and ensure rewards are not calculated for a "gap"
- ensure claim rewards reset state after claiming

## [0.20.0] - 2025-01-10
### Updated
- Redeployment market for Sonic: `stS/S`
- Redeployment SiloRouter
- Redeployment GaugeHookReceiver with updated event and reduced contract size

## [0.19.0] - 2025-01-08
### Added
- Redeployment market for Sonic: `stS/S`
- Redeployment GaugeHookReceiver
- Extended LiquidationCall event
- silo vaults catch 63/64 gas attack

## [0.18.0] - 2025-01-07
### Added
- Sonic and Arbitrum deployments
- new market for Sonic: `stS/S`
- Silo Incentives controller
- Silo vaults incentives module and incentives claiming logic
- Renaming of 'MetaMorpho' to 'SiloVaults'
- Extended LiquidationCall event

## [0.17.3] - 2024-12-20
### Fixed
- allow LiquidationHelper to accept ETH

## [0.17.2] - 2024-12-16
### Added
- new markets for v0.17: `wstETH/WETH`, `gmETH/WETH`, `solvBTC/wBTC`, `ETHPlus/WETH`

## [0.17.1] - 2024-12-14
### Updated
- redeployment of silo-vault with `MIN_TIMELOCK` set to 1 minute for QA purposes

## [0.17.0] - 2024-12-14
### Updated
- redeployment of whole protocol

## [0.16.0] - 2024-12-12
### Added
- add support for custom oracle setup

## [0.15.1] - 2024-12-03
### Added
- add initial setup for IRM params: `ri` and `Tcrit`

### Fixed
- fix `maxBorrow` estimation

## [0.15.0] - 2024-12-02
### Added
- `PublicAllocator` contract for vaults
- add reentrancy for `withdrawFees`

### Fixed
- ensure transition deposit not fail when user insolvent

## [0.14.0] - 2024-11-25
### Added
- Vault functionality based on MetaMorpho
  - MetaMorpho was adjusted to work with ERC4626 standard
  - Concept of Idle market needs to be replaced with additional vault. By default, in Silo `IdleVault` is used. 

## [0.13.0] - 2024-11-19
### Added
- `LiquidationHelper` and `Tower`

## [0.12.1] - 2024-11-04
### Added
- LICENSE

### Changed
- modified license for some solidity files

### Fixed
- SiloLens redeployment

## [0.12.0] - 2024-11-01
### Added
- solvBTC/wBTC market Arbitrum
- gmETH/WETH market Arbitrum
- wstETH/WETH market Arbitrum
- ETH+/WETH market Arbitrum
- SiloRouter with preview methods instead of convertToAssets

## [0.11.0] - 2024-10-30
### Changed
- dao fee can be set based on range

## [0.10.1] - 2024-10-29
### Added
- optimism deployment

## [0.10.0] - 2024-10-28
### Changed
- make target LTV after liquidation configurable

## [0.9.1] - 2024-10-25
### Fixed
- SiloRouter with convertToAssets

## [0.9.0] - 2024-10-23
### Changed
- allow for forced transfer of debt
- use transient storage for reentrancy flag

### Fixed
- remove unchecked math from some places
- exclude protected assets from flashloan

### Removed
- remove `leverageSameAsset`
- remove self liquidation
- remove decimals from value calculations

## [0.8.0] - 2024-09-13

Design changes:

- The liquidation module was transformed into a hook receiver.
- Silo is now a share collateral token and implements share token functionality. So, now we have collateral share token (silo), protected share token (customized ERC-20), debt share token (customized ERC-20).
- Removed ‘bool sameAsset’ from the silo and introduced separate methods for work with the same asset.
- Removed ordered configs from the SiloConfig and introduced a collateral silo concept.
- Removed ‘leverage’ functionality from the Silo.borrow fn.
- Removed InterestRateModelV2.connect and added InterestRateModelV2.initialize. Now each silo has a different irm that is a minimal proxy and is cloned during the silo deployment like other components

## [0.7.0] - 2024-06-03
### Added
 - Refactoring of the hooks' actions and hooks inputs
 - Reentrancy bug fix in flashLoan fn
 - Rounding error bug fix in maxWithdraw fn
 - Overflow bug fix on maxWithdraw fn
 - ERC20Permit for share token
 - Added delegate call into the callOnBehalfOfSilo fn
 - Other minor fixes and improvements

## [0.6.2] - 2024-05-15
### Added
 - deployment with mocked CCIP and tokens for Arbitrum and Optimism

## [0.6.1] - 2024-05-14
### Fixed
- apply fixes for certora report

## [0.6.0] - 2024-05-06
### Added
- deposit to any silo without restrictions
- borrow same token
  - liquidation for same token can be done with sToken without reverting
  - case observed on full liquidation: when we empty out silo, there is dust left (no shares)

### Changed
- standard reentrancy guard was replaced by cross Silo reentrancy check

### Fixed
- fix issue with wrong configs in `isSolvent` after debt share transfer

## [0.5.0] - 2024-03-12
### Added
- SiloLens deploy

## [0.4.0] - 2024-02-22
### Added
- add returned code for `IHookReceiver.afterTokenTransfer`

## [0.3.3] - 2024-02-21
### Fixed
- underestimate `maxWithdraw`

## [0.3.2] - 2024-02-20
### Fixed
- fix rounding on `maxRedeem`
- fix rounding on `maxBorrow`

## [0.3.1] - 2024-02-19
### Fixed
- optimise `maxWithdraw`: do not run `getTotalCollateralAssetsWithInterest` twice

## [0.3.0] - 2024-02-15
### Added
- add `SiloLens` to reduced Silo size

### Changed
- change visibility of `total` mapping to public
- ensure total getters returns values with interest

### Removed
- remove `getProtectedAssets()`

## [0.2.0] - 2024-02-13
### Added
- Arbitrum and Optimism deployments

## [0.1.7] - 2024-02-12
### Fixed
- fix `maxBorrowShares` by using `-1`, same solution as we have for `maxBorrow`

## [0.1.6] - 2024-02-12
### Fixed
- fix max redeem: include interest for collateral assets

## [0.1.5] - 2024-02-08
### Fixed
- accrue interest on both silos for borrow

## [0.1.4] - 2024-02-08
### Changed
- improvements to `silo-core`, new test environments: certora, echidna

## [0.1.3] - 2024-02-07
### Fixed
- `SiloStdLib.flashFee` fn revert if `_amount` is `0`

## [0.1.2] - 2024-01-31
### Fixed
- ensure we can not deposit shares with `0` assets

## [0.1.1] - 2024-01-30
### Fixed
- ensure we can not borrow shares with `0` assets

## [0.1.0] - 2024-01-03
- code after first audit + develop changes

## [0.0.36] - 2023-12-27
### Fixed
- [issue-320](https://github.com/silo-finance/silo-contracts-v2/issues/320) TOB-SILO2-19: max* functions return
  incorrect values: underestimate `maxBorrow` more, to cover big amounts

## [0.0.35] - 2023-12-27
### Fixed
- [issue-320](https://github.com/silo-finance/silo-contracts-v2/issues/320) TOB-SILO2-19: max* functions return
  incorrect values: add liquidity limit when user has no debt

## [0.0.34] - 2023-12-22
### Fixed
- [TOB-SILO2-10](https://github.com/silo-finance/silo-contracts-v2/issues/300): Incorrect rounding direction in preview
  functions

## [0.0.33] - 2023-12-22
### Fixed
- [TOB-SILO2-13](https://github.com/silo-finance/silo-contracts-v2/issues/306): replaced leverageNonReentrant with nonReentrant,
  removed nonReentrant from the flashLoan fn

## [0.0.32] - 2023-12-22
### Fixed
- [issue-320](https://github.com/silo-finance/silo-contracts-v2/issues/320) TOB-SILO2-19: max* functions return 
  incorrect values

## [0.0.31] - 2023-12-18
### Fixed
- [issue-319](https://github.com/silo-finance/silo-contracts-v2/issues/319) TOB-SILO2-18: Minimum acceptable LTV is not
  enforced for full liquidation

## [0.0.30] - 2023-12-18
### Fixed
- [issue-286](https://github.com/silo-finance/silo-contracts-v2/issues/286) TOB-SILO2-3: Flash Loans cannot be performed 
  through the SiloRouter contract

## [0.0.29] - 2023-12-18
### Fixed
- [issue-322](https://github.com/silo-finance/silo-contracts-v2/issues/322) Repay reentrancy attack can drain all Silo assets

## [0.0.28] - 2023-12-18
### Fixed
- [issue-321](https://github.com/silo-finance/silo-contracts-v2/issues/321) Deposit reentrancy attack allows users to steal assets

## [0.0.27] - 2023-12-15
### Fixed
- [issue-255](https://github.com/silo-finance/silo-contracts-v2/issues/255): UniswapV3Oracle contract implementation 
  is left uninitialized

## [0.0.26] - 2023-12-15
### Fixed
- [TOB-SILO2-17](https://github.com/silo-finance/silo-contracts-v2/issues/318): Flashloan fee can round down to zero

## [0.0.25] - 2023-12-15
### Fixed
- [TOB-SILO2-16](https://github.com/silo-finance/silo-contracts-v2/issues/317): Minting zero collateral shares can 
  inflate share calculation

## [0.0.24] - 2023-12-15
### Fixed
- [TOB-SILO2-14](https://github.com/silo-finance/silo-contracts-v2/issues/314): Risk of daoAndDeployerFee overflow

## [0.0.23] - 2023-12-15
### Fixed
- [TOB-SILO2-12](https://github.com/silo-finance/silo-contracts-v2/issues/312): Risk of deprecated Chainlink oracles 
  locking user funds

## [0.0.22] - 2023-12-15
### Fixed
- [TOB-SILO2-10](https://github.com/silo-finance/silo-contracts-v2/issues/300): Incorrect rounding direction in preview 
  functions

## [0.0.21] - 2023-12-12
### Fixed
- [TOB-SILO2-13](https://github.com/silo-finance/silo-contracts-v2/issues/306): Users can borrow from and deposit to the 
  same silo vault to farm rewards

## [0.0.20] - 2023-12-11
### Fixed
EVM version changed to `paris`
- [Issue #285](https://github.com/silo-finance/silo-contracts-v2/issues/285)
- [Issue #215](https://github.com/silo-finance/silo-contracts-v2/issues/215)

## [0.0.19] - 2023-12-01
### Fixed
- TOB-SILO2-9: fix avoiding paying the flash loan fee

## [0.0.18] - 2023-12-01
### Fixed
- TOB-SILO2-7: fix fee distribution
- TOB-SILO2-8: fix fee transfer

## [0.0.17] - 2023-11-29
### Added
- TOB-SILO2-4: add 2-step ownership for `SiloFactory` and `GaugeHookReceiver`

## [0.0.16] - 2023-11-28
### Fixed
- TOB-SILO2-6: ensure no one can initialise GaugeHookReceiver and SiloFactory 

## [0.0.15] - 2023-11-28
### Fixed
- TOB-SILO2-1: ensure silo factory initialization can not be front-run

## [0.0.14] - 2023-11-28
### Fixed
- tob-silo2-5: fix deposit limit

## [0.0.13] - 2023-11-21
### Fixed
- fix `ASSET_DATA_OVERFLOW_LIMIT` in IRM model

## [0.0.11] - 2023-11-14
### Fixed
- [Issue #220](https://github.com/silo-finance/silo-contracts-v2/issues/220)

## [0.0.10] - 2023-11-14
### Fixed
- [Issue #223](https://github.com/silo-finance/silo-contracts-v2/issues/223)

## [0.0.9] - 2023-11-13
### Fixed
- [Issue #221](https://github.com/silo-finance/silo-contracts-v2/issues/221)

## [0.0.8] - 2023-11-13
### Fixed
- [Issue #219](https://github.com/silo-finance/silo-contracts-v2/issues/219)

## [0.0.7] - 2023-11-10
### Fixed
- [Issue #217](https://github.com/silo-finance/silo-contracts-v2/issues/217)

## [0.0.6] - 2023-11-10
### Fixed
- [Issue #216](https://github.com/silo-finance/silo-contracts-v2/issues/216)

## [0.0.5] - 2023-11-10
### Fixed
- [Issue #214](https://github.com/silo-finance/silo-contracts-v2/issues/214)

## [0.0.4] - 2023-11-10
### Fixed
- [Issue #213](https://github.com/silo-finance/silo-contracts-v2/issues/213)

## [0.0.3] - 2023-10-26
### Added
- silo-core for audit

## [0.0.2] - 2023-10-18
### Added
- silo-oracles for audit

## [0.0.1] - 2023-10-06
### Added
- ve-silo for audit
