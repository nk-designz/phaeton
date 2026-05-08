#!/usr/bin/env bash
# seed_el_hierro.sh — 100-entity NGSI-LD Smart Island model for El Hierro (Canary Islands, Spain)
# Uses batch upsert in chunks of 50 for speed.
#
# Entity breakdown (100 total):
#   Admin        (6):  3 Neighborhood, 3 EmergencyStation
#   Energy      (13):  1 PowerPlant, 5 WindTurbine, 2 HydroPumpStation,
#                      2 PowerTransformer, 3 SmartMeter
#   Water       (13):  3 WaterPumpStation, 3 WaterReservoir,
#                      4 WaterPressureSensor, 3 WaterQualitySensor
#   Environment (19):  5 AirQualitySensor, 4 WeatherStation,
#                      3 SeaLevelSensor, 3 SoilMoistureSensor, 4 NoiseSensor
#   Traffic     (10):  4 TrafficCamera, 4 TrafficFlowSensor, 2 ParkingLot
#   Transport   (11):  2 BusRoute, 6 BusStop, 3 Bus
#   Waste       (11):  8 WasteContainer, 2 WasteCollectionVehicle,
#                      1 WasteProcessingFacility
#   Lighting     (8):  8 StreetLight
#   Smart Infra  (9):  5 ElectricVehicleCharger, 4 PublicWifiAccessPoint
#
# Usage: ./scripts/seed_el_hierro.sh [BASE_URL] [--token TOKEN] [--tenant TENANT]
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
TOTAL=100

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

echo "=== Smart Island El Hierro Seeder (100 entities) ==="
echo "    Target: ${TOTAL} entities → ${API}"
echo ""

# ─────────────────────────────────────────
# 1. Neighborhoods (3)
# ─────────────────────────────────────────
echo "Creating neighborhoods..."

add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:Neighborhood:Valverde",
  "type": "Neighborhood",
  "name": {"type": "Property", "value": "Valverde"},
  "description": {"type": "Property", "value": "Capital municipal, zona noreste de El Hierro"},
  "population": {"type": "Property", "value": 5099},
  "area": {"type": "Property", "value": 93.4, "unitCode": "KMK"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [-17.9110, 27.8110]}}
}
JSON
)"

add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:Neighborhood:Frontera",
  "type": "Neighborhood",
  "name": {"type": "Property", "value": "Frontera"},
  "description": {"type": "Property", "value": "Valle de El Golfo, zona oeste, principal área agrícola"},
  "population": {"type": "Property", "value": 2924},
  "area": {"type": "Property", "value": 111.8, "unitCode": "KMK"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [-18.0100, 27.7370]}}
}
JSON
)"

add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:Neighborhood:ElPinar",
  "type": "Neighborhood",
  "name": {"type": "Property", "value": "El Pinar"},
  "description": {"type": "Property", "value": "Zona sur, bosque de pinos centenarios y costa volcánica"},
  "population": {"type": "Property", "value": 1109},
  "area": {"type": "Property", "value": 103.4, "unitCode": "KMK"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [-17.9747, 27.7508]}}
}
JSON
)"

# ─────────────────────────────────────────
# 2. Emergency Stations (3)
# ─────────────────────────────────────────
echo "Creating emergency stations..."

add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:EmergencyStation:GuardiaCivil",
  "type": "EmergencyStation",
  "name": {"type": "Property", "value": "Guardia Civil El Hierro"},
  "address": {"type": "Property", "value": "Calle Dr. Quintero Magdaleno, 8, 38900 Valverde"},
  "serviceType": {"type": "Property", "value": "police"},
  "phone": {"type": "Property", "value": "+34 922 550 022"},
  "active": {"type": "Property", "value": true},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:Neighborhood:Valverde"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [-17.9102, 27.8118]}}
}
JSON
)"

add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:EmergencyStation:Bomberos",
  "type": "EmergencyStation",
  "name": {"type": "Property", "value": "Parque de Bomberos El Hierro"},
  "address": {"type": "Property", "value": "Calle San Francisco, 3, 38900 Valverde"},
  "serviceType": {"type": "Property", "value": "fire"},
  "phone": {"type": "Property", "value": "+34 922 550 080"},
  "active": {"type": "Property", "value": true},
  "units": {"type": "Property", "value": 3},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:Neighborhood:Valverde"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [-17.9118, 27.8125]}}
}
JSON
)"

add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:EmergencyStation:HospitalInsular",
  "type": "EmergencyStation",
  "name": {"type": "Property", "value": "Hospital Insular El Hierro"},
  "address": {"type": "Property", "value": "Calle La Verdad, 12, 38900 Valverde"},
  "serviceType": {"type": "Property", "value": "medical"},
  "phone": {"type": "Property", "value": "+34 922 559 600"},
  "active": {"type": "Property", "value": true},
  "beds": {"type": "Property", "value": 21},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:Neighborhood:Valverde"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [-17.9095, 27.8098]}}
}
JSON
)"

# ─────────────────────────────────────────
# 3. Energy — PowerPlant (1)
# ─────────────────────────────────────────
echo "Creating energy infrastructure..."

add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:PowerPlant:GoronaDelViento",
  "type": "PowerPlant",
  "name": {"type": "Property", "value": "Gorona del Viento"},
  "description": {"type": "Property", "value": "Central hidroeólica 100% renovable — referencia mundial de isla sostenible"},
  "address": {"type": "Property", "value": "Paraje Gorona del Viento, Frontera, El Hierro"},
  "installedCapacity": {"type": "Property", "value": 11.5, "unitCode": "2J"},
  "energySource": {"type": "Property", "value": "wind-hydro-hybrid"},
  "renewableRatio": {"type": "Property", "value": $(randf 80 100), "unitCode": "P1", "observedAt": "${NOW}"},
  "netOutput": {"type": "Property", "value": $(randf 4000 11000), "unitCode": "KWT", "observedAt": "${NOW}"},
  "operationalSince": {"type": "Property", "value": "2014-06-27"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:Neighborhood:Frontera"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [-18.0220, 27.7860]}}
}
JSON
)"

