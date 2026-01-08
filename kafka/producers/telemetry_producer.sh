#!/usr/bin/env bash
set -euo pipefail

# telemetry_producer.sh
# Usage:
#   ./telemetry_producer.sh
# Assumes:
#   - you have a docker container named "kafka"
#   - broker inside docker network is kafka:29092
#   - topic: foodtruck_events

docker exec -i kafka bash -lc 'cat <<EOF | kafka-console-producer   --bootstrap-server kafka:29092   --topic foodtruck_events
{"EVENT_TS":"2026-01-06T18:00:00Z","TRUCK_ID":"cf3cd082-dc1f-4134-9c3a-02ea90998db8","EVENT_TYPE":"SPEED_KMH","AMOUNT":62.50}
{"EVENT_TS":"2026-01-06T18:00:10Z","TRUCK_ID":"cf3cd082-dc1f-4134-9c3a-02ea90998db8","EVENT_TYPE":"FUEL_GALLONS","AMOUNT":1.25}
{"EVENT_TS":"2026-01-06T18:00:20Z","TRUCK_ID":"cf3cd082-dc1f-4134-9c3a-02ea90998db8","EVENT_TYPE":"IDLE_MIN","AMOUNT":3.00}
{"EVENT_TS":"2026-01-06T18:00:30Z","TRUCK_ID":"cf3cd082-dc1f-4134-9c3a-02ea90998db8","EVENT_TYPE":"FRIDGE_TEMP_C","AMOUNT":3.90}
{"EVENT_TS":"2026-01-06T18:00:40Z","TRUCK_ID":"cf3cd082-dc1f-4134-9c3a-02ea90998db8","EVENT_TYPE":"MAINT_COST","AMOUNT":12.75}
EOF'
echo "✅ Produced 5 telemetry events to foodtruck_events"
