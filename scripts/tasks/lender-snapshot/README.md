# Lender snapshot (Trevee)

Builds a block-pinned snapshot of all lenders of a single Silo, splitting them into:

- **direct lenders** – every account holding collateral and/or protected shares of the Silo, and
- **SiloVault depositors** – holders of any SiloVault that itself lends into the Silo, attributed by their share of the vault.

Redeemable `assets` per address are computed purely via on-chain `previewRedeem` at the snapshot block. The subgraph is only used to enumerate addresses (lenders of the Silo and depositors of each vault). The result is a single, incrementally-updated, per-chain JSON file.

## Layout

- `snapshot_lenders.py` – main script that produces `distribution_snapshot.json`.
- `qa_check.py` – pure-JSON validator (no RPC/graph) that asserts share-sum invariants against the stored total supplies.
- `requirements.txt` – Python dependencies (`web3`).
- `.env.example` – template for the required secrets.

## Configuration

Non-secret parameters are hardcoded near the top of `snapshot_lenders.py`:

- `BLOCK`, `SILO_ADDRESS`, `CHAIN`, `CHAIN_ID`
- `SUBGRAPH_URL` (public subgraph id), `OUTPUT_JSON`
- `MULTICALL3` address and `MULTICALL_BATCH`

Secrets are read **only** from the environment (or a local, gitignored `.env`):

- `RPC_URL` – archive RPC endpoint (must support `eth_call` at the historical block).
- `THE_GRAPH_API_KEY` – The Graph gateway Bearer token.

```bash
cp scripts/tasks/lender-snapshot/.env.example scripts/tasks/lender-snapshot/.env
# edit .env and fill RPC_URL and THE_GRAPH_API_KEY
```

The script auto-loads `scripts/tasks/lender-snapshot/.env` if present; you can also export the variables in your shell.

## Usage

```bash
python3 -m pip install -r scripts/tasks/lender-snapshot/requirements.txt

# Produce / refresh the snapshot for the configured Silo:
python3 scripts/tasks/lender-snapshot/snapshot_lenders.py

# Validate the JSON invariants (zero tolerance, exact wei equality):
python3 scripts/tasks/lender-snapshot/qa_check.py

# Optionally re-confirm stored total supplies against the chain:
python3 scripts/tasks/lender-snapshot/qa_check.py --verify-onchain
```

Re-running for the same Silo **overwrites** that Silo's entry under its chain key; other Silos and other chains are preserved.

## Performance

All historical reads are batched through Multicall3 (`aggregate3` with `allowFailure=true`) via `eth_call` pinned at `BLOCK`. `eth_getCode` (used for contract detection) cannot go through Multicall3 and is issued in JSON-RPC batches instead.

## Output shape

```jsonc
{
  "<chain>": {
    "chain_id": 146,
    "silos": {
      "<silo_address>": {
        "snapshot_block": 54144258,
        "input_token": { "address": "0x..", "decimals": 6 },
        "protected_share_token": "0x..",
        "collateral_total_supply": "…",   // raw integer string
        "protected_total_supply": "…",
        "direct_lenders": {
          "<addr>": {
            "address_type": "eoa|silo_vault|erc4626_unresolved|contract_other",
            "collateral_shares": "…",
            "protected_shares": "…",
            "assets_collateral": "…",
            "assets_protected": "…",
            "total_assets": "…"
          }
        },
        "vaults": {
          "<vault_addr>": {
            "name": "…",
            "indexed_in_subgraph": true,
            "in_withdraw_queue": true,
            "status": "ok|vault_not_indexed|not_in_withdraw_queue",
            "vault_silo_assets": "…",
            "vault_total_supply": "…",
            "depositors": {
              "<addr>": {
                "address_type": "…",
                "vault_shares": "…",
                "fraction": "0.1234",
                "attributed_silo_assets": "…"
              }
            }
          }
        }
      }
    }
  }
}
```

All share/supply amounts are raw integers (as strings, to preserve precision), expressed in the same units as the corresponding `totalSupply`, so that sums match exactly.

## QA invariants

`qa_check.py` enforces, with **zero tolerance** (exact equality to 1 wei):

- `sum(direct_lenders[].collateral_shares) == collateral_total_supply`
- `sum(direct_lenders[].protected_shares) == protected_total_supply`
- for each indexed vault with `in_withdraw_queue == true`: `sum(depositors[].vault_shares) == vault_total_supply`

Vaults with `status == vault_not_indexed` or `in_withdraw_queue == false` are reported as warnings (their depositors are intentionally not enumerated), not errors.