# ─────────────────────────────────────────
# 4. Energy — WindTurbines (5)
# ─────────────────────────────────────────
WT_LONS=("-18.0215" "-18.0198" "-18.0182" "-18.0166" "-18.0150")
WT_LATS=("27.7872" "27.7855" "27.7838" "27.7821" "27.7804")

for i in $(seq 1 5); do
  idx=$((i - 1))
  wpad=$(printf "%02d" "$i")
  lon="${WT_LONS[$idx]}"
  lat="${WT_LATS[$idx]}"
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:WindTurbine:WT${wpad}",
  "type": "WindTurbine",
  "name": {"type": "Property", "value": "Aerogenerador WT${wpad}"},
  "address": {"type": "Property", "value": "Paraje Gorona del Viento, Frontera"},
  "ratedPower": {"type": "Property", "value": 2300, "unitCode": "KWT"},
  "powerOutput": {"type": "Property", "value": $(randf 200 2300), "unitCode": "KWT", "observedAt": "${NOW}"},
  "rotorSpeed": {"type": "Property", "value": $(randf 5 18), "unitCode": "RPM", "observedAt": "${NOW}"},
  "windSpeed": {"type": "Property", "value": $(randf 4 22), "unitCode": "MTS", "observedAt": "${NOW}"},
  "hubHeight": {"type": "Property", "value": 55, "unitCode": "MTR"},
  "status": {"type": "Property", "value": "operating"},
  "partOf": {"type": "Relationship", "object": "urn:ngsi-ld:PowerPlant:GoronaDelViento"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:Neighborhood:Frontera"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${lon}, ${lat}]}}
}
JSON
)"
done

# ─────────────────────────────────────────
# 5. Energy — HydroPumpStations (2)
# ─────────────────────────────────────────
add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:HydroPumpStation:GoronaUpper",
  "type": "HydroPumpStation",
  "name": {"type": "Property", "value": "Estación de Bombeo Superior Gorona"},
  "address": {"type": "Property", "value": "Embalse Superior de Gorona, Frontera"},
  "pumpCapacity": {"type": "Property", "value": 1500, "unitCode": "LTR"},
  "elevation": {"type": "Property", "value": 714, "unitCode": "MTR"},
  "status": {"type": "Property", "value": "pumping"},
  "flowRate": {"type": "Property", "value": $(randf 200 1500), "unitCode": "LTR", "observedAt": "${NOW}"},
  "partOf": {"type": "Relationship", "object": "urn:ngsi-ld:PowerPlant:GoronaDelViento"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [-18.0232, 27.7882]}}
}
JSON
)"

add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:HydroPumpStation:GoronaLower",
  "type": "HydroPumpStation",
  "name": {"type": "Property", "value": "Estación de Bombeo Inferior Gorona"},
  "address": {"type": "Property", "value": "Embalse Inferior de Gorona, Frontera"},
  "pumpCapacity": {"type": "Property", "value": 1500, "unitCode": "LTR"},
  "elevation": {"type": "Property", "value": 236, "unitCode": "MTR"},
  "status": {"type": "Property", "value": "standby"},
  "flowRate": {"type": "Property", "value": $(randf 0 500), "unitCode": "LTR", "observedAt": "${NOW}"},
  "partOf": {"type": "Relationship", "object": "urn:ngsi-ld:PowerPlant:GoronaDelViento"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [-18.0205, 27.7840]}}
}
JSON
)"

# ─────────────────────────────────────────
# 6. Energy — PowerTransformers (2)
# ─────────────────────────────────────────
add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:PowerTransformer:TR-Valverde",
  "type": "PowerTransformer",
  "name": {"type": "Property", "value": "Subestación Eléctrica Valverde"},
  "address": {"type": "Property", "value": "Avenida Islas Canarias, 45, 38900 Valverde"},
  "voltage": {"type": "Property", "value": 20, "unitCode": "KVT"},
  "load": {"type": "Property", "value": $(randf 30 85), "unitCode": "P1", "observedAt": "${NOW}"},
  "status": {"type": "Property", "value": "normal"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:Neighborhood:Valverde"},
  "poweredBy": {"type": "Relationship", "object": "urn:ngsi-ld:PowerPlant:GoronaDelViento"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [-17.9132, 27.8088]}}
}
JSON
)"

add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:PowerTransformer:TR-Frontera",
  "type": "PowerTransformer",
  "name": {"type": "Property", "value": "Subestación Eléctrica Frontera"},
  "address": {"type": "Property", "value": "Calle Tigaday, 22, 38911 Frontera"},
  "voltage": {"type": "Property", "value": 20, "unitCode": "KVT"},
  "load": {"type": "Property", "value": $(randf 20 70), "unitCode": "P1", "observedAt": "${NOW}"},
  "status": {"type": "Property", "value": "normal"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:Neighborhood:Frontera"},
  "poweredBy": {"type": "Relationship", "object": "urn:ngsi-ld:PowerPlant:GoronaDelViento"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [-18.0088, 27.7358]}}
}
JSON
)"

# ─────────────────────────────────────────
# 7. Energy — SmartMeters (3)
# ─────────────────────────────────────────
METER_HOODS=("Valverde" "Frontera" "ElPinar")
METER_ADDRS=("Plaza de la Constitución, 1, 38900 Valverde" "Calle La Era, 4, 38911 Frontera" "Calle Los Mocanes, 2, 38912 El Pinar")
METER_LONS=("-17.9108" "-18.0095" "-17.9748")
METER_LATS=("27.8112" "27.7362" "27.7505")
METER_TRS=("TR-Valverde" "TR-Frontera" "TR-Frontera")

