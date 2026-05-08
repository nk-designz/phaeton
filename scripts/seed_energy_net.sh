#!/usr/bin/env bash
# seed_energy_net.sh — Create 1000 NGSI-LD entities for a wind park + hydro energy network
# Uses batch upsert in chunks of 50, then seeds 24h of temporal readings
#
# Entity layout (1000 total):
# ── Wind Park (500) ──────────────────────────────────────────────────────────
#   200  WindTurbine              (20 sectors × 10 turbines)
#    20  WindSector               (20 sectors of the park)
#    20  MeteorologicalMast       (one per sector)
#    50  WindInverter             (one per 4 turbines)
#    30  WindTransformer          (one per sector pair)
#    10  WindSubstation           (one per 2 sectors)
#     5  WindParkController
#     5  SCADASystem
#    10  WeatherStation
#    50  WindEnergyMeter
#   100  TurbineVibrationSensor   (one per 2 turbines)
# ── Hydro Network (500) ──────────────────────────────────────────────────────
#    50  HydroTurbineUnit         (5 per plant × 10 plants)
#    10  HydroPlant
#     5  Dam
#     5  HydroReservoir
#     5  Spillway
#    10  Penstock                 (one per 2 turbines per plant)
#    50  WaterFlowSensor          (one per turbine unit)
#    30  ReservoirLevelSensor     (3 per reservoir × 10)
#    20  TailraceSensor           (2 per plant × 10)
#    50  HydroEnergyMeter         (one per turbine unit)
#    30  HydroTransformer
#    10  HydroSubstation
#    80  HydroBearingVibrationSensor (8 per plant × 10)
#    75  HydroPressureSensor
#    30  HydroGenerator           (3 per plant × 10)
#    25  HydroControlValve
#    15  HydroSCADA
#
# Temporal data seeded after entity creation:
#   10 WindTurbines  → powerOutput (MW), windSpeedAtHub (m/s)   — 48 pts / 30 min
#    3 MeteoMasts    → windSpeed (m/s), windDirection (°)        — 48 pts / 30 min
#   10 HydroTurbines → powerOutput (MW), waterFlow (m³/s)        — 48 pts / 30 min
#    5 WaterFlow     → waterFlow (m³/s)                          — 48 pts / 30 min
#
# Usage: ./scripts/seed_energy_net.sh [BASE_URL] [--token TOKEN] [--tenant TENANT]
#   BASE_URL defaults to http://localhost:4000

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
TOTAL=1000

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
entities=()
count=0

# ─── Colour helpers ────────────────────────────────────────────────────────────
BLD='\033[1m'
GRN='\033[0;32m'
CYN='\033[0;36m'
RST='\033[0m'

# ─── Helpers ──────────────────────────────────────────────────────────────────
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
  awk -v min="$1" -v max="$2" 'BEGIN{srand(); printf "%.3f", min + rand() * (max - min)}'
}

randi() {
  awk -v min="$1" -v max="$2" 'BEGIN{srand(); printf "%d", min + int(rand() * (max - min + 1))}'
}

# Wind park centre: North Sea, German Bight (lon=7.50, lat=54.80)
# Sectors: 4 columns × 5 rows — 0.080° lon × 0.060° lat spacing (~5-7 km)
# Turbines within sector: 2 columns × 5 rows — 0.013° lon × 0.010° lat spacing (~0.8-1 km)
PARK_LON=7.50
PARK_LAT=54.80

# geo_lon <col> → adds col * 0.080° east of park centre
geo_sector_lon() { awk -v b="$PARK_LON" -v c="$1" 'BEGIN{printf "%.6f", b + c * 0.080}'; }
# geo_lat <row> → adds row * 0.060° north of park centre
geo_sector_lat() { awk -v b="$PARK_LAT" -v r="$1" 'BEGIN{printf "%.6f", b + r * 0.060}'; }
# turbine offset within a sector
geo_turbine_lon() { awk -v slon="$1" -v col="$2" 'BEGIN{printf "%.6f", slon + col * 0.013}'; }
geo_turbine_lat() { awk -v slat="$1" -v row="$2" 'BEGIN{printf "%.6f", slat + row * 0.010}'; }

# ─── Timestamp helper (GNU + BSD date compatible) ─────────────────────────────
ts_minutes_ago() {
  local mins_ago=$1
  if date --version >/dev/null 2>&1; then
    date -u -d "${mins_ago} minutes ago" +"%Y-%m-%dT%H:%M:%SZ"
  else
    date -u -v-"${mins_ago}"M +"%Y-%m-%dT%H:%M:%SZ"
  fi
}

