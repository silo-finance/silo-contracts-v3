#!/usr/bin/env bash
#
# Verify all deployed contracts on the selected blockchain.
# Runs forge script --verify --resume for each deploy script.
# Errors in individual scripts do not stop the whole process.
#
# Usage:
#   ./scripts/verify_all_deployments.sh
#   or after loading .env: source .env && ./scripts/verify_all_deployments.sh
#

set -euo pipefail

# =============================================================================
# CONFIGURATION - adjust before running
# =============================================================================

# RPC URL for the blockchain (can be overridden by environment variable)
RPC_URL=$RPC_INJECTIVE

# Verifier API URL (etherscan, blockscout, snowscan, etc.)
VERIFIER_URL=$VERIFIER_URL_INJECTIVE

# Verifier type: etherscan | blockscout | ...
VERIFIER="${VERIFIER:-blockscout}"

# List of deploy scripts to verify (path relative to repo root)
# Format: "path/to/ScriptDeploy.s.sol"
# You can add new ones or remove unnecessary ones.
DEPLOY_SCRIPTS=(
    # silo-core
    "silo-core/deploy/InterestRateModelV2Deploy.s.sol"
    "silo-core/deploy/DKinkIRMFactoryDeploy.s.sol"
    "silo-core/deploy/InterestRateModelV2FactoryDeploy.s.sol"
    "silo-core/deploy/MainnetDeploy.s.sol"
    "silo-core/deploy/SiloLensDeploy.s.sol"
    "silo-core/deploy/SiloImplementationDeploy.s.sol"
    "silo-core/deploy/SiloHookV1Deploy.s.sol"
    "silo-core/deploy/SiloHookV2Deploy.s.sol"
    "silo-core/deploy/SiloHookV3Deploy.s.sol"
    "silo-core/deploy/SiloFactoryDeploy.s.sol"
    "silo-core/deploy/SiloDeployerDeploy.s.sol"
    "silo-core/deploy/TowerDeploy.s.sol"
    "silo-core/deploy/SiloRouterV2Deploy.s.sol"
    "silo-core/deploy/SiloIncentivesControllerFactoryDeploy.s.sol"
    "silo-core/deploy/ManualLiquidationHelperDeploy.s.sol"
    "silo-core/deploy/LiquidationHelperDeploy.s.sol"
    "silo-core/deploy/LeverageRouterUsingSiloFlashloanWithGeneralSwapDeploy.s.sol"
    "silo-core/deploy/PendleRewardsClaimerDeploy.s.sol"
    "silo-core/deploy/GlobalPauseDeploy.s.sol"
    "silo-core/deploy/SiloCoreVerifier.s.sol"
    # silo-oracles
    "silo-oracles/deploy/MainnetDeploy.s.sol"
    "silo-oracles/deploy/SiloVirtualAsset8DecimalsDeploy.s.sol"
    # silo-vaults
    "silo-vaults/deploy/MainnetDeploy.s.sol"
    "silo-vaults/deploy/SiloVaultsFactoryDeploy.s.sol"
    "silo-vaults/deploy/SiloVaultsDeployerDeploy.s.sol"
    "silo-vaults/deploy/SiloIncentivesControllerCLFactoryDeploy.s.sol"
    "silo-vaults/deploy/SiloIncentivesControllerCLDeployerDeploy.s.sol"
    "silo-vaults/deploy/PublicAllocatorDeploy.s.sol"
    "silo-vaults/deploy/IdleVaultsFactoryDeploy.s.sol"
    "silo-vaults/deploy/SiloVaultsVerifier.s.sol"
    # x-silo
    "x-silo/deploy/XSiloDeploy.s.sol"
    "x-silo/deploy/XSiloAndStreamDeploy.s.sol"
    "x-silo/deploy/StreamDeploy.s.sol"
)

# =============================================================================
# LOGIC
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Check required variables
if [[ -z "${RPC_URL:-}" ]]; then
    echo "Error: Set RPC_URL or load .env (e.g. source .env)" >&2
    exit 1
fi
if [[ -z "${VERIFIER_URL:-}" ]]; then
    echo "Error: Set VERIFIER_URL or load .env" >&2
    exit 1
fi
if [[ -z "${PRIVATE_KEY:-}" ]]; then
    echo "Error: Set PRIVATE_KEY (e.g. in .env)" >&2
    exit 1
fi

# Map path -> FOUNDRY_PROFILE
get_profile() {
    local path="$1"
    if [[ "$path" == silo-core/* ]]; then
        echo "core"
    elif [[ "$path" == silo-oracles/* ]]; then
        echo "oracles"
    elif [[ "$path" == silo-vaults/* ]]; then
        echo "vaults"
    elif [[ "$path" == x-silo/* ]]; then
        echo "x_silo"
    else
        echo "default"
    fi
}

# Extract contract name from path (e.g. MyDeploy.s.sol -> MyDeploy)
get_contract_name() {
    local path="$1"
    local basename
    basename="$(basename "$path")"
    echo "${basename%.s.sol}"
}

echo "=== Verifying deployments ==="
echo "RPC:        $RPC_URL"
echo "Verifier:   $VERIFIER"
echo "Verifier URL: $VERIFIER_URL"
echo "Scripts:    ${#DEPLOY_SCRIPTS[@]}"
echo ""

FAILED=()
SUCCESS_COUNT=0

for script_path in "${DEPLOY_SCRIPTS[@]}"; do
    if [[ ! -f "$script_path" ]]; then
        echo "[SKIP] $script_path (file does not exist)"
        continue
    fi

    profile=$(get_profile "$script_path")
    contract=$(get_contract_name "$script_path")

    echo "----------------------------------------"
    echo "[VERIFY] $script_path (profile=$profile)"
    echo "----------------------------------------"

    if FOUNDRY_PROFILE="$profile" forge script "$script_path:$contract" \
        --ffi \
        --rpc-url "$RPC_URL" \
        --verify \
        --verifier "$VERIFIER" \
        --verifier-url "$VERIFIER_URL" \
        --private-key "$PRIVATE_KEY" \
        --resume; then
        ((SUCCESS_COUNT++)) || true
        echo "[OK] $script_path"
    else
        FAILED+=("$script_path")
        echo "[FAIL] $script_path" >&2
    fi
    echo ""
done

# Summary
echo "========================================"
echo "SUMMARY"
echo "========================================"
echo "Success: $SUCCESS_COUNT / ${#DEPLOY_SCRIPTS[@]}"

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo ""
    echo "Failed scripts:"
    for f in "${FAILED[@]}"; do
        echo "  - $f"
    done
    exit 1
fi

echo "All verifications completed successfully."
exit 0