for i in $(seq 0 2); do
  hood="${METER_HOODS[$i]}"
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:SmartMeter:SM-${hood}",
  "type": "SmartMeter",
  "name": {"type": "Property", "value": "Contador Inteligente ${hood}"},
  "address": {"type": "Property", "value": "${METER_ADDRS[$i]}"},
  "consumption": {"type": "Property", "value": $(randf 50 800), "unitCode": "KWH", "observedAt": "${NOW}"},
  "voltage": {"type": "Property", "value": $(randf 218 242), "unitCode": "VLT", "observedAt": "${NOW}"},
  "powerFactor": {"type": "Property", "value": $(randf 0.90 0.99), "observedAt": "${NOW}"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:Neighborhood:${hood}"},
  "connectedTo": {"type": "Relationship", "object": "urn:ngsi-ld:PowerTransformer:${METER_TRS[$i]}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${METER_LONS[$i]}, ${METER_LATS[$i]}]}}
}
JSON
)"
done

# ─────────────────────────────────────────
# 8. Water — WaterPumpStations (3)
# ─────────────────────────────────────────
echo "Creating water distribution network..."

WPS_NAMES=("Norte" "Oeste" "Sur")
WPS_ADDRS=("Carretera HI-1, Tiñor, Valverde" "Carretera HI-1 km 18, Frontera" "Carretera del Sur HI-3 km 6, El Pinar")
WPS_HOODS=("Valverde" "Frontera" "ElPinar")
WPS_LONS=("-17.9045" "-18.0050" "-17.9755")
WPS_LATS=("27.7810" "27.7450" "27.7495")

for i in $(seq 0 2); do
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:WaterPumpStation:WPS-${WPS_NAMES[$i]}",
  "type": "WaterPumpStation",
  "name": {"type": "Property", "value": "Estación de Bombeo de Agua ${WPS_NAMES[$i]}"},
  "address": {"type": "Property", "value": "${WPS_ADDRS[$i]}"},
  "flowRate": {"type": "Property", "value": $(randf 50 400), "unitCode": "LTR", "observedAt": "${NOW}"},
  "pressure": {"type": "Property", "value": $(randf 2.5 6.0), "unitCode": "BAR", "observedAt": "${NOW}"},
  "status": {"type": "Property", "value": "active"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:Neighborhood:${WPS_HOODS[$i]}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${WPS_LONS[$i]}, ${WPS_LATS[$i]}]}}
}
JSON
)"
done

# ─────────────────────────────────────────
# 9. Water — WaterReservoirs (3)
# ─────────────────────────────────────────
WR_IDS=("Tinor" "GoronaUpper" "Lomo")
WR_NAMES=("Embalse de Tiñor" "Embalse Superior de Gorona" "Embalse del Lomo")
WR_CAPS=("250000" "150000" "120000")
WR_LONS=("-17.9040" "-18.0240" "-17.9760")
WR_LATS=("27.7820" "27.7895" "27.7515")

for i in $(seq 0 2); do
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:WaterReservoir:WR-${WR_IDS[$i]}",
  "type": "WaterReservoir",
  "name": {"type": "Property", "value": "${WR_NAMES[$i]}"},
  "capacity": {"type": "Property", "value": ${WR_CAPS[$i]}, "unitCode": "LTR"},
  "currentLevel": {"type": "Property", "value": $(randf 40 95), "unitCode": "P1", "observedAt": "${NOW}"},
  "temperature": {"type": "Property", "value": $(randf 14 22), "unitCode": "CEL", "observedAt": "${NOW}"},
  "suppliedBy": {"type": "Relationship", "object": "urn:ngsi-ld:WaterPumpStation:WPS-${WPS_NAMES[$i]}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${WR_LONS[$i]}, ${WR_LATS[$i]}]}}
}
JSON
)"
done

# ─────────────────────────────────────────
# 10. Water — WaterPressureSensors (4)
# ─────────────────────────────────────────
WP_ZONES=("Valverde-Centro" "Valverde-Puerto" "Frontera-Centro" "ElPinar-Centro")
WP_ADDRS=("Calle Dr. Quintero Magdaleno, 38900 Valverde" "Puerto de La Estaca, 38900 Valverde" "Calle El Batán, 38911 Frontera" "Calle La Dehesa, 38912 El Pinar")
WP_WPS=("Norte" "Norte" "Oeste" "Sur")
WP_LONS=("-17.9108" "-17.8960" "-18.0065" "-17.9750")
WP_LATS=("27.8112" "27.7990" "27.7375" "27.7502")

for i in $(seq 0 3); do
  ppad=$(printf "%02d" "$((i+1))")
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:WaterPressureSensor:WP${ppad}",
  "type": "WaterPressureSensor",
  "name": {"type": "Property", "value": "Sensor Presión Red ${WP_ZONES[$i]}"},
  "address": {"type": "Property", "value": "${WP_ADDRS[$i]}"},
  "pressure": {"type": "Property", "value": $(randf 2.0 5.5), "unitCode": "BAR", "observedAt": "${NOW}"},
  "status": {"type": "Property", "value": "normal"},
  "monitoredBy": {"type": "Relationship", "object": "urn:ngsi-ld:WaterPumpStation:WPS-${WP_WPS[$i]}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${WP_LONS[$i]}, ${WP_LATS[$i]}]}}
}
JSON
)"
done

# ─────────────────────────────────────────
# 11. Water — WaterQualitySensors (3)
# ─────────────────────────────────────────
WQ_ZONES=("Norte" "Oeste" "Sur")
WQ_RES=("WR-Tinor" "WR-GoronaUpper" "WR-Lomo")
WQ_LONS=("-17.9042" "-18.0055" "-17.9762")
WQ_LATS=("27.7815" "27.7448" "27.7498")

