#!/usr/bin/env bash
# seed_vertical_farm.sh — IoT Grape Vertical Farm — entities + temporal data in one pass
#
# Entity breakdown (100 total):
#    5  GrapeVariety         2  FertilizerBatch     3  AlertRule
#    2  ZoneController       2  HarvestRobot        2  EnergyMeter
#    2  ClimateSensor        2  WaterTank
#   10  LightController     10  IrrigationValve
#   20  GrapeShelf          20  TemperatureSensor   20  HumiditySensor
# ─── = 100
#
# Temporal: 24 h of temperature + humidity at 15-min intervals for all shelf sensors
#
# Usage: ./scripts/seed_vertical_farm.sh [BASE_URL] [HOURS] [INTERVAL_MINUTES]
#   BASE_URL          defaults to http://localhost:4000
#   HOURS             defaults to 24
#   INTERVAL_MINUTES  defaults to 15
#
# Set SKIP_TEMPORAL=1 to skip temporal seeding (entities only)

set -euo pipefail

BASE_URL="http://localhost:4000"
HOURS="24"
INTERVAL="15"
TOKEN=""
TENANT=""
_positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --token)  TOKEN="$2";  shift 2 ;;
    --tenant) TENANT="$2"; shift 2 ;;
    --*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) _positional+=("$1"); shift ;;
  esac
