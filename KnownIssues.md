## Known issues:

### Decimals

`decimals()` function in `SiloVault` and `Silo` does not add decimal offset to decimals of underlaying asset. Both contracts use decimal offset but it is not reflected in `decimals()` function return value.

SiloVault:
  decimals(): same as underlying asset
  offset: 6
  minted shares per 1 wei of asset deposited: 1000000

Silo:
  decimals(): same as underlying asset
  offset: 3
  minted shares per 1 wei of asset deposited: 1000

ProtectedShareToken:
  decimals(): same as underlying asset
  offset: 3
  minted shares per 1 wei of asset deposited: 1000

DebtShareToken:
  decimals(): same as underlying asset
  offset: 0
  shares per 1 wei of asset borrowed: 1

Learn more about the [decimal offset here](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/a7d38c7a3321e3832ca84f7ba1125dff9a91361e/contracts/token/ERC20/extensions/ERC4626.sol#L31)

The share-to-asset ratio may change over time due to interest accrual. Assets grow with interest but the number 
of shares remains constant, the ratio will adjust dynamically.

To determine the current conversion rate, use the vault’s `convertToShares(1 asset)` method.

For `SiloVault` and `Silo` `decimals()` fn return underlying asset decimals (USDC - 6, WETH - 18).

### `getProgramName()`

Silo incentives controller with version < 3.6.0 has issue with `getProgramName` fn. It fails to convert the immediate 
distribution program name (which is token address) into a proper string representation.
Eg. if token address has any zeros, they will be removed, so returned name will be incomplete.

Silos incentives controller with this issue: Sonic 1 - 101, Arbitrum 100 - 111, Optimism - 100, Ink - 100 - 101.

### Debt share tokens approval for the leverage smart contract

The leverage contract requires approval of share debt tokens so it can borrow on behalf of the user. Recent versions of the debt share token used `approve` fn for that, but it was changed in PR#1098 (Release 3.0.0), and after that change, we need to use `setReceiveApproval` fn.

Silos with id < 100 on Sonic use `approve`. All other versions use `setReceiveApproval` fn.

### Liquidation collateral overestimation

The `PartialLiquidationLib` uses a fixed `_UNDERESTIMATION` constant of 2 wei to account for rounding errors during liquidation conversions (assets → shares → assets). This underestimation becomes insufficient when the asset-to-share ratio is high and liquidation is for same asset position. We were not able to find such a case for two asset position.

During liquidation, the protocol performs two conversions that both round down:
1. Converting collateral assets to shares (rounds down)
2. Converting shares back to assets for withdrawal (rounds down)
3. Repay same asset also changes the ratio based on which `maxLiquidation` was calculated

Because of all above factors, cumulative rounding errors can exceed 2 wei. As a result, `maxLiquidation()` may overestimate the collateral to be liquidated in such cases.

**Recommendation**: Instead of comparing maxLiquidation directly with the actual liquidation result, just check whether the liquidation is profitable. This avoids failed transactions caused by a small wei-level overestimation.


### Liquidation when we have share dust

For version below 4.0.0, in an edge case where during liquidation we need to transfer shares that cannot be converted to a 1 wei of assets (e.g., 999 shares => 0 assets), liquidation will fail if `_receiveSToken` is `false`.  

Workarounds for this case are:
- deposit a dust amount of assets for the borrower for the collateral type that has dust
- or transfer shares to the borrower if you already have some

For example, with a deposit of 10 wei, it will give us ~10000 shares, so `999 + 10000 shares converts to ~ 1 assets` and liquidation will succeed.
