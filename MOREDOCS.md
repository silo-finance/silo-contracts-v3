# Silo V3

Monorepo for Silo protocol v3

## Development setup

see:

- https://yarnpkg.com/getting-started/install
- https://classic.yarnpkg.com/lang/en/docs/workspaces/

```shell
# from root dir
git clone <repo>
git hf init

nvm install 18
nvm use 18

# this is for ode 18, for other versions please check https://yarnpkg.com/getting-started/install
corepack enable
corepack prepare yarn@stable --activate

npm i -g yarn
yarn install

git config core.hooksPath .githooks/
```

### Foundry setup for monorepo

```
git submodule add --name foundry https://github.com/foundry-rs/forge-std gitmodules/forge-std
git submodule add --name silo-foundry-utils https://github.com/silo-finance/silo-foundry-utils gitmodules/silo-foundry-utils
forge install OpenZeppelin/openzeppelin-contracts --no-commit 
forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit
git submodule add --name gitmodules/uniswap/v3-periphery https://github.com/Uniswap/v3-periphery gitmodules/uniswap/v3-periphery 
git submodule add --name gitmodules/chainlink https://github.com/smartcontractkit/chainlink gitmodules/chainlink 
git submodule add --name lz_gauges https://github.com/LayerZero-Labs/lz_gauges gitmodules/lz_gauges
git submodule add --name layer-zero-examples https://github.com/LayerZero-Labs/solidity-examples gitmodules/layer-zero-examples
git submodule add --name chainlink-ccip https://github.com/smartcontractkit/ccip gitmodules/chainlink-ccip
git submodule add --name openzeppelin5 https://github.com/OpenZeppelin/openzeppelin-contracts@5.0.2 gitmodules/openzeppelin-contracts-5
git submodule add --name openzeppelin-contracts-upgradeable-5 https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable gitmodules/openzeppelin-contracts-upgradeable-5
git submodule add --name morpho-blue https://github.com/morpho-org/morpho-blue/ gitmodules/morpho-blue

git submodule update --init --recursive
git submodule
```

create `.remappings.txt` in main directory

```
forge-std/=gitmodules/forge-std/src/
```

this will make forge visible for imports eg: `import "forge-std/Test.sol"`.

### Build Silo Foundry Utils
```bash
cd gitmodules/silo-foundry-utils
git pull
cargo build --release
cp target/release/silo-foundry-utils ../../silo-foundry-utils
cd -
./silo-foundry-utils --version
```

