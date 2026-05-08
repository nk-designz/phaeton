#!/usr/bin/env bash
# run_cluster_3_ephemeral.sh — Start a 3-node ephemeral local cluster.
#
# Usage:
#   ./scripts/run_cluster_3_ephemeral.sh
#
# Optional env vars:
#   BASE_PORT=4000          # Web node starts here (node1)
#   NODE_PREFIX=phaeton     # Node names: <prefix>1..3
#   CLUSTER_COOKIE=phaeton_cluster_cookie
#   HOST_SHORT=<hostname>   # Defaults to `hostname -s`
#
# Notes:
# - node1 runs Phoenix server
# - node2 and node3 run headless app nodes
# - all nodes are connected to node1
# - processes are killed automatically on Ctrl+C

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_PORT="${BASE_PORT:-4000}"
NODE_PREFIX="${NODE_PREFIX:-phaeton}"
CLUSTER_COOKIE="${CLUSTER_COOKIE:-phaeton_cluster_cookie}"
HOST_SHORT="${HOST_SHORT:-$(hostname -s)}"

NODE1="${NODE_PREFIX}1"
NODE2="${NODE_PREFIX}2"
NODE3="${NODE_PREFIX}3"
NODE1_FULL="${NODE1}@${HOST_SHORT}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/phaeton-cluster-XXXXXX")"
LOG_DIR="${TMP_DIR}/logs"
mkdir -p "${LOG_DIR}"

PIDS=()

cleanup() {
  local code=$?
  echo ""
  echo "Shutting down cluster..."

  for pid in "${PIDS[@]:-}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done

  for pid in "${PIDS[@]:-}"; do
    wait "$pid" 2>/dev/null || true
  done

  rm -rf "${TMP_DIR}"
  exit "$code"
}

trap cleanup INT TERM EXIT

start_node() {
  local label="$1"
  local log_file="$2"
  shift 2

  (
    cd "${ROOT_DIR}"
    "$@"
  ) >"${log_file}" 2>&1 &

  local pid=$!
  PIDS+=("$pid")
  echo "Started ${label} (pid=${pid})"
}

echo "=== Starting 3-node ephemeral cluster ==="
echo "Project: ${ROOT_DIR}"
echo "Cookie: ${CLUSTER_COOKIE}"
echo "Host: ${HOST_SHORT}"
echo "Logs: ${LOG_DIR}"
echo ""

# Node 1: Web/API node
start_node \
  "${NODE1} (web)" \
  "${LOG_DIR}/${NODE1}.log" \
  env PORT="${BASE_PORT}" iex --sname "${NODE1}" --cookie "${CLUSTER_COOKIE}" -S mix phx.server

# Give node1 a moment to boot before peers connect
sleep 3

# Node 2: Headless peer node
start_node \
  "${NODE2} (peer)" \
  "${LOG_DIR}/${NODE2}.log" \
  iex --sname "${NODE2}" --cookie "${CLUSTER_COOKIE}" -S mix run --no-halt \
    --eval "Node.connect(:\"${NODE1_FULL}\")"

# Node 3: Headless peer node
start_node \
  "${NODE3} (peer)" \
  "${LOG_DIR}/${NODE3}.log" \
  iex --sname "${NODE3}" --cookie "${CLUSTER_COOKIE}" -S mix run --no-halt \
    --eval "Node.connect(:\"${NODE1_FULL}\")"

sleep 2

echo ""
echo "Cluster started."
echo "- Dashboard: http://localhost:${BASE_PORT}/cluster"
echo "- Node names: ${NODE1}@${HOST_SHORT}, ${NODE2}@${HOST_SHORT}, ${NODE3}@${HOST_SHORT}"
echo "- Tail logs: tail -f ${LOG_DIR}/${NODE1}.log"
echo ""
echo "Press Ctrl+C to stop all nodes."
echo ""

# Keep script running while child processes run
while true; do
  sleep 1

  for pid in "${PIDS[@]}"; do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "A node process exited unexpectedly. Check logs in ${LOG_DIR}."
      exit 1
    fi
  done
done