for i in $(seq 0 2); do
  qpad=$(printf "%02d" "$((i+1))")
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:WaterQualitySensor:WQ${qpad}",
  "type": "WaterQualitySensor",
  "name": {"type": "Property", "value": "Sensor Calidad Agua Zona ${WQ_ZONES[$i]}"},
  "pH": {"type": "Property", "value": $(randf 6.5 8.5), "observedAt": "${NOW}"},
  "turbidity": {"type": "Property", "value": $(randf 0.1 2.0), "unitCode": "NTU", "observedAt": "${NOW}"},
  "conductivity": {"type": "Property", "value": $(randf 200 800), "unitCode": "S4", "observedAt": "${NOW}"},
  "chlorine": {"type": "Property", "value": $(randf 0.2 1.0), "unitCode": "MGL", "observedAt": "${NOW}"},
  "monitoredBy": {"type": "Relationship", "object": "urn:ngsi-ld:WaterReservoir:${WQ_RES[$i]}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${WQ_LONS[$i]}, ${WQ_LATS[$i]}]}}
}
JSON
)"
done

# ─────────────────────────────────────────
# 12. Environment — AirQualitySensors (5)
# ─────────────────────────────────────────
echo "Creating environment sensors..."

AQ_LOCS=("Valverde-Plaza" "Frontera-Centro" "ElPinar" "LaRestinga" "PuertoEstaca")
AQ_ADDRS=("Plaza de la Constitución, 38900 Valverde" "Calle Tigaday, 8, 38911 Frontera" "Carretera del Sur HI-3, 38912 El Pinar" "Calle Puerto, La Restinga" "Puerto de La Estaca, 38900 Valverde")
AQ_HOODS=("Valverde" "Frontera" "ElPinar" "ElPinar" "Valverde")
AQ_LONS=("-17.9105" "-18.0088" "-17.9748" "-17.9902" "-17.8958")
AQ_LATS=("27.8115" "27.7368" "27.7508" "27.6432" "27.7988")

for i in $(seq 0 4); do
  apad=$(printf "%02d" "$((i+1))")
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:AirQualitySensor:AQ${apad}",
  "type": "AirQualitySensor",
  "name": {"type": "Property", "value": "Sensor Calidad Aire ${AQ_LOCS[$i]}"},
  "address": {"type": "Property", "value": "${AQ_ADDRS[$i]}"},
  "NO2": {"type": "Property", "value": $(randf 5 40), "unitCode": "GQ", "observedAt": "${NOW}"},
  "O3": {"type": "Property", "value": $(randf 40 120), "unitCode": "GQ", "observedAt": "${NOW}"},
  "PM2_5": {"type": "Property", "value": $(randf 2 25), "unitCode": "GQ", "observedAt": "${NOW}"},
  "PM10": {"type": "Property", "value": $(randf 5 50), "unitCode": "GQ", "observedAt": "${NOW}"},
  "AQI": {"type": "Property", "value": $(randi 20 80), "observedAt": "${NOW}"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:Neighborhood:${AQ_HOODS[$i]}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${AQ_LONS[$i]}, ${AQ_LATS[$i]}]}}
}
JSON
)"
done

# ─────────────────────────────────────────
# 13. Environment — WeatherStations (4)
# ─────────────────────────────────────────
WS_IDS=("Valverde" "Frontera" "ElPinar" "PuntaOrchilla")
WS_ADDRS=("Avenida Islas Canarias, 38900 Valverde" "Camino del Julan, 38911 Frontera" "Calle Los Mocanes, 38912 El Pinar" "Faro de Orchilla, Carretera HI-4, El Hierro")
WS_LONS=("-17.9112" "-18.0098" "-17.9755" "-18.0780")
WS_LATS=("27.8108" "27.7372" "27.7510" "27.7055")
WS_HOODS=("Valverde" "Frontera" "ElPinar" "ElPinar")

for i in $(seq 0 3); do
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:WeatherStation:WS-${WS_IDS[$i]}",
  "type": "WeatherStation",
  "name": {"type": "Property", "value": "Estación Meteorológica ${WS_IDS[$i]}"},
  "address": {"type": "Property", "value": "${WS_ADDRS[$i]}"},
  "temperature": {"type": "Property", "value": $(randf 18 28), "unitCode": "CEL", "observedAt": "${NOW}"},
  "humidity": {"type": "Property", "value": $(randf 55 85), "unitCode": "P1", "observedAt": "${NOW}"},
  "windSpeed": {"type": "Property", "value": $(randf 5 30), "unitCode": "MTS", "observedAt": "${NOW}"},
  "windDirection": {"type": "Property", "value": $(randi 0 359), "unitCode": "DD", "observedAt": "${NOW}"},
  "atmosphericPressure": {"type": "Property", "value": $(randf 1008 1025), "unitCode": "A97", "observedAt": "${NOW}"},
  "solarRadiation": {"type": "Property", "value": $(randf 100 900), "unitCode": "D81", "observedAt": "${NOW}"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:Neighborhood:${WS_HOODS[$i]}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${WS_LONS[$i]}, ${WS_LATS[$i]}]}}
}
JSON
)"
done

# ─────────────────────────────────────────
# 14. Environment — SeaLevelSensors (3)
# ─────────────────────────────────────────
SLV_IDS=("LaRestinga" "LasPlayas" "Tamaduste")
SLV_ADDRS=("Puerto de La Restinga, 38915 El Pinar" "Las Playas, Carretera HI-1, Frontera" "Playa de Tamaduste, 38900 Valverde")
SLV_LONS=("-17.9898" "-17.9175" "-17.9148")
SLV_LATS=("27.6428" "27.7098" "27.8198")
SLV_HOODS=("ElPinar" "Frontera" "Valverde")