# ─── Sinusoidal sensor value helper ───────────────────────────────────────────
# sensor_value <base> <amplitude> <minute_offset> <noise_range>
sensor_value() {
  local base=$1 amplitude=$2 minute_offset=$3 noise_range=$4
  local period=1440
  local phase sine noise
  phase=$(echo "scale=6; (${minute_offset} % ${period}) / ${period} * 6.2832 - 1.5708" | bc -l)
  sine=$(echo "scale=6; s(${phase})" | bc -l)
  noise=$(echo "scale=3; (${RANDOM} % 1000) / 1000 * ${noise_range} - (${noise_range} / 2)" | bc -l)
  echo "scale=3; ${base} + ${amplitude} * ${sine} + ${noise}" | bc -l
}

# ─── Wind value: follows 4h wind gusts (shorter period than daily) ────────────
wind_value() {
  local base=$1 amplitude=$2 minute_offset=$3
  local period=240
  local phase sine noise
  phase=$(echo "scale=6; (${minute_offset} % ${period}) / ${period} * 6.2832" | bc -l)
  sine=$(echo "scale=6; s(${phase})" | bc -l)
  noise=$(echo "scale=3; (${RANDOM} % 1000) / 1000 * 2.0 - 1.0" | bc -l)
  echo "scale=3; ${base} + ${amplitude} * ${sine} + ${noise}" | bc -l
}

echo ""
echo -e "${BLD}=== Energy Network Seeder ===${RST}"
echo -e "${CYN}    500 Wind Park entities + 500 Hydro Network entities${RST}"
echo -e "    Target: ${API}"
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# WIND PARK (500 entities)
# ═══════════════════════════════════════════════════════════════════════════════

echo "── Wind Park ────────────────────────────────────────────────────────────────"

