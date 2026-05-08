#!/usr/bin/env bash
# simulate_farm.sh — Continuously update the 5 farm entities with random sensor values
#
# Usage: ./scripts/simulate_farm.sh [BASE_URL] [--token TOKEN] [--tenant TENANT]
#   BASE_URL defaults to http://localhost:4000
#   Press Ctrl+C to stop

set -euo pipefail

BASE_URL="http://localhost:4000"
TOKEN=""
TENANT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --token)  TOKEN="$2";  shift 2 ;;
    --tenant) TENANT="$2"; shift 2 ;;
    --*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) BASE_URL="$1"; shift ;;
  esac
done

API="${BASE_URL}/ngsi-ld/v1"
COMMON_HEADERS=()
[[ -n "$TOKEN"  ]] && COMMON_HEADERS+=(-H "Authorization: Bearer $TOKEN")
[[ -n "$TENANT" ]] && COMMON_HEADERS+=(-H "NGSILD-Tenant: $TENANT")
INTERVAL=5

echo "=== IoT Grape Vertical Farm Simulator ==="
echo "    Target: ${API}"
echo "    Interval: ${INTERVAL}s"
echo "    Press Ctrl+C to stop"
echo ""

# Helper: random float between min and max (2 decimal places)
rand_float() {
  local min=$1 max=$2
  awk "BEGIN{srand(); printf \"%.2f\", $min + rand() * ($max - $min)}"
}

# Helper: random int between min and max
rand_int() {
  local min=$1 max=$2
  shuf -i "${min}-${max}" -n 1
}

cycle=0

while true; do
  cycle=$((cycle + 1))
  NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # --- TemperatureSensor: temperature drifts 18-28°C, battery slowly drains ---
  TEMP=$(rand_float 18.0 28.0)
  BATT_T=$(rand_int 50 100)
  curl -s -o /dev/null -w "" \
    "${COMMON_HEADERS[@]+"${COMMON_HEADERS[@]}"}"\
    -X PATCH "${API}/entities/urn:ngsi-ld:TemperatureSensor:Z01R01L1/attrs" \
    -H "Content-Type: application/json" \
    -d "{
      \"temperature\": {\"type\": \"Property\", \"value\": ${TEMP}, \"unitCode\": \"CEL\", \"observedAt\": \"${NOW}\"},
      \"batteryLevel\": {\"type\": \"Property\", \"value\": ${BATT_T}, \"unitCode\": \"P1\"}
    }"

  # --- HumiditySensor: humidity drifts 45-85%, battery drains ---
  HUM=$(rand_float 45.0 85.0)
  BATT_H=$(rand_int 40 100)
  curl -s -o /dev/null -w "" \
    "${COMMON_HEADERS[@]+"${COMMON_HEADERS[@]}"}"\
    -X PATCH "${API}/entities/urn:ngsi-ld:HumiditySensor:Z01R01L1/attrs" \
    -H "Content-Type: application/json" \
    -d "{
      \"relativeHumidity\": {\"type\": \"Property\", \"value\": ${HUM}, \"unitCode\": \"P1\", \"observedAt\": \"${NOW}\"},
      \"batteryLevel\": {\"type\": \"Property\", \"value\": ${BATT_H}, \"unitCode\": \"P1\"}
    }"

  # --- GrapeShelf: health score fluctuates, growth stage cycles ---
  HEALTH=$(rand_float 70.0 99.0)
  PLANTS=$(rand_int 6 12)
  STAGES=("germination" "vegetative" "flowering" "fruit-set" "veraison" "ripening")
  STAGE_IDX=$(( (cycle / 20) % 6 ))
  STAGE=${STAGES[$STAGE_IDX]}
  curl -s -o /dev/null -w "" \
    "${COMMON_HEADERS[@]+"${COMMON_HEADERS[@]}"}"\
    -X PATCH "${API}/entities/urn:ngsi-ld:GrapeShelf:Z01R01L1/attrs" \
    -H "Content-Type: application/json" \
    -d "{
      \"healthScore\": {\"type\": \"Property\", \"value\": ${HEALTH}, \"unitCode\": \"P1\"},
      \"plantCount\": {\"type\": \"Property\", \"value\": ${PLANTS}},
      \"growthStage\": {\"type\": \"Property\", \"value\": \"${STAGE}\"}
    }"

  # --- ZoneController: mode toggles, status updates ---
  MODES=("auto" "manual" "eco" "boost")
  MODE_IDX=$(( (cycle / 30) % 4 ))
  MODE=${MODES[$MODE_IDX]}
  STATUSES=("active" "active" "active" "idle" "calibrating")
  STATUS_IDX=$(rand_int 0 4)
  STATUS=${STATUSES[$STATUS_IDX]}
  curl -s -o /dev/null -w "" \
    "${COMMON_HEADERS[@]+"${COMMON_HEADERS[@]}"}"\
    -X PATCH "${API}/entities/urn:ngsi-ld:ZoneController:Zone01/attrs" \
    -H "Content-Type: application/json" \
    -d "{
      \"mode\": {\"type\": \"Property\", \"value\": \"${MODE}\"},
      \"status\": {\"type\": \"Property\", \"value\": \"${STATUS}\"}
    }"

  # --- GrapeVariety: optimal ranges shift slightly (simulating seasonal adjustment) ---
  OPT_TEMP=$(rand_float 19.0 24.0)
  OPT_HUM=$(rand_float 55.0 75.0)
  curl -s -o /dev/null -w "" \
    "${COMMON_HEADERS[@]+"${COMMON_HEADERS[@]}"}"\
    -X PATCH "${API}/entities/urn:ngsi-ld:GrapeVariety:PinotNoir/attrs" \
    -H "Content-Type: application/json" \
    -d "{
      \"optimalTemp\": {\"type\": \"Property\", \"value\": ${OPT_TEMP}, \"unitCode\": \"CEL\"},
      \"optimalHumidity\": {\"type\": \"Property\", \"value\": ${OPT_HUM}, \"unitCode\": \"P1\"}
    }"

  # Print status line
  printf "\r  [#%04d] T=%.1f°C  H=%.1f%%  HP=%.1f  Mode=%s  Stage=%s   " \
    "$cycle" "$TEMP" "$HUM" "$HEALTH" "$MODE" "$STAGE"

  sleep "$INTERVAL"
done