for i in $(seq 0 2); do
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:SeaLevelSensor:SL-${SLV_IDS[$i]}",
  "type": "SeaLevelSensor",
  "name": {"type": "Property", "value": "Sensor Nivel Mar ${SLV_IDS[$i]}"},
  "address": {"type": "Property", "value": "${SLV_ADDRS[$i]}"},
  "seaLevel": {"type": "Property", "value": $(randf -0.40 0.80), "unitCode": "MTR", "observedAt": "${NOW}"},
  "waveHeight": {"type": "Property", "value": $(randf 0.1 3.5), "unitCode": "MTR", "observedAt": "${NOW}"},
  "seaSurfaceTemp": {"type": "Property", "value": $(randf 20 26), "unitCode": "CEL", "observedAt": "${NOW}"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:Neighborhood:${SLV_HOODS[$i]}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${SLV_LONS[$i]}, ${SLV_LATS[$i]}]}}
}
JSON
)"
done

# ─────────────────────────────────────────
# 15. Environment — SoilMoistureSensors (3)
# ─────────────────────────────────────────
SMS_IDS=("ElGolfo01" "ElGolfo02" "PajonalesPinar")
SMS_ADDRS=("Camino agrícola Las Vegas, 38911 Frontera" "Finca El Golfo, Carretera HI-1, Frontera" "Pinar de Pajonales, 38912 El Pinar")
SMS_LONS=("-18.0082" "-18.0118" "-17.9762")
SMS_LATS=("27.7322" "27.7285" "27.7492")
SMS_HOODS=("Frontera" "Frontera" "ElPinar")

for i in $(seq 0 2); do
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:SoilMoistureSensor:SMS-${SMS_IDS[$i]}",
  "type": "SoilMoistureSensor",
  "name": {"type": "Property", "value": "Sensor Humedad Suelo ${SMS_IDS[$i]}"},
  "address": {"type": "Property", "value": "${SMS_ADDRS[$i]}"},
  "soilMoisture": {"type": "Property", "value": $(randf 15 75), "unitCode": "P1", "observedAt": "${NOW}"},
  "soilTemperature": {"type": "Property", "value": $(randf 15 28), "unitCode": "CEL", "observedAt": "${NOW}"},
  "soilEC": {"type": "Property", "value": $(randf 0.1 2.5), "unitCode": "D10", "observedAt": "${NOW}"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:Neighborhood:${SMS_HOODS[$i]}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${SMS_LONS[$i]}, ${SMS_LATS[$i]}]}}
}
JSON
)"
done

# ─────────────────────────────────────────
# 16. Environment — NoiseSensors (4)
# ─────────────────────────────────────────
NS_LOCS=("Valverde-Plaza" "Valverde-HI1" "Frontera-Centro" "ElPinar-Carretera")
NS_ADDRS=("Plaza de la Constitución, 38900 Valverde" "Carretera HI-1 km 2, 38900 Valverde" "Calle Tigaday, 5, 38911 Frontera" "Carretera del Sur HI-3 km 4, 38912 El Pinar")
NS_LONS=("-17.9105" "-17.9145" "-18.0090" "-17.9748")
NS_LATS=("27.8115" "27.8075" "27.7365" "27.7502")
NS_HOODS=("Valverde" "Valverde" "Frontera" "ElPinar")

for i in $(seq 0 3); do
  npad=$(printf "%02d" "$((i+1))")
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:NoiseSensor:NS${npad}",
  "type": "NoiseSensor",
  "name": {"type": "Property", "value": "Sensor Ruido ${NS_LOCS[$i]}"},
  "address": {"type": "Property", "value": "${NS_ADDRS[$i]}"},
  "noiseLevel": {"type": "Property", "value": $(randf 35 72), "unitCode": "2N", "observedAt": "${NOW}"},
  "peak": {"type": "Property", "value": $(randf 55 90), "unitCode": "2N", "observedAt": "${NOW}"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:Neighborhood:${NS_HOODS[$i]}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${NS_LONS[$i]}, ${NS_LATS[$i]}]}}
}
JSON
)"
done

# ─────────────────────────────────────────
# 17. Traffic — TrafficCameras (4)
# ─────────────────────────────────────────
echo "Creating traffic infrastructure..."

TC_LOCS=("HI1-SalidaValverde" "HI1-CruceMocanal" "HI3-ElPinar" "HI5-LaRestinga")
TC_ADDRS=("Carretera HI-1 km 1, salida Valverde" "Cruce de Mocanal, HI-1, Valverde" "Carretera del Sur HI-3 km 5, El Pinar" "Carretera HI-5 km 1, La Restinga")
TC_LONS=("-17.9148" "-17.9282" "-17.9752" "-17.9892")
TC_LATS=("27.8068" "27.8185" "27.7498" "27.6445")

for i in $(seq 0 3); do
  cpad=$(printf "%02d" "$((i+1))")
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:TrafficCamera:TC${cpad}",
  "type": "TrafficCamera",
  "name": {"type": "Property", "value": "Cámara Tráfico ${TC_LOCS[$i]}"},
  "address": {"type": "Property", "value": "${TC_ADDRS[$i]}"},
  "status": {"type": "Property", "value": "active"},
  "resolution": {"type": "Property", "value": "1080p"},
  "vehiclesDetected": {"type": "Property", "value": $(randi 0 25), "observedAt": "${NOW}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${TC_LONS[$i]}, ${TC_LATS[$i]}]}}
}
JSON
)"
done

# ─────────────────────────────────────────
# 18. Traffic — TrafficFlowSensors (4)
# ─────────────────────────────────────────
TFS_LOCS=("HI1-Norte" "HI1-Centro" "HI3-Sur" "HI5-Costa")
TFS_ADDRS=("Carretera HI-1 km 5, Valverde" "Carretera HI-1 km 15, Frontera" "Carretera HI-3 km 8, El Pinar" "Carretera HI-5 km 3, La Restinga")
TFS_LONS=("-17.9210" "-17.9520" "-17.9745" "-17.9602")
TFS_LATS=("27.8045" "27.7820" "27.7505" "27.6618")

