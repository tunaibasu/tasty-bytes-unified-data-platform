# Kafka Validation (Demo)

Goal: **prove the exact message you produced exists in Kafka**, without accidentally reading older messages for the same truck.

## 0) Confirm topic partitions
```bash
docker exec -it kafka bash -lc 'kafka-topics --bootstrap-server kafka:29092 --describe --topic foodtruck_events'
```

## 1) Produce demo events
Option A (script):
```bash
bash kafka/producers/telemetry_producer.sh
```

Option B (inline):
```bash
docker exec -i kafka bash -lc 'cat <<EOF | kafka-console-producer   --bootstrap-server kafka:29092   --topic foodtruck_events
{"EVENT_TS":"2026-01-06T18:00:00Z","TRUCK_ID":"cf3cd082-dc1f-4134-9c3a-02ea90998db8","EVENT_TYPE":"SPEED_KMH","AMOUNT":62.50}
{"EVENT_TS":"2026-01-06T18:00:10Z","TRUCK_ID":"cf3cd082-dc1f-4134-9c3a-02ea90998db8","EVENT_TYPE":"FUEL_GALLONS","AMOUNT":1.25}
{"EVENT_TS":"2026-01-06T18:00:20Z","TRUCK_ID":"cf3cd082-dc1f-4134-9c3a-02ea90998db8","EVENT_TYPE":"IDLE_MIN","AMOUNT":3.00}
{"EVENT_TS":"2026-01-06T18:00:30Z","TRUCK_ID":"cf3cd082-dc1f-4134-9c3a-02ea90998db8","EVENT_TYPE":"FRIDGE_TEMP_C","AMOUNT":3.90}
{"EVENT_TS":"2026-01-06T18:00:40Z","TRUCK_ID":"cf3cd082-dc1f-4134-9c3a-02ea90998db8","EVENT_TYPE":"MAINT_COST","AMOUNT":12.75}
EOF'
```

## 2) Find the **latest offsets** per partition
This is the clean way to “tail” messages without scanning the entire topic.

```bash
docker exec -it kafka bash -lc '
for p in 0 1 2; do
  echo "Partition $p:";
  kafka-console-consumer     --bootstrap-server kafka:29092     --topic foodtruck_events     --partition $p     --offset latest     --max-messages 1     --property print.partition=true     --property print.offset=true     --property print.timestamp=true 2>/dev/null || true;
done
'
```

> If you see nothing, it means no message landed in that partition since you last checked.
> Run step (1) again and re-run this step.

## 3) Read the **last N messages** from each partition and grep for your exact timestamp
Because your topic has historical data for the same TRUCK_ID, search by **EVENT_TS=2026-01-06T18:00**.

```bash
docker exec -it kafka bash -lc '
for p in 0 1 2; do
  echo "=== Partition $p (tail) ===";
  timeout 8s kafka-console-consumer     --bootstrap-server kafka:29092     --topic foodtruck_events     --partition $p     --offset latest     --property print.partition=true     --property print.offset=true     --property print.timestamp=true 2>/dev/null   | grep -E "2026-01-06T18:00|cf3cd082-dc1f-4134-9c3a-02ea90998db8" || true;
done
'
```

## 4) (Optional) From-beginning search (slow but works)
```bash
docker exec -it kafka bash -lc 'timeout 20s kafka-console-consumer   --bootstrap-server kafka:29092   --topic foodtruck_events   --from-beginning   --property print.partition=true   --property print.offset=true   --property print.timestamp=true 2>/dev/null | grep -m 5 "2026-01-06T18:00"'
```