done
[[ ${#_positional[@]} -ge 1 ]] && BASE_URL="${_positional[0]}"
[[ ${#_positional[@]} -ge 2 ]] && HOURS="${_positional[1]}"
[[ ${#_positional[@]} -ge 3 ]] && INTERVAL="${_positional[2]}"
SKIP_TEMPORAL="${SKIP_TEMPORAL:-0}"

API="${BASE_URL}/ngsi-ld/v1"
COMMON_HEADERS=()
[[ -n "$TOKEN"  ]] && COMMON_HEADERS+=(-H "Authorization: Bearer $TOKEN")
[[ -n "$TENANT" ]] && COMMON_HEADERS+=(-H "NGSILD-Tenant: $TENANT")
BATCH_SIZE=50
TOTAL=100

ZONES=2
RACKS_PER_ZONE=5
LEVELS_PER_RACK=2

VARIETIES=("PinotNoir" "Chardonnay" "Merlot" "CabernetSauvignon" "Riesling")
FERT_NAMES=("MacroNPK" "CalMag")
ALERT_NAMES=("TempHigh" "HumidityLow" "SoilDry")

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
entities=()
count=0

flush_batch() {
  if [ ${#entities[@]} -eq 0 ]; then return; fi
  local payload
  payload=$(printf '%s' "[$(IFS=,; echo "${entities[*]}")]")
  local http_code
  http_code=$(curl -s -o /dev/null -w '%{http_code}' \
    "${COMMON_HEADERS[@]+"${COMMON_HEADERS[@]}"}"\
    -X POST "${API}/entityOperations/upsert" \
    -H "Content-Type: application/json" \
    -d "${payload}")
  if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
    printf "\r  Upserted %d / %d entities (HTTP %s)" "$count" "$TOTAL" "$http_code"
  else
    printf "\n  WARNING: batch at %d returned HTTP %s\n" "$count" "$http_code"
  fi
  entities=()
}

add_entity() {
  entities+=("$1")
  count=$((count + 1))
  if [ ${#entities[@]} -ge $BATCH_SIZE ]; then
    flush_batch
  fi
}

randf() {
  awk -v min="$1" -v max="$2" -v seed="$RANDOM" \
    'BEGIN{srand(seed); printf "%.2f", min + rand() * (max - min)}'
}

randi() {
  awk -v min="$1" -v max="$2" -v seed="$RANDOM" \
    'BEGIN{srand(seed); printf "%d", min + int(rand() * (max - min + 1))}'
}

ts_minutes_ago() {
  local mins_ago=$1
  if date --version >/dev/null 2>&1; then
    date -u -d "${mins_ago} minutes ago" +"%Y-%m-%dT%H:%M:%SZ"
  else
    date -u -v-"${mins_ago}"M +"%Y-%m-%dT%H:%M:%SZ"
  fi
}

sensor_value() {
  local base=$1 amplitude=$2 minute_offset=$3 noise_range=$4
  local period=1440
  local phase sine cycle noise
  phase=$(echo "scale=6; (${minute_offset} % ${period}) / ${period} * 6.2832 - 1.5708" | bc -l)
  sine=$(echo "scale=6; s(${phase})" | bc -l)
  cycle=$(echo "scale=2; ${amplitude} * ${sine}" | bc -l)
  noise=$(echo "scale=2; (${RANDOM} % 100) / 100 * ${noise_range} - (${noise_range} / 2)" | bc -l)
  echo "scale=2; ${base} + ${cycle} + ${noise}" | bc -l
}

TOTAL_POINTS=$(( (HOURS * 60) / INTERVAL ))

echo "=== IoT Grape Vertical Farm Seeder ==="
echo "    Target:   ${TOTAL} entities -> ${API}"
if [ "$SKIP_TEMPORAL" = "0" ]; then
  echo "    Temporal: ${HOURS}h at ${INTERVAL}min intervals (${TOTAL_POINTS} pts/sensor x $((ZONES * RACKS_PER_ZONE * LEVELS_PER_RACK * 2)) sensors)"
fi
echo ""

# -----------------------------------------
# 1. Grape Varieties (5)
# -----------------------------------------
echo "Creating grape varieties..."
for i in "${!VARIETIES[@]}"; do
  variety="${VARIETIES[$i]}"
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:GrapeVariety:${variety}",
  "type": "GrapeVariety",
  "name": {"type": "Property", "value": "${variety}"},
  "color": {"type": "Property", "value": "$(echo red white red red white | cut -d' ' -f$((i+1)))"},
  "optimalTemp": {"type": "Property", "value": $(randf 18 24), "unitCode": "CEL"},
  "optimalHumidity": {"type": "Property", "value": $(randf 55 75), "unitCode": "P1"},
  "growthCycleDays": {"type": "Property", "value": $(randi 90 150)},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
done

# -----------------------------------------
# 2. Fertilizer Batches (2)
# -----------------------------------------
echo "Creating fertilizer batches..."
for i in "${!FERT_NAMES[@]}"; do
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:FertilizerBatch:${FERT_NAMES[$i]}",
  "type": "FertilizerBatch",
  "name": {"type": "Property", "value": "${FERT_NAMES[$i]}"},
  "concentration": {"type": "Property", "value": $(randf 0.5 5.0), "unitCode": "GL"},
  "remainingVolume": {"type": "Property", "value": $(randf 50 500), "unitCode": "LTR"},
  "lastRefilled": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
done

# -----------------------------------------
# 3. Alert Rules (3)
# -----------------------------------------
echo "Creating alert rules..."
thresholds=("30.0" "40.0" "20.0")
units=("CEL" "P1" "P1")
severities=("critical" "warning" "warning")
for i in "${!ALERT_NAMES[@]}"; do
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:AlertRule:${ALERT_NAMES[$i]}",
  "type": "AlertRule",
  "name": {"type": "Property", "value": "${ALERT_NAMES[$i]}"},
  "threshold": {"type": "Property", "value": ${thresholds[$i]}, "unitCode": "${units[$i]}"},
  "severity": {"type": "Property", "value": "${severities[$i]}"},
  "enabled": {"type": "Property", "value": true}
}
JSON
)"
done

# -----------------------------------------
# 4. Zone infrastructure (ZoneController, HarvestRobot, EnergyMeter, ClimateSensor, WaterTank)
# -----------------------------------------
echo "Creating zone infrastructure..."
for z in $(seq 1 $ZONES); do
  zpad=$(printf "%02d" "$z")
  variety="${VARIETIES[$((z - 1))]}"

  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:ZoneController:Zone${zpad}",
  "type": "ZoneController",
  "zoneName": {"type": "Property", "value": "Zone ${zpad}"},
  "status": {"type": "Property", "value": "active"},
  "mode": {"type": "Property", "value": "auto"},
  "targetVariety": {"type": "Relationship", "object": "urn:ngsi-ld:GrapeVariety:${variety}"},
  "operatingSince": {"type": "Property", "value": "${NOW}"}
}
JSON
)"

  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:HarvestRobot:Zone${zpad}",
  "type": "HarvestRobot",
  "status": {"type": "Property", "value": "idle"},
  "batteryLevel": {"type": "Property", "value": $(randi 60 100), "unitCode": "P1"},
  "harvestCount": {"type": "Property", "value": $(randi 0 500)},
  "assignedZone": {"type": "Relationship", "object": "urn:ngsi-ld:ZoneController:Zone${zpad}"},
  "lastMaintenance": {"type": "Property", "value": "${NOW}"}
}
JSON
)"

  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:EnergyMeter:Zone${zpad}",
  "type": "EnergyMeter",
  "powerConsumption": {"type": "Property", "value": $(randf 1.5 8.0), "unitCode": "KWH", "observedAt": "${NOW}"},
  "dailyTotal": {"type": "Property", "value": $(randf 30 120), "unitCode": "KWH"},
  "monitorsZone": {"type": "Relationship", "object": "urn:ngsi-ld:ZoneController:Zone${zpad}"}
}
JSON
)"

  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:ClimateSensor:Zone${zpad}",
  "type": "ClimateSensor",
  "temperature": {"type": "Property", "value": $(randf 18 28), "unitCode": "CEL", "observedAt": "${NOW}"},
  "humidity": {"type": "Property", "value": $(randf 50 85), "unitCode": "P1", "observedAt": "${NOW}"},
  "co2Level": {"type": "Property", "value": $(randi 400 1200), "unitCode": "PPM", "observedAt": "${NOW}"},
  "inZone": {"type": "Relationship", "object": "urn:ngsi-ld:ZoneController:Zone${zpad}"}
}
JSON
)"

  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:WaterTank:Zone${zpad}",
  "type": "WaterTank",
  "waterLevel": {"type": "Property", "value": $(randf 30 100), "unitCode": "P1", "observedAt": "${NOW}"},
  "temperature": {"type": "Property", "value": $(randf 15 22), "unitCode": "CEL"},
  "pH": {"type": "Property", "value": $(randf 5.5 7.0)},
  "ec": {"type": "Property", "value": $(randf 1.0 3.0), "unitCode": "D10"},
  "servesZone": {"type": "Relationship", "object": "urn:ngsi-ld:ZoneController:Zone${zpad}"}
}
JSON
)"
done

# -----------------------------------------
# 5. Per-rack: LightController + IrrigationValve
# -----------------------------------------
echo "Creating rack equipment..."
for z in $(seq 1 $ZONES); do
  zpad=$(printf "%02d" "$z")
  for r in $(seq 1 $RACKS_PER_ZONE); do
    rpad=$(printf "%02d" "$r")
    rid="Z${zpad}R${rpad}"

    add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:LightController:${rid}",
  "type": "LightController",
  "intensity": {"type": "Property", "value": $(randi 0 100), "unitCode": "P1", "observedAt": "${NOW}"},
  "spectrum": {"type": "Property", "value": "full-spectrum"},
  "photoperiodHours": {"type": "Property", "value": $(randi 12 18)},
  "ppfd": {"type": "Property", "value": $(randi 200 800), "unitCode": "UMOL"},
  "onRack": {"type": "Relationship", "object": "urn:ngsi-ld:ZoneController:Zone${zpad}"}
}
JSON
)"

    add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:IrrigationValve:${rid}",
  "type": "IrrigationValve",
  "flowRate": {"type": "Property", "value": $(randf 0 5.0), "unitCode": "LTR", "observedAt": "${NOW}"},
  "status": {"type": "Property", "value": "closed"},
  "totalDispensed": {"type": "Property", "value": $(randf 10 500), "unitCode": "LTR"},
  "feedsFrom": {"type": "Relationship", "object": "urn:ngsi-ld:WaterTank:Zone${zpad}"}
}
JSON
)"
  done