for i in $(seq 0 3); do
  fpad=$(printf "%02d" "$((i+1))")
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:TrafficFlowSensor:TFS${fpad}",
  "type": "TrafficFlowSensor",
  "name": {"type": "Property", "value": "Sensor Flujo Tráfico ${TFS_LOCS[$i]}"},
  "address": {"type": "Property", "value": "${TFS_ADDRS[$i]}"},
  "vehicleCount": {"type": "Property", "value": $(randi 10 350), "observedAt": "${NOW}"},
  "avgSpeed": {"type": "Property", "value": $(randf 30 80), "unitCode": "KMH", "observedAt": "${NOW}"},
  "occupancy": {"type": "Property", "value": $(randf 5 70), "unitCode": "P1", "observedAt": "${NOW}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${TFS_LONS[$i]}, ${TFS_LATS[$i]}]}}
}
JSON
)"
done

# ─────────────────────────────────────────
# 19. Traffic — ParkingLots (2)
# ─────────────────────────────────────────
add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:ParkingLot:PL-Valverde",
  "type": "ParkingLot",
  "name": {"type": "Property", "value": "Parking Municipal Valverde"},
  "address": {"type": "Property", "value": "Calle El Molino, 1, 38900 Valverde"},
  "capacity": {"type": "Property", "value": 80},
  "available": {"type": "Property", "value": $(randi 10 75), "observedAt": "${NOW}"},
  "EVspots": {"type": "Property", "value": 6},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:Neighborhood:Valverde"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [-17.9122, 27.8095]}}
}
JSON
)"

add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:ParkingLot:PL-Frontera",
  "type": "ParkingLot",
  "name": {"type": "Property", "value": "Parking Municipal Frontera"},
  "address": {"type": "Property", "value": "Calle Las Casas, 5, 38911 Frontera"},
  "capacity": {"type": "Property", "value": 45},
  "available": {"type": "Property", "value": $(randi 5 40), "observedAt": "${NOW}"},
  "EVspots": {"type": "Property", "value": 4},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:Neighborhood:Frontera"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [-18.0078, 27.7382]}}
}
JSON
)"

# ─────────────────────────────────────────
# 20. Transport — BusRoutes (2)
# ─────────────────────────────────────────
echo "Creating public transport..."

add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:BusRoute:Route-Norte",
  "type": "BusRoute",
  "name": {"type": "Property", "value": "Línea 1 — Valverde ↔ Frontera (HI-1 Norte)"},
  "routeNumber": {"type": "Property", "value": "L1"},
  "distance": {"type": "Property", "value": 28.5, "unitCode": "KMT"},
  "frequency": {"type": "Property", "value": 60, "unitCode": "MIN"},
  "operatingHours": {"type": "Property", "value": "07:00-21:00"},
  "electricFleet": {"type": "Property", "value": true}
}
JSON
)"

add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:BusRoute:Route-Sur",
  "type": "BusRoute",
  "name": {"type": "Property", "value": "Línea 2 — Valverde ↔ La Restinga (HI-3 Sur)"},
  "routeNumber": {"type": "Property", "value": "L2"},
  "distance": {"type": "Property", "value": 35.2, "unitCode": "KMT"},
  "frequency": {"type": "Property", "value": 90, "unitCode": "MIN"},
  "operatingHours": {"type": "Property", "value": "07:30-20:00"},
  "electricFleet": {"type": "Property", "value": true}
}
JSON
)"

# ─────────────────────────────────────────
# 21. Transport — BusStops (6)
# ─────────────────────────────────────────
BS_NAMES=("Valverde-Estacion" "Mocanal" "Tinor" "Frontera-Centro" "ElPinar" "LaRestinga")
BS_ADDRS=("Avenida Islas Canarias, 38900 Valverde" "Carretera HI-1, Mocanal, Valverde" "Carretera HI-1, Tiñor, Valverde" "Calle Tigaday, 38911 Frontera" "Carretera del Sur HI-3, 38912 El Pinar" "Calle Puerto, La Restinga, El Pinar")
BS_ROUTES=("Route-Norte" "Route-Norte" "Route-Norte" "Route-Norte" "Route-Sur" "Route-Sur")
BS_LNUMS=("L1" "L1" "L1" "L1" "L2" "L2")
BS_LONS=("-17.9108" "-17.9278" "-17.9038" "-18.0082" "-17.9748" "-17.9895")
BS_LATS=("27.8112" "27.8188" "27.7808" "27.7372" "27.7505" "27.6430")

for i in $(seq 0 5); do
  bpad=$(printf "%02d" "$((i+1))")
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:BusStop:BS${bpad}",
  "type": "BusStop",
  "name": {"type": "Property", "value": "Parada ${BS_NAMES[$i]}"},
  "address": {"type": "Property", "value": "${BS_ADDRS[$i]}"},
  "routeNumber": {"type": "Property", "value": "${BS_LNUMS[$i]}"},
  "nextArrival": {"type": "Property", "value": $(randi 1 58), "unitCode": "MIN", "observedAt": "${NOW}"},
  "shelter": {"type": "Property", "value": true},
  "accessible": {"type": "Property", "value": true},
  "onRoute": {"type": "Relationship", "object": "urn:ngsi-ld:BusRoute:${BS_ROUTES[$i]}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${BS_LONS[$i]}, ${BS_LATS[$i]}]}}
}
JSON
)"
done

# ─────────────────────────────────────────
# 22. Transport — Buses (3)
# ─────────────────────────────────────────
BUS_ROUTES=("Route-Norte" "Route-Norte" "Route-Sur")
BUS_STOPS=("BS01" "BS03" "BS05")
BUS_LONS=("-17.9215" "-17.9052" "-17.9750")
BUS_LATS=("27.8048" "27.7812" "27.7505")