More about silo foundry utils [here](https://github.com/silo-finance/silo-foundry-utils).

### Remove submodule

example:

```shell
# Remove the submodule entry from .git/config
git submodule deinit -f gitmodules/silo-foundry-utils

# Remove the submodule directory from the super project's .git/modules directory
rm -rf .git/modules/gitmodules/silo-foundry-utils

# Remove the entry in .gitmodules and remove the submodule directory located at path/to/submodule
rm -rf .git/modules/gitmodules/silo-foundry-utils
```

### Update submodule
```shell
git submodule update --remote gitmodules/<submodule>
```

If you want to update to specific commit:
1. cd `gitmodules/<module>`
2. `git checkout <commit>`
3. commit changes (optionally update `branch` section in `.gitmodules`, however this make no difference)

## Adding new working space

- create new workflow in `.github/workflows`
- create new directory `mkdir new-dir` with content
- create new profile in `.foundry.toml`
- add new workspace in `package.json` `workspaces` section
- run `yarn reinstall`

## Cloning external code

- In `external/` create subdirectory for cloned code eg `uniswap-v3-core/`
- clone git repo into that directory

**NOTICE**: do not run `yarn install` directly from workspace directory. It will create separate `yarn.lock` and it will
act like separate repo, not part of monorepo. It will cause issues when trying to access other workspaces eg as
dependency.
- you need to remove `./git` directories in order to commit cloned code
- update `external/package.json#workspaces` with this new `uniswap-v3-core`
- update `external/uniswap-v3-core/package.json#name` to match dir name, in our example `uniswap-v3-core`

Run `yarn install`, enter your new cloned workspace, and you should be able to execute commands for this new workspace.

example of running scripts for workspace:

```shell
yarn workspace <workspaceName> <commandName> ...
```

## Coverage Report


```shell
brew install lcov

rm lcov.info
mkdir coverage

AGGREGATOR=1INCH FOUNDRY_PROFILE=core_with_test forge coverage --report summary --report lcov --gas-price 1 --ffi --gas-limit 40000000000 --no-match-test "_skip_|_gas_|_anvil_" --nmc "SiloLensCompatibilityTest|NewMarketTest" > coverage/silo-core.log

 cat coverage/silo-core.log | grep -i 'silo-core/contracts/' | grep -v -E '/(test|deploy|silo-oracles)/' > coverage/silo-core.txt
 genhtml --ignore-errors inconsistent --ignore-errors range --exclude 'silo-oracles/*' --exclude '*/test/*' --exclude '*/deploy/*' -o coverage/silo-core/ lcov.info

rm lcov.info
FOUNDRY_PROFILE=oracles forge coverage --report summary --report lcov | grep -i 'silo-oracles/contracts/' > coverage/silo-oracles.log
cat coverage/silo-oracles.log | grep -i 'silo-oracles/contracts/' | grep -v -E '/(test|deploy|common|silo-core)/' > coverage/silo-oracles.txt
genhtml --ignore-errors inconsistent --ignore-errors range --exclude 'silo-core/*' --exclude 'common/*' --exclude '*/test/*' --exclude '*/deploy/*' -o coverage/silo-oracles/ lcov.info

rm lcov.info
FOUNDRY_PROFILE=vaults_with_tests forge coverage --report summary --report lcov --gas-price 1 --ffi --gas-limit 40000000000
cat coverage/silo-vaults.log | grep -i 'silo-vaults/contracts/' | grep -v -E '/(test|deploy|common|mocks|silo-core|silo-oracles)/' > coverage/silo-vaults.txt
genhtml --ignore-errors inconsistent --ignore-errors range --exclude 'silo-core/*' --exclude 'silo-oracles/*' --exclude 'common/*' --exclude '*/mocks/*' --exclude '*/test/*' --exclude '*/deploy/*' -o coverage/silo-vaults/ lcov.info
```

## Rounding policy

Check `Rounding.sol` for rounding policy.

## Setup Echidna

- https://github.com/crytic/echidna
- https://github.com/crytic/properties

```shell
brew install echidna
git submodule add --name crytic-properties https://github.com/crytic/properties gitmodules/crytic/properties


# before you can run any echidna tests, run the script:
./silo-core/scripts/echidnaBefore.sh
# after you done run this to revert changes:
./silo-core/scripts/echidnaAfter.sh
```

## Gas

```shell
# generate snapshot file
FOUNDRY_PROFILE=core_test forge snapshot --desc --no-match-test "_skip_" --no-match-contract "SiloIntegrationTest" --ffi
# check gas difference
FOUNDRY_PROFILE=core_test forge snapshot --desc --check --no-match-test "_skip_" --no-match-contract "SiloIntegrationTest" --ffi
# better view, with % change
FOUNDRY_PROFILE=core_test forge snapshot --diff --desc --no-match-test "_skip_" --no-match-contract "SiloIntegrationTest" --ffi
```

## Auditing tools 

### Echidna

https://github.com/crytic/echidna

### Slither

https://github.com/crytic/slither

- slither is installed by default with echidna
- for `dot` preview use `brew install graphviz`
- try different [print engines](https://github.com/crytic/slither/wiki/Printer-documentation) eg `slither ./silo-core/contracts/hooks/SiloHookV2.sol --print <printer>`
- check `audits/scripts/generate_call_graphs.py`

## Deployment

### Silo Core
1. set env variable `PRIVATE_KEY` then run
1. some adjustment is needed for new blockchain, I will use `Injective` as example:
  - update silo utils to add new blockchain
  - create `common/addresses/injective.json` and add necessary addresses
  - add necessary keys `common/addresses/AddrKey.sol`
1. run `silo-core/deploy/SiloFactoryDeploy.s.sol`
1. run `silo-core/deploy/SiloImplementationDeploy.s.sol`
1. run [MainnetDeploy.sol](silo-core/deploy/MainnetDeploy.s.sol) script
1. update onchain registry `silo-core/deploy/TowerRegistration.s.sol`
1. deploy any test market, to confirm everything is ok.

#### New SiloDeployer with Silo, ProtectedShareToken, and DebtShareToken implementations
SiloDeployer is deployed using `MainnetDeploy` script. In case you need to redeploy:
- run `silo-core/deploy/SiloDeployerDeploy.s.sol` script
- then deploy new market

### Silo Vaults
1. run `silo-vaults/deploy/MainnetDeploy.s.sol`

### Oracles
Choose oracle you want to deploy and ruch each deployer individually.

## Flat Standard JSON script

We have a Flat Standard JSON download script: `scripts/get_standard_json.py` (internally referred to as `script-get-standard-json`), created for OKX blockchain needs. It lets us fetch Standard JSON from Arbitrum and use it to verify the contract on another chain.

Example:
```bash
python3 scripts/get_standard_json.py --network arbitrum_one --address 0xA8C5eb9ae9c7a8fab4116d1e9c1FCfc8A478b390
```