# ─── WindParkController (5) ───────────────────────────────────────────────────
echo "  Creating WindParkControllers..."
for c in $(seq -w 1 5); do
  cn=$((10#$c))
  WPC_LON=$(awk -v b="$PARK_LON" -v c="$cn" 'BEGIN{printf "%.6f", b + 0.140 + c * 0.020}')
  WPC_LAT=$(awk -v b="$PARK_LAT" 'BEGIN{printf "%.6f", b + 0.130}')
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:WindParkController:WPC${c}",
  "type": "WindParkController",
  "name": {"type": "Property", "value": "Wind Park Controller ${c}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${WPC_LON}, ${WPC_LAT}]}},
  "operatingMode": {"type": "Property", "value": "automatic"},
  "curtailmentActive": {"type": "Property", "value": false},
  "totalCapacityMW": {"type": "Property", "value": $(randf 80 120), "unitCode": "2G"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
done

# ─── SCADASystem (5) ──────────────────────────────────────────────────────────
echo "  Creating SCADASystems..."
for s in $(seq -w 1 5); do
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:SCADASystem:WIND-SCADA${s}",
  "type": "SCADASystem",
  "name": {"type": "Property", "value": "Wind SCADA ${s}"},
  "vendor": {"type": "Property", "value": "$(echo 'Siemens ABB GE Vestas Schneider' | cut -d' ' -f${s#0})"},
  "softwareVersion": {"type": "Property", "value": "v$(randi 3 7).$(randi 0 9).$(randi 0 9)"},
  "connected": {"type": "Property", "value": true},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
done

# ─── WindSectors + MeteorologicalMasts + WeatherStations ─────────────────────
echo "  Creating sectors, masts and weather stations..."
for s in $(seq -w 1 20); do
  sn=$((10#$s))
  s_row=$(( (sn-1) / 4 ))
  s_col=$(( (sn-1) % 4 ))
  S_LON=$(geo_sector_lon "$s_col")
  S_LAT=$(geo_sector_lat "$s_row")

  # WindSector
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:WindSector:WP01-S${s}",
  "type": "WindSector",
  "name": {"type": "Property", "value": "Sector ${s}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${S_LON}, ${S_LAT}]}},
  "turbineCount": {"type": "Property", "value": 10},
  "installedCapacityMW": {"type": "Property", "value": $(randf 30 50), "unitCode": "2G"},
  "controlledBy": {"type": "Relationship", "object": "urn:ngsi-ld:WindParkController:WPC0$(randi 1 5)"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"

  # MeteorologicalMast (one per sector)
  MM_LON=$(awk -v slon="$S_LON" 'BEGIN{printf "%.6f", slon + 0.005}')
  MM_LAT=$(awk -v slat="$S_LAT" 'BEGIN{printf "%.6f", slat + 0.005}')
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:MeteorologicalMast:MM-S${s}",
  "type": "MeteorologicalMast",
  "name": {"type": "Property", "value": "Met Mast Sector ${s}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${MM_LON}, ${MM_LAT}]}},
  "hubHeight": {"type": "Property", "value": $(randi 80 120), "unitCode": "MTR"},
  "windSpeed": {"type": "Property", "value": $(randf 3.5 14.0), "unitCode": "MTS"},
  "windDirection": {"type": "Property", "value": $(randi 0 359), "unitCode": "DD"},
  "airTemperature": {"type": "Property", "value": $(randf 8.0 22.0), "unitCode": "CEL"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:WindSector:WP01-S${s}"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
done

# WeatherStation (10 — one per 2 sectors)
for w in $(seq -w 1 10); do
  wn=$((10#$w))
  WS_LON=$(awk -v b="$PARK_LON" -v w="$wn" 'BEGIN{printf "%.6f", b + ((w-1)%5) * 0.060 - 0.030}')
  WS_LAT=$(awk -v b="$PARK_LAT" -v w="$wn" 'BEGIN{printf "%.6f", b + int((w-1)/5) * 0.280 + 0.020}')
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:WeatherStation:WS-WP${w}",
  "type": "WeatherStation",
  "name": {"type": "Property", "value": "Weather Station ${w}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${WS_LON}, ${WS_LAT}]}},
  "airPressure": {"type": "Property", "value": $(randf 980.0 1030.0), "unitCode": "PAL"},
  "airTemperature": {"type": "Property", "value": $(randf 5.0 25.0), "unitCode": "CEL"},
  "precipitation": {"type": "Property", "value": $(randf 0 15.0), "unitCode": "MMT"},
  "visibility": {"type": "Property", "value": $(randi 1000 20000), "unitCode": "MTR"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
done

# ─── WindSubstations (10) ─────────────────────────────────────────────────────
echo "  Creating substations and transformers..."
for sub in $(seq -w 1 10); do
  subn=$((10#$sub))
  WSUB_LON=$(awk -v b="$PARK_LON" -v s="$subn" 'BEGIN{printf "%.6f", b + ((s-1)%4) * 0.080}')
  WSUB_LAT=$(awk -v b="$PARK_LAT" 'BEGIN{printf "%.6f", b - 0.040}')
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:WindSubstation:WSub${sub}",
  "type": "WindSubstation",
  "name": {"type": "Property", "value": "Wind Substation ${sub}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${WSUB_LON}, ${WSUB_LAT}]}},
  "voltageLevel": {"type": "Property", "value": $(randi 66 132), "unitCode": "KVT"},
  "capacityMVA": {"type": "Property", "value": $(randf 100 250), "unitCode": "2G"},
  "status": {"type": "Property", "value": "in-service"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
done

# ─── WindTransformers (30 — 3 per substation) ─────────────────────────────────
for sub in $(seq -w 1 10); do
  for t in 1 2 3; do
    add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:WindTransformer:WTx${sub}-T${t}",
  "type": "WindTransformer",
  "name": {"type": "Property", "value": "Wind Transformer ${sub}-${t}"},
  "ratedPowerMVA": {"type": "Property", "value": $(randf 40 90), "unitCode": "2G"},
  "primaryVoltage": {"type": "Property", "value": $(randi 30 36), "unitCode": "KVT"},
  "secondaryVoltage": {"type": "Property", "value": $(randi 132 220), "unitCode": "KVT"},
  "oilTemperature": {"type": "Property", "value": $(randf 45.0 75.0), "unitCode": "CEL"},
  "connectedTo": {"type": "Relationship", "object": "urn:ngsi-ld:WindSubstation:WSub${sub}"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
  done
done

# ─── WindInverters (50 — one per 4 turbines) ──────────────────────────────────
echo "  Creating inverters and energy meters..."
for s in $(seq -w 1 20); do
  for i in 1 2 3; do  # 3 per sector (covers ~4 turbines each)
    if [ "${#entities[@]}" -ge 0 ] && [ "$count" -lt 500 ]; then
      inv_idx=$(( (10#$s - 1) * 3 + i ))
      if [ "$inv_idx" -le 50 ]; then
        add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:WindInverter:WInv-S${s}-I${i}",
  "type": "WindInverter",
  "name": {"type": "Property", "value": "Inverter S${s}-${i}"},
  "ratedPowerKW": {"type": "Property", "value": $(randi 2000 5000), "unitCode": "KWT"},
  "efficiency": {"type": "Property", "value": $(randf 96.5 99.5), "unitCode": "P1"},
  "dcVoltage": {"type": "Property", "value": $(randf 600 900), "unitCode": "VLT"},
  "acFrequency": {"type": "Property", "value": 50.0, "unitCode": "HTZ"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:WindSector:WP01-S${s}"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
      fi
    fi
  done
done

# ─── WindEnergyMeters (50) ────────────────────────────────────────────────────
for m in $(seq -w 1 50); do
  sec=$(( ( (10#$m - 1) / 3) + 1 ))
  sec_pad=$(printf '%02d' $sec)
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:WindEnergyMeter:WEM${m}",
  "type": "WindEnergyMeter",
  "name": {"type": "Property", "value": "Wind Energy Meter ${m}"},
  "activeEnergyProduced": {"type": "Property", "value": $(randf 10000 500000), "unitCode": "KWH"},
  "activePower": {"type": "Property", "value": $(randf 0.5 5.0), "unitCode": "2G"},
  "powerFactor": {"type": "Property", "value": $(randf 0.90 1.00), "unitCode": "P1"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:WindSector:WP01-S${sec_pad}"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
done

# ─── WindTurbines (200 — 10 per sector) ───────────────────────────────────────
echo "  Creating 200 wind turbines..."
TURBINE_MAKERS=("Vestas" "Siemens-Gamesa" "GE-Renewable" "Nordex" "Enercon")
TURBINE_STATES=("producing" "producing" "producing" "producing" "standby" "maintenance" "curtailed")
for s in $(seq -w 1 20); do
  sn=$((10#$s))
  s_row=$(( (sn-1) / 4 ))
  s_col=$(( (sn-1) % 4 ))
  S_LON=$(geo_sector_lon "$s_col")
  S_LAT=$(geo_sector_lat "$s_row")
  maker="${TURBINE_MAKERS[$(( (sn - 1) % 5 ))]}"
  for t in $(seq -w 1 10); do
    tn=$((10#$t))
    t_row=$(( (tn-1) / 2 ))
    t_col=$(( (tn-1) % 2 ))
    T_LON=$(geo_turbine_lon "$S_LON" "$t_col")
    T_LAT=$(geo_turbine_lat "$S_LAT" "$t_row")
    state="${TURBINE_STATES[$(( RANDOM % 7 ))]}"
    add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:WindTurbine:WP01-S${s}-T${t}",
  "type": "WindTurbine",
  "name": {"type": "Property", "value": "Turbine S${s}-T${t}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${T_LON}, ${T_LAT}]}},
  "manufacturer": {"type": "Property", "value": "${maker}"},
  "ratedPowerMW": {"type": "Property", "value": $(randf 3.0 7.0), "unitCode": "2G"},
  "rotorDiameter": {"type": "Property", "value": $(randi 120 220), "unitCode": "MTR"},
  "hubHeight": {"type": "Property", "value": $(randi 90 160), "unitCode": "MTR"},
  "powerOutput": {"type": "Property", "value": $(randf 0.5 5.5), "unitCode": "2G"},
  "windSpeedAtHub": {"type": "Property", "value": $(randf 4.0 14.0), "unitCode": "MTS"},
  "rotorRPM": {"type": "Property", "value": $(randf 6.0 18.0), "unitCode": "RPM"},
  "operationalStatus": {"type": "Property", "value": "${state}"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:WindSector:WP01-S${s}"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
  done
done

# ─── TurbineVibrationSensors (100 — one per 2 turbines) ───────────────────────
echo "  Creating vibration sensors..."
for s in $(seq -w 1 20); do
  sn=$((10#$s))
  s_row=$(( (sn-1) / 4 ))
  s_col=$(( (sn-1) % 4 ))
  S_LON=$(geo_sector_lon "$s_col")
  S_LAT=$(geo_sector_lat "$s_row")
  for t in 1 3 5 7 9; do  # 5 per sector = 100 total
    tn=$t
    t_row=$(( (tn-1) / 2 ))
    t_col=$(( (tn-1) % 2 ))
    T_LON=$(geo_turbine_lon "$S_LON" "$t_col")
    T_LAT=$(geo_turbine_lat "$S_LAT" "$t_row")
    add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:TurbineVibrationSensor:TVS-S${s}-T${t}",
  "type": "TurbineVibrationSensor",
  "name": {"type": "Property", "value": "Vibration S${s}-T${t}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${T_LON}, ${T_LAT}]}},
  "vibrationX": {"type": "Property", "value": $(randf 0.01 0.5), "unitCode": "G45"},
  "vibrationY": {"type": "Property", "value": $(randf 0.01 0.5), "unitCode": "G45"},
  "vibrationZ": {"type": "Property", "value": $(randf 0.01 0.5), "unitCode": "G45"},
  "alertLevel": {"type": "Property", "value": "normal"},
  "monitors": {"type": "Relationship", "object": "urn:ngsi-ld:WindTurbine:WP01-S${s}-T${t}"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
  done
done

flush_batch
echo ""
echo -e "  ${GRN}Wind Park complete — ${count} entities${RST}"

# ═══════════════════════════════════════════════════════════════════════════════
# HYDRO ENERGY NETWORK (500 entities)
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── Hydro Network ────────────────────────────────────────────────────────────"

# ─── Dams + Reservoirs + Spillways (5 each) ────────────────────────────────────
echo "  Creating dams, reservoirs and spillways..."
RIVER_NAMES=("Rhine" "Danube" "Rhone" "Ebro" "Loire")
for d in $(seq -w 1 5); do
  river="${RIVER_NAMES[$((d-1))]}"

  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:Dam:D${d}",
  "type": "Dam",
  "name": {"type": "Property", "value": "${river} Dam ${d}"},
  "river": {"type": "Property", "value": "${river}"},
  "height": {"type": "Property", "value": $(randi 40 200), "unitCode": "MTR"},
  "crestLength": {"type": "Property", "value": $(randi 200 2000), "unitCode": "MTR"},
  "completionYear": {"type": "Property", "value": $(randi 1960 2010)},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"

  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:HydroReservoir:HR${d}",
  "type": "HydroReservoir",
  "name": {"type": "Property", "value": "${river} Reservoir ${d}"},
  "totalCapacityMCM": {"type": "Property", "value": $(randf 50.0 5000.0), "unitCode": "G37"},
  "currentLevel": {"type": "Property", "value": $(randf 60.0 98.0), "unitCode": "P1"},
  "waterTemperature": {"type": "Property", "value": $(randf 4.0 18.0), "unitCode": "CEL"},
  "associatedWith": {"type": "Relationship", "object": "urn:ngsi-ld:Dam:D${d}"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"

  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:Spillway:SP${d}",
  "type": "Spillway",
  "name": {"type": "Property", "value": "${river} Spillway ${d}"},
  "gateCount": {"type": "Property", "value": $(randi 2 8)},
  "dischargeCapacity": {"type": "Property", "value": $(randf 500 5000), "unitCode": "G47"},
  "currentDischarge": {"type": "Property", "value": $(randf 0 200), "unitCode": "G47"},
  "status": {"type": "Property", "value": "closed"},
  "controlledBy": {"type": "Relationship", "object": "urn:ngsi-ld:Dam:D${d}"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
done

# ─── HydroPlants + HydroSubstations (10 each) ─────────────────────────────────
echo "  Creating hydro plants and substations..."
for p in $(seq -w 1 10); do
  dam_id=$(( ( (10#$p - 1) / 2) + 1 ))
  dam_pad=$(printf '%02d' $dam_id)

  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:HydroPlant:HP${p}",
  "type": "HydroPlant",
  "name": {"type": "Property", "value": "Hydro Plant ${p}"},
  "installedCapacityMW": {"type": "Property", "value": $(randf 50 500), "unitCode": "2G"},
  "headHeight": {"type": "Property", "value": $(randi 20 300), "unitCode": "MTR"},
  "turbineCount": {"type": "Property", "value": 5},
  "operationalStatus": {"type": "Property", "value": "generating"},
  "supplyFrom": {"type": "Relationship", "object": "urn:ngsi-ld:HydroReservoir:HR${dam_pad}"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"

  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:HydroSubstation:HSub${p}",
  "type": "HydroSubstation",
  "name": {"type": "Property", "value": "Hydro Substation ${p}"},
  "voltageLevel": {"type": "Property", "value": $(randi 110 400), "unitCode": "KVT"},
  "capacityMVA": {"type": "Property", "value": $(randf 100 600), "unitCode": "2G"},
  "status": {"type": "Property", "value": "in-service"},
  "servedBy": {"type": "Relationship", "object": "urn:ngsi-ld:HydroPlant:HP${p}"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
done

# ─── HydroSCADA (15) ──────────────────────────────────────────────────────────
echo "  Creating hydro SCADA systems..."
for s in $(seq -w 1 15); do
  plant_id=$(( ( (10#$s - 1) % 10) + 1 ))
  plant_pad=$(printf '%02d' $plant_id)
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:HydroSCADA:HSCADA${s}",
  "type": "HydroSCADA",
  "name": {"type": "Property", "value": "Hydro SCADA ${s}"},
  "protocol": {"type": "Property", "value": "$(echo 'DNP3 IEC-104 Modbus DNP3 IEC-61968' | cut -d' ' -f$(( (10#$s % 5) + 1 )))"},
  "connected": {"type": "Property", "value": true},
  "monitoredPlant": {"type": "Relationship", "object": "urn:ngsi-ld:HydroPlant:HP${plant_pad}"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
done

# ─── Penstocks (10) ───────────────────────────────────────────────────────────
echo "  Creating penstocks, valves and generators..."
for p in $(seq -w 1 10); do
  plant_id=$(( ( (10#$p - 1) / 2) + 1 ))
  plant_pad=$(printf '%02d' $plant_id)
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:Penstock:PS${p}",
  "type": "Penstock",
  "name": {"type": "Property", "value": "Penstock ${p}"},
  "diameter": {"type": "Property", "value": $(randf 2.0 8.0), "unitCode": "MTR"},
  "length": {"type": "Property", "value": $(randf 100 2000), "unitCode": "MTR"},
  "designPressure": {"type": "Property", "value": $(randf 5.0 30.0), "unitCode": "BAR"},
  "currentPressure": {"type": "Property", "value": $(randf 3.0 25.0), "unitCode": "BAR"},
  "feedsPlant": {"type": "Relationship", "object": "urn:ngsi-ld:HydroPlant:HP${plant_pad}"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
done

# ─── HydroControlValves (25) ──────────────────────────────────────────────────
for v in $(seq -w 1 25); do
  penstock_id=$(( ( (10#$v - 1) % 10) + 1 ))
  penstock_pad=$(printf '%02d' $penstock_id)
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:HydroControlValve:HCV${v}",
  "type": "HydroControlValve",
  "name": {"type": "Property", "value": "Control Valve ${v}"},
  "valveType": {"type": "Property", "value": "$(echo 'butterfly sphere gate needle ring' | cut -d' ' -f$(( (10#$v % 5) + 1 )))"},
  "openingPercentage": {"type": "Property", "value": $(randf 30.0 100.0), "unitCode": "P1"},
  "flowRate": {"type": "Property", "value": $(randf 20.0 200.0), "unitCode": "G47"},
  "installedOn": {"type": "Relationship", "object": "urn:ngsi-ld:Penstock:PS${penstock_pad}"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
done

# ─── HydroGenerators (30 — 3 per plant) ───────────────────────────────────────
for p in $(seq -w 1 10); do
  for g in 1 2 3; do
    add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:HydroGenerator:HG${p}-G${g}",
  "type": "HydroGenerator",
  "name": {"type": "Property", "value": "Generator P${p}-G${g}"},
  "ratedPowerMW": {"type": "Property", "value": $(randf 20 150), "unitCode": "2G"},
  "ratedVoltageKV": {"type": "Property", "value": $(randi 10 20), "unitCode": "KVT"},
  "statorTemperature": {"type": "Property", "value": $(randf 35.0 80.0), "unitCode": "CEL"},
  "rotorTemperature": {"type": "Property", "value": $(randf 30.0 75.0), "unitCode": "CEL"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:HydroPlant:HP${p}"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
  done
done

# ─── HydroTransformers (30) ───────────────────────────────────────────────────
for p in $(seq -w 1 10); do
  for t in 1 2 3; do
    add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:HydroTransformer:HTx${p}-T${t}",
  "type": "HydroTransformer",
  "name": {"type": "Property", "value": "Hydro Transformer P${p}-T${t}"},
  "ratedPowerMVA": {"type": "Property", "value": $(randf 50 200), "unitCode": "2G"},
  "oilTemperature": {"type": "Property", "value": $(randf 40.0 80.0), "unitCode": "CEL"},
  "loadPercentage": {"type": "Property", "value": $(randf 40.0 95.0), "unitCode": "P1"},
  "connectedTo": {"type": "Relationship", "object": "urn:ngsi-ld:HydroSubstation:HSub${p}"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
  done
done

# ─── HydroTurbineUnits (50 — 5 per plant) ─────────────────────────────────────
echo "  Creating 50 hydro turbine units..."
TURBINE_TYPES=("Kaplan" "Francis" "Pelton" "Bulb" "Turgo")
for p in $(seq -w 1 10); do
  for t in $(seq -w 1 5); do
    ttype="${TURBINE_TYPES[$(( (10#$t - 1) % 5 ))]}"
    add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:HydroTurbineUnit:HP${p}-TU${t}",
  "type": "HydroTurbineUnit",
  "name": {"type": "Property", "value": "Turbine Unit P${p}-T${t}"},
  "turbineType": {"type": "Property", "value": "${ttype}"},
  "ratedPowerMW": {"type": "Property", "value": $(randf 20 120), "unitCode": "2G"},
  "powerOutput": {"type": "Property", "value": $(randf 10.0 100.0), "unitCode": "2G"},
  "waterFlow": {"type": "Property", "value": $(randf 30.0 300.0), "unitCode": "G47"},
  "efficiency": {"type": "Property", "value": $(randf 88.0 96.0), "unitCode": "P1"},
  "rotorRPM": {"type": "Property", "value": $(randf 60.0 500.0), "unitCode": "RPM"},
  "operationalStatus": {"type": "Property", "value": "generating"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:HydroPlant:HP${p}"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
  done
done

# ─── WaterFlowSensors (50) ────────────────────────────────────────────────────
echo "  Creating flow, level and tailrace sensors..."
for p in $(seq -w 1 10); do
  for t in $(seq -w 1 5); do
    add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:WaterFlowSensor:WFS-HP${p}-TU${t}",
  "type": "WaterFlowSensor",
  "name": {"type": "Property", "value": "Flow Sensor P${p}-T${t}"},
  "waterFlow": {"type": "Property", "value": $(randf 30.0 300.0), "unitCode": "G47"},
  "velocity": {"type": "Property", "value": $(randf 1.0 8.0), "unitCode": "MTS"},
  "monitors": {"type": "Relationship", "object": "urn:ngsi-ld:HydroTurbineUnit:HP${p}-TU${t}"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
  done
done

# ─── ReservoirLevelSensors (30 — 3 per reservoir × 10) ────────────────────────
for r in $(seq -w 1 10); do
  for l in 1 2 3; do
    res_id=$(( ( (10#$r - 1) / 2) + 1 ))
    res_pad=$(printf '%02d' $res_id)
    add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:ReservoirLevelSensor:RLS-HR${r}-L${l}",
  "type": "ReservoirLevelSensor",
  "name": {"type": "Property", "value": "Level Sensor R${r}-${l}"},
  "waterLevel": {"type": "Property", "value": $(randf 50.0 300.0), "unitCode": "MTR"},
  "fillPercentage": {"type": "Property", "value": $(randf 50.0 98.0), "unitCode": "P1"},
  "monitors": {"type": "Relationship", "object": "urn:ngsi-ld:HydroReservoir:HR${res_pad}"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
  done
done

# ─── TailraceSensors (20 — 2 per plant) ───────────────────────────────────────
for p in $(seq -w 1 10); do
  for t in 1 2; do
    add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:TailraceSensor:TRS-HP${p}-${t}",
  "type": "TailraceSensor",
  "name": {"type": "Property", "value": "Tailrace Sensor P${p}-${t}"},
  "waterLevel": {"type": "Property", "value": $(randf 1.0 15.0), "unitCode": "MTR"},
  "waterTemperature": {"type": "Property", "value": $(randf 5.0 18.0), "unitCode": "CEL"},
  "monitors": {"type": "Relationship", "object": "urn:ngsi-ld:HydroPlant:HP${p}"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
  done
done

# ─── HydroEnergyMeters (50) ───────────────────────────────────────────────────
echo "  Creating hydro energy meters and bearing sensors..."
for p in $(seq -w 1 10); do
  for t in $(seq -w 1 5); do
    add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:HydroEnergyMeter:HEM-HP${p}-TU${t}",
  "type": "HydroEnergyMeter",
  "name": {"type": "Property", "value": "Hydro Meter P${p}-T${t}"},
  "activeEnergyProduced": {"type": "Property", "value": $(randf 50000 2000000), "unitCode": "KWH"},
  "activePower": {"type": "Property", "value": $(randf 10.0 110.0), "unitCode": "2G"},
  "powerFactor": {"type": "Property", "value": $(randf 0.92 1.00), "unitCode": "P1"},
  "monitors": {"type": "Relationship", "object": "urn:ngsi-ld:HydroTurbineUnit:HP${p}-TU${t}"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
  done
done

# ─── HydroBearingVibrationSensors (80 — 8 per plant) ─────────────────────────
for p in $(seq -w 1 10); do
  for b in $(seq -w 1 8); do
    add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:HydroBearingVibrationSensor:HBVS-HP${p}-B${b}",
  "type": "HydroBearingVibrationSensor",
  "name": {"type": "Property", "value": "Bearing Sensor P${p}-B${b}"},
  "vibrationRMS": {"type": "Property", "value": $(randf 0.5 8.0), "unitCode": "MMT"},
  "temperature": {"type": "Property", "value": $(randf 35.0 70.0), "unitCode": "CEL"},
  "alertLevel": {"type": "Property", "value": "normal"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:HydroPlant:HP${p}"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
  done
done

# ─── HydroPressureSensors (75) ────────────────────────────────────────────────
echo "  Creating pressure sensors..."
for s in $(seq -w 1 75); do
  penstock_id=$(( ( (10#$s - 1) % 10) + 1 ))
  penstock_pad=$(printf '%02d' $penstock_id)
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:HydroPressureSensor:HPS${s}",
  "type": "HydroPressureSensor",
  "name": {"type": "Property", "value": "Pressure Sensor ${s}"},
  "pressure": {"type": "Property", "value": $(randf 3.0 28.0), "unitCode": "BAR"},
  "temperature": {"type": "Property", "value": $(randf 5.0 20.0), "unitCode": "CEL"},
  "monitors": {"type": "Relationship", "object": "urn:ngsi-ld:Penstock:PS${penstock_pad}"},
  "observedAt": {"type": "Property", "value": "${NOW}"}
}
JSON
)"
done

flush_batch
echo ""
echo -e "  ${GRN}Hydro Network complete — ${count} entities total${RST}"

# ═══════════════════════════════════════════════════════════════════════════════
# TEMPORAL DATA
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "── Temporal Data ────────────────────────────────────────────────────────────"
echo "  Seeding 24h of readings at 30-minute intervals (48 points per entity)"

TEMPORAL_DURATION_H=24
TEMPORAL_INTERVAL_M=30
TEMPORAL_POINTS=$(( (TEMPORAL_DURATION_H * 60) / TEMPORAL_INTERVAL_M ))  # 48
TEMPORAL_BATCH=48  # send all points in one request per entity

send_temporal() {
  local entity_id="$1"
  local entity_type="$2"
  local attr_name="$3"
  local attr_body="$4"

  local http_code
  http_code=$(curl -s -o /dev/null -w '%{http_code}' \
    "${COMMON_HEADERS[@]+"${COMMON_HEADERS[@]}"}"\
    -X POST "${API}/temporal/entities" \
    -H "Content-Type: application/json" \
    -d "{\"id\": \"${entity_id}\", \"type\": \"${entity_type}\", \"${attr_name}\": ${attr_body}}")
  printf "    [%s] temporal → %s.%s\n" "$http_code" "$entity_id" "$attr_name"
}

build_temporal_attr() {
  # build_temporal_attr <entity_id> <attr_name> <base> <amplitude> <noise> <unit> [mode]
  local entity_id="$1" attr_name="$2" base="$3" amplitude="$4" noise="$5" unit="$6"
  local mode="${7:-sine}"
  local attr_body="["
  local first=1

  for (( i=TEMPORAL_POINTS-1; i>=0; i-- )); do
    local mins_ago=$(( i * TEMPORAL_INTERVAL_M ))
    local ts
    ts=$(ts_minutes_ago "$mins_ago")

    local val
    if [ "$mode" = "wind" ]; then
      val=$(wind_value "$base" "$amplitude" "$mins_ago")
    else
      val=$(sensor_value "$base" "$amplitude" "$mins_ago" "$noise")
    fi
    # Clamp to 0 if negative
    val=$(echo "if (${val} < 0) 0 else ${val}" | bc -l 2>/dev/null || echo "$val")

    if [ "$first" -ne 1 ]; then
      attr_body="${attr_body},"
    fi
    first=0

    attr_body="${attr_body}
    {\"type\":\"Property\",\"value\":${val},\"unitCode\":\"${unit}\",\"observedAt\":\"${ts}\",\"instanceId\":\"urn:ngsi-ld:ti:${entity_id##*:}:${attr_name}:${i}\"}"
  done

  attr_body="${attr_body}]"
  echo "$attr_body"
}

# ─── 10 Wind Turbines → powerOutput + windSpeedAtHub ─────────────────────────
echo ""
echo "  Wind turbines (10 × 2 attributes)..."
for s in 01 05 10 15 20; do
  for t in 01 06; do
    TID="urn:ngsi-ld:WindTurbine:WP01-S${s}-T${t}"

    power_body=$(build_temporal_attr "$TID" "powerOutput" 3.0 2.5 0.3 "2G" "wind")
    send_temporal "$TID" "WindTurbine" "powerOutput" "$power_body"

    wind_body=$(build_temporal_attr "$TID" "windSpeedAtHub" 9.0 4.5 0.8 "MTS" "wind")
    send_temporal "$TID" "WindTurbine" "windSpeedAtHub" "$wind_body"
  done
done

# ─── 3 MeteorologicalMasts → windSpeed + windDirection ───────────────────────
echo ""
echo "  Meteorological masts (3 × 2 attributes)..."
for s in 01 10 20; do
  MID="urn:ngsi-ld:MeteorologicalMast:MM-S${s}"

  ws_body=$(build_temporal_attr "$MID" "windSpeed" 9.0 4.0 1.0 "MTS" "wind")
  send_temporal "$MID" "MeteorologicalMast" "windSpeed" "$ws_body"

  wd_body=$(build_temporal_attr "$MID" "windDirection" 180 90 15 "DD" "sine")
  send_temporal "$MID" "MeteorologicalMast" "windDirection" "$wd_body"
done

# ─── 10 HydroTurbineUnits → powerOutput + waterFlow ─────────────────────────
echo ""
echo "  Hydro turbine units (10 × 2 attributes)..."
for p in 01 02 03 04 05; do
  for t in 01 03; do
    HID="urn:ngsi-ld:HydroTurbineUnit:HP${p}-TU${t}"

    hpower_body=$(build_temporal_attr "$HID" "powerOutput" 80.0 15.0 2.0 "2G" "sine")
    send_temporal "$HID" "HydroTurbineUnit" "powerOutput" "$hpower_body"

    hflow_body=$(build_temporal_attr "$HID" "waterFlow" 150.0 40.0 5.0 "G47" "sine")
    send_temporal "$HID" "HydroTurbineUnit" "waterFlow" "$hflow_body"
  done
done

# ─── 5 WaterFlowSensors → waterFlow ──────────────────────────────────────────
echo ""
echo "  Water flow sensors (5 × 1 attribute)..."
for p in 01 02 03 04 05; do
  WFID="urn:ngsi-ld:WaterFlowSensor:WFS-HP${p}-TU01"

  wf_body=$(build_temporal_attr "$WFID" "waterFlow" 150.0 35.0 5.0 "G47" "sine")
  send_temporal "$WFID" "WaterFlowSensor" "waterFlow" "$wf_body"
done

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BLD}=== Energy Network seeding complete ===${RST}"
echo ""
echo -e "  ${BLD}Entities created:${RST} ${count}"
echo -e "  ${BLD}Temporal series:${RST}  26 entities × 1-2 attributes × ${TEMPORAL_POINTS} points"
echo ""
echo -e "  ${CYN}Dashboard:  ${BASE_URL}/${RST}"
echo -e "  ${CYN}Entities:   ${BASE_URL}/entities${RST}"
echo -e "  ${CYN}Charts:     ${BASE_URL}/charts${RST}"
echo ""
