#!/usr/bin/env bash
# clean_broker.sh — Delete ALL data from the NGSI-LD broker
# Removes all entities, temporal records, and subscriptions
#
# Usage: ./scripts/clean_broker.sh [BASE_URL] [--token TOKEN] [--tenant TENANT]
#   BASE_URL defaults to http://localhost:4000
#
# WARNING: This is destructive and irreversible. All broker data will be wiped.

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
BATCH_SIZE=50

# ─── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLD='\033[1m'
RST='\033[0m'

echo -e ""
echo -e "${BLD}=== NGSI-LD Broker Cleaner ===${RST}"
echo -e "    Target: ${API}"
echo -e ""

# ─── Confirm ──────────────────────────────────────────────────────────────────
if [ -t 0 ]; then
  echo -e "${RED}${BLD}WARNING: This will permanently delete ALL entities, temporal records,"
  echo -e "         and subscriptions from the broker.${RST}"
  echo -e ""
  read -r -p "Type 'yes' to confirm: " confirm
  if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
  fi
  echo ""
fi

# ─── Require Python3 for JSON parsing ─────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
  echo "Error: python3 is required for JSON parsing." >&2
  exit 1
fi

# ─── Helper: extract JSON array of string values for a given key ───────────────
# Reads JSON from stdin, key passed as argument.
# Usage: echo "$json" | json_strings_for_key <key>
json_strings_for_key() {
  python3 -c "
import sys, json
data = json.load(sys.stdin)
key = sys.argv[1]
if isinstance(data, list):
    for item in data:
        v = item.get(key, '')
        if v:
            print(v)
elif isinstance(data, dict):
    v = data.get(key, '')
    if v:
        print(v)
" "$1"
}

# ─── Helper: count items in a JSON array ──────────────────────────────────────
# Reads JSON from stdin.
json_count() {
  python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d) if isinstance(d,list) else 0)"
}

# ─── Helper: print compact JSON array from newline-separated IDs ──────────────
ids_to_json_array() {
  python3 -c "
import sys, json
ids = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(ids))
"
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. DELETE ALL ENTITIES
# ─────────────────────────────────────────────────────────────────────────────
echo -e "${BLD}Step 1: Collecting all entity IDs...${RST}"

total_entities=0
offset=0
limit=1000
all_ids=()

while true; do
  response=$(curl -s -f \
    "${COMMON_HEADERS[@]+"${COMMON_HEADERS[@]}"}"\
    "${API}/entities?limit=${limit}&offset=${offset}" \
    -H "Accept: application/json" || echo "[]")

  count=$(echo "$response" | json_count)
  if [ "$count" -eq 0 ]; then
    break
  fi

  # Extract IDs and append to array
  while IFS= read -r id; do
    all_ids+=("$id")
  done < <(echo "$response" | json_strings_for_key "id")

  total_entities=$((total_entities + count))
  printf "    Collected %d entity IDs so far...\r" "$total_entities"

  if [ "$count" -lt "$limit" ]; then
    break
  fi
  offset=$((offset + limit))
done

echo ""
echo -e "    Found ${BLD}${total_entities}${RST} entities"

if [ "${#all_ids[@]}" -gt 0 ]; then
  echo -e "    Deleting in batches of ${BATCH_SIZE}..."
  deleted=0

  for (( i=0; i<${#all_ids[@]}; i+=BATCH_SIZE )); do
    batch=("${all_ids[@]:$i:$BATCH_SIZE}")
    # Build JSON array from batch
    json_body=$(printf '%s\n' "${batch[@]}" | ids_to_json_array)

    http_code=$(curl -s -o /dev/null -w '%{http_code}' \
      "${COMMON_HEADERS[@]+"${COMMON_HEADERS[@]}"}"\
      -X POST "${API}/entityOperations/delete" \
      -H "Content-Type: application/json" \
      -d "$json_body")

    deleted=$((deleted + ${#batch[@]}))
    printf "    Deleted %d / %d entities (HTTP %s)\r" "$deleted" "$total_entities" "$http_code"
  done

  echo ""
  echo -e "    ${GRN}✓ Deleted ${total_entities} entities${RST}"
else
  echo -e "    ${GRN}✓ No entities to delete${RST}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. DELETE ALL SUBSCRIPTIONS
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLD}Step 2: Collecting all subscriptions...${RST}"

sub_response=$(curl -s -f \
  "${COMMON_HEADERS[@]+"${COMMON_HEADERS[@]}"}"\
  "${API}/subscriptions?limit=1000" \
  -H "Accept: application/json" || echo "[]")

sub_ids=()
while IFS= read -r id; do
  sub_ids+=("$id")
done < <(echo "$sub_response" | json_strings_for_key "id")

total_subs=${#sub_ids[@]}
echo -e "    Found ${BLD}${total_subs}${RST} subscriptions"

if [ "${#sub_ids[@]}" -gt 0 ]; then
  deleted_subs=0
  for sub_id in "${sub_ids[@]}"; do
    encoded_id=$(printf '%s' "$sub_id" | python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read(), safe=''))")
    curl -s -o /dev/null \
      "${COMMON_HEADERS[@]+"${COMMON_HEADERS[@]}"}"\
      -X DELETE "${API}/subscriptions/${encoded_id}"
    deleted_subs=$((deleted_subs + 1))
    printf "    Deleted %d / %d subscriptions\r" "$deleted_subs" "$total_subs"
  done
  echo ""
  echo -e "    ${GRN}✓ Deleted ${total_subs} subscriptions${RST}"
else
  echo -e "    ${GRN}✓ No subscriptions to delete${RST}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. DELETE ALL TEMPORAL RECORDS
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLD}Step 3: Collecting temporal entity records...${RST}"

temporal_response=$(curl -s -f \
  "${COMMON_HEADERS[@]+"${COMMON_HEADERS[@]}"}"\
  "${API}/temporal/entities?limit=1000" \
  -H "Accept: application/json" || echo "[]")

temporal_ids=()
while IFS= read -r id; do
  temporal_ids+=("$id")
done < <(echo "$temporal_response" | json_strings_for_key "id")

total_temporal=${#temporal_ids[@]}
echo -e "    Found ${BLD}${total_temporal}${RST} temporal records"

if [ "${#temporal_ids[@]}" -gt 0 ]; then
  deleted_temporal=0
  for t_id in "${temporal_ids[@]}"; do
    encoded_id=$(printf '%s' "$t_id" | python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read(), safe=''))")
    curl -s -o /dev/null \
      "${COMMON_HEADERS[@]+"${COMMON_HEADERS[@]}"}"\
      -X DELETE "${API}/temporal/entities/${encoded_id}"
    deleted_temporal=$((deleted_temporal + 1))
    printf "    Deleted %d / %d temporal records\r" "$deleted_temporal" "$total_temporal"
  done
  echo ""
  echo -e "    ${GRN}✓ Deleted ${total_temporal} temporal records${RST}"
else
  echo -e "    ${GRN}✓ No temporal records to delete${RST}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLD}=== Clean complete ===${RST}"
echo -e "    Entities deleted:          ${total_entities}"
echo -e "    Subscriptions deleted:     ${total_subs}"
echo -e "    Temporal records deleted:  ${total_temporal}"
echo ""