done

# -----------------------------------------
# 6. Per-shelf: GrapeShelf + TemperatureSensor + HumiditySensor
# -----------------------------------------
echo "Creating shelf sensors..."
for z in $(seq 1 $ZONES); do
  zpad=$(printf "%02d" "$z")
  variety="${VARIETIES[$((z - 1))]}"
  for r in $(seq 1 $RACKS_PER_ZONE); do
    rpad=$(printf "%02d" "$r")
    for lv in $(seq 1 $LEVELS_PER_RACK); do
      sid="Z${zpad}R${rpad}L${lv}"

      add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:GrapeShelf:${sid}",
  "type": "GrapeShelf",
  "shelfLevel": {"type": "Property", "value": ${lv}},
  "plantCount": {"type": "Property", "value": $(randi 4 12)},
  "growthStage": {"type": "Property", "value": "vegetative"},
  "healthScore": {"type": "Property", "value": $(randf 70 100), "unitCode": "P1"},
  "grapeVariety": {"type": "Relationship", "object": "urn:ngsi-ld:GrapeVariety:${variety}"},
  "managedBy": {"type": "Relationship", "object": "urn:ngsi-ld:ZoneController:Zone${zpad}"}
}
JSON
)"

      add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:TemperatureSensor:${sid}",
  "type": "TemperatureSensor",
  "temperature": {"type": "Property", "value": $(randf 16 30), "unitCode": "CEL", "observedAt": "${NOW}"},
  "accuracy": {"type": "Property", "value": 0.5, "unitCode": "CEL"},
  "batteryLevel": {"type": "Property", "value": $(randi 20 100), "unitCode": "P1"},
  "monitorsShelf": {"type": "Relationship", "object": "urn:ngsi-ld:GrapeShelf:${sid}"}
}
JSON
)"

      add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:HumiditySensor:${sid}",
  "type": "HumiditySensor",
  "relativeHumidity": {"type": "Property", "value": $(randf 40 90), "unitCode": "P1", "observedAt": "${NOW}"},
  "accuracy": {"type": "Property", "value": 2.0, "unitCode": "P1"},
  "batteryLevel": {"type": "Property", "value": $(randi 20 100), "unitCode": "P1"},
  "monitorsShelf": {"type": "Relationship", "object": "urn:ngsi-ld:GrapeShelf:${sid}"}
}
JSON
)"
    done
  done
