# Demo Runbook – Tasty Bytes Unified Data Platform (End-to-End)

This runbook is designed for a **live interview demo**:
- generate new data in **Postgres** (Revenue keeps updating after 2026-01-03)
- generate new data in **Kafka** (Ops telemetry)
- validate end-to-end in **Snowflake** (Raw → Typed → Iceberg → DTs → KPI Views)

---

## 0) Pre-flight (make sure pipelines are running)

### 0.1 Snowflake: warehouses + tasks + DTs
In Snowsight Worksheet:

```sql
-- Ensure warehouse is resumable
SHOW WAREHOUSES LIKE 'TB_PG_OPS_WH_01';
SHOW WAREHOUSES LIKE 'SNOWFLAKE_LEARNING_WH';

-- Kafka tasks
SHOW TASKS IN SCHEMA TASTY_BYTES_ICEBERG_DB.FOODTRUCK;

-- Resume tasks if paused
ALTER TASK TASTY_BYTES_ICEBERG_DB.FOODTRUCK.FOODTRUCK_EVENTS_TYPED_TASK RESUME;
ALTER TASK TASTY_BYTES_ICEBERG_DB.FOODTRUCK.FOODTRUCK_EVENTS_ICEBERG_TASK RESUME;

-- Dynamic tables status
SHOW DYNAMIC TABLES IN SCHEMA TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS;

-- (Optional) refresh if needed
ALTER DYNAMIC TABLE TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_EXEC_DAILY_SCORECARD REFRESH;
```

---

## A) Postgres demo: Generate new orders (Revenue)

### A1) Run Postgres generator
In pgAdmin, open:

`postgres/data_generation/generate_orders.sql`

**Important:** turn **autocommit ON** (or run each `DO $$ ... $$;` block one at a time).

Run the script.

### A2) Validate Postgres data
```sql
SELECT
  DATE_TRUNC('day', order_ts) AS day,
  COUNT(*) AS orders,
  SUM(total) AS revenue
FROM foodtruck.order_header
WHERE order_ts >= '2026-01-04 00:00:00+00'
  AND order_ts <  '2026-01-06 00:00:00+00'
GROUP BY 1
ORDER BY 1;
```

### A3) Validate Snowflake picked up the new orders
In Snowflake:

```sql
-- base replicated table
SELECT
  DATE_TRUNC('day', order_ts)::DATE AS day,
  COUNT(*) AS orders,
  SUM(total) AS revenue
FROM TASTY_BYTES_V2."foodtruck"."order_header"
WHERE order_ts >= '2026-01-04'::TIMESTAMP_NTZ
GROUP BY 1
ORDER BY 1 DESC;

-- revenue DT
SELECT sales_date, SUM(revenue) AS revenue, SUM(orders_cnt) AS orders
FROM TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_REVENUE_DAILY
WHERE sales_date >= '2026-01-04'::DATE
GROUP BY 1
ORDER BY 1 DESC;

-- exec DT rollup
SELECT day, SUM(revenue) AS revenue
FROM TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_EXEC_DAILY_SCORECARD
WHERE day >= '2026-01-03'::DATE
GROUP BY 1
ORDER BY 1 DESC;
```

---

## B) Kafka demo: Generate telemetry + validate in Kafka

### B1) Produce telemetry events
Option A: run script
```bash
bash kafka/producers/telemetry_producer.sh
```

Option B: inline producer
```bash
docker exec -i kafka bash -lc 'cat <<EOF | kafka-console-producer   --bootstrap-server kafka:29092   --topic foodtruck_events
{"EVENT_TS":"2026-01-06T18:00:00Z","TRUCK_ID":"cf3cd082-dc1f-4134-9c3a-02ea90998db8","EVENT_TYPE":"SPEED_KMH","AMOUNT":62.50}
{"EVENT_TS":"2026-01-06T18:00:10Z","TRUCK_ID":"cf3cd082-dc1f-4134-9c3a-02ea90998db8","EVENT_TYPE":"FUEL_GALLONS","AMOUNT":1.25}
{"EVENT_TS":"2026-01-06T18:00:20Z","TRUCK_ID":"cf3cd082-dc1f-4134-9c3a-02ea90998db8","EVENT_TYPE":"IDLE_MIN","AMOUNT":3.00}
{"EVENT_TS":"2026-01-06T18:00:30Z","TRUCK_ID":"cf3cd082-dc1f-4134-9c3a-02ea90998db8","EVENT_TYPE":"FRIDGE_TEMP_C","AMOUNT":3.90}
{"EVENT_TS":"2026-01-06T18:00:40Z","TRUCK_ID":"cf3cd082-dc1f-4134-9c3a-02ea90998db8","EVENT_TYPE":"MAINT_COST","AMOUNT":12.75}
EOF'
```

### B2) Validate *exact* events in Kafka
Because the topic already contains historical events for the same TRUCK_ID, validate using the **EVENT_TS=2026-01-06T18:00** signature.