for i in $(seq 1 3); do
  idx=$((i-1))
  bpad=$(printf "%02d" "$i")
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:Bus:Bus${bpad}",
  "type": "Bus",
  "name": {"type": "Property", "value": "Autobús Eléctrico ${bpad}"},
  "licensePlate": {"type": "Property", "value": "GC-0${bpad}0${bpad}-HI"},
  "capacity": {"type": "Property", "value": 40},
  "passengerCount": {"type": "Property", "value": $(randi 0 38), "observedAt": "${NOW}"},
  "speed": {"type": "Property", "value": $(randf 0 60), "unitCode": "KMH", "observedAt": "${NOW}"},
  "batteryLevel": {"type": "Property", "value": $(randf 20 100), "unitCode": "P1", "observedAt": "${NOW}"},
  "electricBus": {"type": "Property", "value": true},
  "onRoute": {"type": "Relationship", "object": "urn:ngsi-ld:BusRoute:${BUS_ROUTES[$idx]}"},
  "nearestStop": {"type": "Relationship", "object": "urn:ngsi-ld:BusStop:${BUS_STOPS[$idx]}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${BUS_LONS[$idx]}, ${BUS_LATS[$idx]}]}}
}
JSON
)"
done

# ─────────────────────────────────────────
# 23. Waste — WasteContainers (8)
# ─────────────────────────────────────────
echo "Creating waste management..."

WC_TYPES=("general" "organic" "plastic" "glass" "general" "organic" "plastic" "paper")
WC_ADDRS=("Calle Dr. Quintero Magdaleno, 5, 38900 Valverde" "Plaza de la Constitución, 38900 Valverde" "Calle San Francisco, 8, 38900 Valverde" "Avenida Islas Canarias, 12, 38900 Valverde" "Calle Tigaday, 3, 38911 Frontera" "Calle La Era, 9, 38911 Frontera" "Carretera del Sur HI-3 km 2, 38912 El Pinar" "Calle Los Mocanes, 11, 38912 El Pinar")
WC_HOODS=("Valverde" "Valverde" "Valverde" "Valverde" "Frontera" "Frontera" "ElPinar" "ElPinar")
WC_LONS=("-17.9115" "-17.9106" "-17.9120" "-17.9132" "-18.0090" "-18.0078" "-17.9748" "-17.9758")
WC_LATS=("27.8108" "27.8118" "27.8125" "27.8088" "27.7372" "27.7360" "27.7505" "27.7498")

for i in $(seq 0 7); do
  wpad=$(printf "%02d" "$((i+1))")
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:WasteContainer:WC${wpad}",
  "type": "WasteContainer",
  "name": {"type": "Property", "value": "Contenedor ${WC_TYPES[$i]} #${wpad}"},
  "address": {"type": "Property", "value": "${WC_ADDRS[$i]}"},
  "wasteType": {"type": "Property", "value": "${WC_TYPES[$i]}"},
  "fillLevel": {"type": "Property", "value": $(randf 10 95), "unitCode": "P1", "observedAt": "${NOW}"},
  "capacity": {"type": "Property", "value": 800, "unitCode": "LTR"},
  "lastCollected": {"type": "Property", "value": "${NOW}"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:Neighborhood:${WC_HOODS[$i]}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${WC_LONS[$i]}, ${WC_LATS[$i]}]}}
}
JSON
)"
done

# ─────────────────────────────────────────
# 24. Waste — WasteCollectionVehicles (2)
# ─────────────────────────────────────────
WCV_STATUS=("collecting" "idle")
WCV_LONS=("-17.9125" "-18.0082")
WCV_LATS=("27.8102" "27.7368")

for i in $(seq 1 2); do
  idx=$((i-1))
  vpad=$(printf "%02d" "$i")
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:WasteCollectionVehicle:WCV${vpad}",
  "type": "WasteCollectionVehicle",
  "name": {"type": "Property", "value": "Camión Recogida ${vpad}"},
  "licensePlate": {"type": "Property", "value": "GC-WCV${vpad}-HI"},
  "status": {"type": "Property", "value": "${WCV_STATUS[$idx]}"},
  "currentLoad": {"type": "Property", "value": $(randf 10 90), "unitCode": "P1", "observedAt": "${NOW}"},
  "fuelLevel": {"type": "Property", "value": $(randf 30 100), "unitCode": "P1"},
  "disposesAt": {"type": "Relationship", "object": "urn:ngsi-ld:WasteProcessingFacility:WPF-Valverde"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${WCV_LONS[$idx]}, ${WCV_LATS[$idx]}]}}
}
JSON
)"
done

# ─────────────────────────────────────────
# 25. Waste — WasteProcessingFacility (1)
# ─────────────────────────────────────────
add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:WasteProcessingFacility:WPF-Valverde",
  "type": "WasteProcessingFacility",
  "name": {"type": "Property", "value": "Punto Limpio El Hierro"},
  "address": {"type": "Property", "value": "Carretera HI-1, Polígono Industrial, 38900 Valverde"},
  "capacity": {"type": "Property", "value": 500, "unitCode": "TNE"},
  "currentLoad": {"type": "Property", "value": $(randf 10 70), "unitCode": "P1", "observedAt": "${NOW}"},
  "recyclingRate": {"type": "Property", "value": $(randf 50 80), "unitCode": "P1"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:Neighborhood:Valverde"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [-17.9165, 27.8055]}}
}
JSON
)"

# ─────────────────────────────────────────
# 26. Lighting — StreetLights (8)
# ─────────────────────────────────────────
echo "Creating street lighting..."