done

flush_batch

echo ""
echo ""
echo "=== Entities done: ${count} / ${TOTAL} created ==="
echo ""

# =========================================
# TEMPORAL DATA
# =========================================
if [ "$SKIP_TEMPORAL" = "1" ]; then
  echo "Skipping temporal seeding (SKIP_TEMPORAL=1)"
  exit 0
fi

echo "=== Seeding temporal data ==="
echo "    ${HOURS}h at ${INTERVAL}min intervals -- ${TOTAL_POINTS} points per sensor"
echo ""

for z in $(seq 1 $ZONES); do
  zpad=$(printf "%02d" "$z")
  for r in $(seq 1 $RACKS_PER_ZONE); do
    rpad=$(printf "%02d" "$r")
    for lv in $(seq 1 $LEVELS_PER_RACK); do
      sid="Z${zpad}R${rpad}L${lv}"

      # -- TemperatureSensor --
      printf "  TemperatureSensor:%-12s" "${sid}"
      temp_batch="["
      batch_count=0
      for (( i=TOTAL_POINTS-1; i>=0; i-- )); do
        mins_ago=$(( i * INTERVAL ))
        ts=$(ts_minutes_ago "$mins_ago")
        temp=$(sensor_value 22.0 3.0 "$mins_ago" 1.0)
        [ "$batch_count" -gt 0 ] && temp_batch="${temp_batch},"
        temp_batch="${temp_batch}{\"type\":\"Property\",\"value\":${temp},\"unitCode\":\"CEL\",\"observedAt\":\"${ts}\",\"instanceId\":\"urn:ngsi-ld:ti:${sid}:${i}\"}"
        batch_count=$((batch_count + 1))
        if [ "$batch_count" -ge "$BATCH_SIZE" ] || [ "$i" -eq 0 ]; then
          temp_batch="${temp_batch}]"
          http_code=$(curl -s -o /dev/null -w '%{http_code}' \
            "${COMMON_HEADERS[@]+"${COMMON_HEADERS[@]}"}"\
            -X POST "${API}/temporal/entities" \
            -H "Content-Type: application/json" \
            -d "{\"id\":\"urn:ngsi-ld:TemperatureSensor:${sid}\",\"type\":\"TemperatureSensor\",\"temperature\":${temp_batch}}")
          [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ] && \
            printf "\n  WARNING: temp %s HTTP %s\n" "$sid" "$http_code"
          temp_batch="["
          batch_count=0
        fi
      done
      printf " [temp ok]\n"

      # -- HumiditySensor --
      printf "  HumiditySensor:%-14s" "${sid}"
      humid_batch="["
      batch_count=0
      for (( i=TOTAL_POINTS-1; i>=0; i-- )); do
        mins_ago=$(( i * INTERVAL ))
        ts=$(ts_minutes_ago "$mins_ago")
        humid=$(sensor_value 64.0 -5.0 "$mins_ago" 4.0)
        [ "$batch_count" -gt 0 ] && humid_batch="${humid_batch},"
        humid_batch="${humid_batch}{\"type\":\"Property\",\"value\":${humid},\"unitCode\":\"P1\",\"observedAt\":\"${ts}\",\"instanceId\":\"urn:ngsi-ld:hi:${sid}:${i}\"}"
        batch_count=$((batch_count + 1))
        if [ "$batch_count" -ge "$BATCH_SIZE" ] || [ "$i" -eq 0 ]; then
          humid_batch="${humid_batch}]"
          http_code=$(curl -s -o /dev/null -w '%{http_code}' \
            "${COMMON_HEADERS[@]+"${COMMON_HEADERS[@]}"}"\
            -X POST "${API}/temporal/entities" \
            -H "Content-Type: application/json" \
            -d "{\"id\":\"urn:ngsi-ld:HumiditySensor:${sid}\",\"type\":\"HumiditySensor\",\"relativeHumidity\":${humid_batch}}")
          [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ] && \
            printf "\n  WARNING: humid %s HTTP %s\n" "$sid" "$http_code"
          humid_batch="["
          batch_count=0
        fi
      done
      printf " [humid ok]\n"

    done
  done
done

SENSOR_COUNT=$(( ZONES * RACKS_PER_ZONE * LEVELS_PER_RACK * 2 ))
echo ""
echo "=== All done! ==="
echo "    Entities: ${count} / ${TOTAL}"
echo "    Temporal: ${SENSOR_COUNT} sensors x ${TOTAL_POINTS} points = $((SENSOR_COUNT * TOTAL_POINTS)) time-series records"
echo ""
echo "    Charts: ${BASE_URL}/charts?entity=urn:ngsi-ld:TemperatureSensor:Z01R01L1&attr=temperature"