```bash
docker exec -it kafka bash -lc '
for p in 0 1 2; do
  echo "=== Partition $p (search) ===";
  timeout 20s kafka-console-consumer     --bootstrap-server kafka:29092     --topic foodtruck_events     --partition $p     --from-beginning     --property print.partition=true     --property print.offset=true     --property print.timestamp=true 2>/dev/null   | grep -E "2026-01-06T18:00" || true;
done
'
```

> This prints the **exact messages** you produced (by timestamp), even if the truck_id existed historically.

---

## C) Snowflake demo: Validate Kafka → Raw → Typed → Iceberg → DTs → KPI Views

### C1) Raw table shows new records (Variant)
```sql
SELECT
  COUNT(*) AS raw_rows,
  MAX(RECORD_CONTENT:"EVENT_TS"::STRING) AS max_event_ts
FROM TASTY_BYTES_ICEBERG_DB.FOODTRUCK.FOODTRUCK_EVENTS_RAW_V2
WHERE RECORD_CONTENT:"EVENT_TS"::STRING LIKE '2026-01-06T18:00%';
```

### C2) Typed table shows parsed + metadata fields
```sql
SELECT
  COUNT(*) AS typed_rows,
  MIN(event_ts) AS min_ts,
  MAX(event_ts) AS max_ts
FROM TASTY_BYTES_ICEBERG_DB.FOODTRUCK.FOODTRUCK_EVENTS_TYPED
WHERE truck_id = 'cf3cd082-dc1f-4134-9c3a-02ea90998db8'
  AND event_ts >= '2026-01-06 18:00:00'::TIMESTAMP_NTZ
  AND event_ts <  '2026-01-06 18:01:00'::TIMESTAMP_NTZ;

SELECT *
FROM TASTY_BYTES_ICEBERG_DB.FOODTRUCK.FOODTRUCK_EVENTS_TYPED
WHERE truck_id = 'cf3cd082-dc1f-4134-9c3a-02ea90998db8'
  AND event_ts >= '2026-01-06 18:00:00'::TIMESTAMP_NTZ
ORDER BY event_ts
LIMIT 10;
```

### C3) Iceberg table shows persisted telemetry
```sql
SELECT
  COUNT(*) AS iceberg_rows,
  MIN(event_ts) AS min_ts,
  MAX(event_ts) AS max_ts
FROM TASTY_BYTES_ICEBERG_DB.FOODTRUCK.FOODTRUCK_EVENTS_ICEBERG
WHERE truck_id = 'cf3cd082-dc1f-4134-9c3a-02ea90998db8'
  AND event_ts >= '2026-01-06 18:00:00'::TIMESTAMP_NTZ
  AND event_ts <  '2026-01-06 18:01:00'::TIMESTAMP_NTZ;
```

### C4) Ops DT rollups updated
```sql
SELECT
  ops_date,
  truck_id,
  avg_speed_kmh,
  idle_minutes,
  fuel_gallons,
  avg_fridge_temp_c,
  maint_cost
FROM TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_OPS_DAILY
WHERE truck_id = 'cf3cd082-dc1f-4134-9c3a-02ea90998db8'
ORDER BY ops_date DESC
LIMIT 10;
```

### C5) KPI Views show updated outputs
```sql
-- ops exceptions view
SELECT *
FROM TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.V_OPS_EXCEPTIONS_DAILY
WHERE truck_id = 'cf3cd082-dc1f-4134-9c3a-02ea90998db8'
ORDER BY day DESC
LIMIT 20;

-- revenue view (after Postgres generation)
SELECT *
FROM TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.V_REVENUE_DAILY
WHERE day >= '2026-01-03'::DATE
ORDER BY day DESC
LIMIT 10;

-- top trucks view
SELECT *
FROM TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.V_TOP_TRUCKS_REVENUE
WHERE window IN ('7D','30D','90D')
QUALIFY revenue_rank <= 10
ORDER BY window_days, revenue_rank;
```

---

## D) Cost control (pause/resume after demo)

```sql
-- Pause tasks
ALTER TASK TASTY_BYTES_ICEBERG_DB.FOODTRUCK.FOODTRUCK_EVENTS_TYPED_TASK SUSPEND;
ALTER TASK TASTY_BYTES_ICEBERG_DB.FOODTRUCK.FOODTRUCK_EVENTS_ICEBERG_TASK SUSPEND;

-- Suspend warehouse to stop compute
ALTER WAREHOUSE TB_PG_OPS_WH_01 SUSPEND;
ALTER WAREHOUSE SNOWFLAKE_LEARNING_WH SUSPEND;

-- Dynamic tables can be suspended (optional)
ALTER DYNAMIC TABLE TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_EXEC_DAILY_SCORECARD SUSPEND;
ALTER DYNAMIC TABLE TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_REVENUE_DAILY SUSPEND;
ALTER DYNAMIC TABLE TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_OPS_DAILY SUSPEND;
ALTER DYNAMIC TABLE TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_NPS_DAILY SUSPEND;

-- Resume later (when you want)
-- ALTER DYNAMIC TABLE ... RESUME;
-- ALTER TASK ... RESUME;
-- ALTER WAREHOUSE ... RESUME;
```

