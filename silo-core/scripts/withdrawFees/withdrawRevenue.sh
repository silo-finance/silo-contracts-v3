#!/bin/bash
#
# Top-level orchestrator for the withdrawFees pipeline.
# For every chain it runs: 1_collect_factories.py -> 2_discover_silos.py -> 3_withdraw_fees.py
#
# Usage:
#   silo-core/scripts/withdrawFees/withdrawRevenue.sh [--parallel] [--broadcast] [chain ...]
#
#   --parallel   run all chains concurrently (logs go to logs/<chain>.log)
#   --broadcast  send withdraw transactions (default is dry-run / simulation only)
#   chain ...    optional list of chain aliases (default: all known chains)
#
# A failure on one chain never aborts the others; a summary is printed at the end.
#
# Note: written to be compatible with the stock macOS bash 3.2 (no mapfile / no
# associative arrays), so it runs the same with `./withdrawRevenue.sh` everywhere.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"

py() { PYTHONPATH="${SCRIPT_DIR}" python3 "$@"; }

# chain metadata comes from _common.py (single source of truth)
chain_rpc_env() { py -c "import sys,_common;print(_common.get_chain(sys.argv[1]).rpc_env)" "$1"; }
rpc_url_for_env() { py -c "import sys,_common;print(_common.load_dotenv().get(sys.argv[1],''))" "$1"; }

PARALLEL=false
BROADCAST=false
CHAINS=()

for arg in "$@"; do
    case "$arg" in
        --parallel)  PARALLEL=true ;;
        --broadcast) BROADCAST=true ;;
        -h|--help)   sed -n '2,17p' "${BASH_SOURCE[0]}"; exit 0 ;;
        --*)         echo "Unknown flag: $arg" >&2; exit 1 ;;
        *)           CHAINS+=("$arg") ;;
    esac
done

# Default to all known chains (read line-by-line; bash 3.2 has no `mapfile`).
if [ "${#CHAINS[@]}" -eq 0 ]; then
    while IFS= read -r _chain; do
        [ -n "$_chain" ] && CHAINS+=("$_chain")
    done < <(py -c "import _common;print('\n'.join(_common.CHAINS))")
fi

if [ "${#CHAINS[@]}" -eq 0 ]; then
    echo "ERROR: no chains to process (could not read chain list from _common.py)." >&2
    exit 1
fi

echo "Chains to process (${#CHAINS[@]}): ${CHAINS[*]}"
if $BROADCAST; then
    echo "Mode: BROADCAST (sending transactions)"
else
    echo "Mode: DRY-RUN (no broadcast; pass --broadcast to send txs)"
fi
$PARALLEL && echo "Mode: PARALLEL (per-chain logs in ${LOG_DIR})"

run_chain() {
    local chain="$1"
    local env_var rpc broadcast

    echo "[$chain] ===== start ====="

    if ! env_var="$(chain_rpc_env "$chain" 2>/dev/null)"; then
        echo "[$chain] FAILED: unknown chain alias (not defined in _common.py)"
        return 1
    fi
    echo "[$chain] using RPC env var: ${env_var}"

    rpc="$(rpc_url_for_env "$env_var")"
    if [ -z "$rpc" ]; then
        echo "[$chain] FAILED: ${env_var} is empty/unset in .env (cannot reach this chain)"
        return 1
    fi

    echo "[$chain] stage 1/3: collect factories from git history"
    if ! py "${SCRIPT_DIR}/1_collect_factories.py" --chain "$chain"; then
        echo "[$chain] FAILED at stage 1/3 (collect factories)"
        return 1
    fi

    echo "[$chain] stage 2/3: discover silos via RPC"
    if ! py "${SCRIPT_DIR}/2_discover_silos.py" --chain "$chain" --rpc-url "$rpc"; then
        echo "[$chain] FAILED at stage 2/3 (discover silos)"
        return 1
    fi

    echo "[$chain] stage 3/3: withdraw fees"
    broadcast=""
    $BROADCAST && broadcast="--broadcast"
    if ! py "${SCRIPT_DIR}/3_withdraw_fees.py" --chain "$chain" --rpc-url "$rpc" \
        --summary-out "${LOG_DIR}/${chain}.withdraw_summary.json" $broadcast; then
        echo "[$chain] FAILED at stage 3/3 (withdraw fees)"
        return 1
    fi

    echo "[$chain] ===== done ====="
}

mkdir -p "$LOG_DIR"

# Parallel indexed arrays (bash 3.2 has no associative arrays): STATUS[i] / PIDS[i]
# correspond to CHAINS[i].
STATUS=()
PIDS=()
overall=0

if $PARALLEL; then
    i=0
    while [ "$i" -lt "${#CHAINS[@]}" ]; do
        chain="${CHAINS[$i]}"
        ( run_chain "$chain" ) >"${LOG_DIR}/${chain}.log" 2>&1 &
        PIDS[$i]=$!
        echo "[$chain] started (pid ${PIDS[$i]}) -> ${LOG_DIR}/${chain}.log"
        i=$((i + 1))
    done
    i=0
    while [ "$i" -lt "${#CHAINS[@]}" ]; do
        chain="${CHAINS[$i]}"
        if wait "${PIDS[$i]}"; then
            STATUS[$i]=OK
            echo "[$chain] finished: OK"
        else
            STATUS[$i]=FAIL
            echo "[$chain] finished: FAIL (see ${LOG_DIR}/${chain}.log)"
        fi
        i=$((i + 1))
    done
else
    i=0
    while [ "$i" -lt "${#CHAINS[@]}" ]; do
        chain="${CHAINS[$i]}"
        echo ""
        echo "================ ${chain} ($((i + 1))/${#CHAINS[@]}) ================"
        if run_chain "$chain" 2>&1 | tee "${LOG_DIR}/${chain}.log"; then
            STATUS[$i]=OK
        else
            STATUS[$i]=FAIL
        fi
        i=$((i + 1))
    done
fi

echo ""
echo "==================== SUMMARY ===================="
i=0
while [ "$i" -lt "${#CHAINS[@]}" ]; do
    chain="${CHAINS[$i]}"
    echo "  ${chain}: ${STATUS[$i]:-SKIPPED}"
    [ "${STATUS[$i]:-}" = "FAIL" ] && overall=1
    i=$((i + 1))
done

echo ""
echo ""
echo "==================== WITHDRAW REVENUE SUMMARY ===================="
py "${SCRIPT_DIR}/3_withdraw_fees.py" --aggregate-summaries "$LOG_DIR" "${CHAINS[@]}"
echo "================================================================="

exit $overall