SLT_ADDRS=("Calle Dr. Quintero Magdaleno, 1, Valverde" "Plaza de la Constitución, 3, Valverde" "Calle San Francisco, 6, Valverde" "Avenida Islas Canarias, 20, Valverde" "Calle Tigaday, 5, Frontera" "Calle La Era, 12, Frontera" "Calle Los Mocanes, 8, El Pinar" "Carretera del Sur HI-3 km 3, El Pinar")
SLT_HOODS=("Valverde" "Valverde" "Valverde" "Valverde" "Frontera" "Frontera" "ElPinar" "ElPinar")
SLT_LONS=("-17.9110" "-17.9105" "-17.9118" "-17.9130" "-18.0088" "-18.0074" "-17.9745" "-17.9755")
SLT_LATS=("27.8110" "27.8118" "27.8126" "27.8090" "27.7368" "27.7358" "27.7508" "27.7500")
SLT_STATUS=("ok" "ok" "ok" "ok" "ok" "faulty" "ok" "ok")

for i in $(seq 0 7); do
  lpad=$(printf "%02d" "$((i+1))")
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:StreetLight:SLT${lpad}",
  "type": "StreetLight",
  "name": {"type": "Property", "value": "Farola LED ${lpad}"},
  "address": {"type": "Property", "value": "${SLT_ADDRS[$i]}"},
  "status": {"type": "Property", "value": "${SLT_STATUS[$i]}"},
  "intensity": {"type": "Property", "value": $(randi 0 100), "unitCode": "P1", "observedAt": "${NOW}"},
  "lampType": {"type": "Property", "value": "LED"},
  "powerConsumption": {"type": "Property", "value": $(randf 40 120), "unitCode": "WTT"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:Neighborhood:${SLT_HOODS[$i]}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${SLT_LONS[$i]}, ${SLT_LATS[$i]}]}}
}
JSON
)"
done

# ─────────────────────────────────────────
# 27. Smart Infra — ElectricVehicleChargers (5)
# ─────────────────────────────────────────
echo "Creating smart infrastructure..."

EVC_ADDRS=("Parking Municipal, Calle El Molino, 38900 Valverde" "Plaza de la Constitución, 38900 Valverde" "Parking Frontera, Calle Las Casas, 38911 Frontera" "Puerto de La Estaca, 38900 Valverde" "Carretera del Sur HI-3, 38912 El Pinar")
EVC_HOODS=("Valverde" "Valverde" "Frontera" "Valverde" "ElPinar")
EVC_STATUS=("available" "occupied" "available" "available" "occupied")
EVC_LONS=("-17.9120" "-17.9106" "-18.0075" "-17.8960" "-17.9752")
EVC_LATS=("27.8095" "27.8118" "27.7382" "27.7992" "27.7502")

for i in $(seq 0 4); do
  epad=$(printf "%02d" "$((i+1))")
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:ElectricVehicleCharger:EVC${epad}",
  "type": "ElectricVehicleCharger",
  "name": {"type": "Property", "value": "Cargador Vehículo Eléctrico ${epad}"},
  "address": {"type": "Property", "value": "${EVC_ADDRS[$i]}"},
  "status": {"type": "Property", "value": "${EVC_STATUS[$i]}"},
  "powerOutput": {"type": "Property", "value": $(randf 7.4 22), "unitCode": "KWT"},
  "chargingType": {"type": "Property", "value": "AC"},
  "energyDelivered": {"type": "Property", "value": $(randf 0 80), "unitCode": "KWH", "observedAt": "${NOW}"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:Neighborhood:${EVC_HOODS[$i]}"},
  "poweredBy": {"type": "Relationship", "object": "urn:ngsi-ld:PowerPlant:GoronaDelViento"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${EVC_LONS[$i]}, ${EVC_LATS[$i]}]}}
}
JSON
)"
done

# ─────────────────────────────────────────
# 28. Smart Infra — PublicWifiAccessPoints (4)
# ─────────────────────────────────────────
WIFI_ADDRS=("Plaza de la Constitución, 38900 Valverde" "Puerto de La Estaca, 38900 Valverde" "Calle Tigaday, 1, 38911 Frontera" "Puerto de La Restinga, 38912 El Pinar")
WIFI_HOODS=("Valverde" "Valverde" "Frontera" "ElPinar")
WIFI_LONS=("-17.9105" "-17.8960" "-18.0085" "-17.9892")
WIFI_LATS=("27.8118" "27.7990" "27.7370" "27.6435")

for i in $(seq 0 3); do
  wfpad=$(printf "%02d" "$((i+1))")
  add_entity "$(cat <<JSON
{
  "id": "urn:ngsi-ld:PublicWifiAccessPoint:WIFI${wfpad}",
  "type": "PublicWifiAccessPoint",
  "name": {"type": "Property", "value": "WiFi Público ${wfpad}"},
  "address": {"type": "Property", "value": "${WIFI_ADDRS[$i]}"},
  "status": {"type": "Property", "value": "active"},
  "ssid": {"type": "Property", "value": "ElHierro-WiFi-Libre"},
  "connectedUsers": {"type": "Property", "value": $(randi 0 45), "observedAt": "${NOW}"},
  "bandwidth": {"type": "Property", "value": $(randf 10 100), "unitCode": "MBT", "observedAt": "${NOW}"},
  "locatedIn": {"type": "Relationship", "object": "urn:ngsi-ld:Neighborhood:${WIFI_HOODS[$i]}"},
  "location": {"type": "GeoProperty", "value": {"type": "Point", "coordinates": [${WIFI_LONS[$i]}, ${WIFI_LATS[$i]}]}}
}
JSON
)"
done

# Flush remaining
flush_batch

echo ""
echo ""
echo "=== Done! Created ${count} / ${TOTAL} entities ==="
echo ""

# Quick verification
echo "Verifying via API..."
type_resp=$(curl -s "${COMMON_HEADERS[@]+"${COMMON_HEADERS[@]}"}"\
  "${API}/types")
echo "Entity types registered:"
echo "$type_resp" | python3 -m json.tool 2>/dev/null || echo "$type_resp"
