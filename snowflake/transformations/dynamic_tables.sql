-- snowflake/transformations/dynamic_tables.sql
-- Dynamic tables: Revenue, Ops, NPS, Exec Scorecard (90 day rolling window)

CREATE OR REPLACE DYNAMIC TABLE TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_REVENUE_DAILY(
  SALES_DATE,
  TRUCK_ID,
  TRUCK_NAME,
  ORDERS_CNT,
  REVENUE,
  AVG_ORDER_VALUE
)
TARGET_LAG = '1 hour'
WAREHOUSE = TB_PG_OPS_WH_01
AS
SELECT
  DATE_TRUNC('DAY', o.order_ts)::DATE AS sales_date,
  o.truck_id,
  t.truck_name,
  COUNT(*) AS orders_cnt,
  SUM(o.total) AS revenue,
  AVG(o.total) AS avg_order_value
FROM TASTY_BYTES_V2."foodtruck"."order_header" o
JOIN TASTY_BYTES_V2."foodtruck"."truck" t
  ON o.truck_id = t.truck_id
GROUP BY 1,2,3;

CREATE OR REPLACE DYNAMIC TABLE TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_OPS_DAILY
TARGET_LAG = '5 minutes'
WAREHOUSE = TB_PG_OPS_WH_01
AS
SELECT
  DATE_TRUNC('DAY', e.event_ts)::DATE AS ops_date,
  e.truck_id,
  t.truck_name,
  AVG(IFF(e.event_type='SPEED_KMH', e.amount, NULL)) AS avg_speed_kmh,
  SUM(IFF(e.event_type='IDLE_MIN', e.amount, 0))     AS idle_minutes,
  SUM(IFF(e.event_type='FUEL_GALLONS', e.amount, 0)) AS fuel_gallons,
  AVG(IFF(e.event_type='FRIDGE_TEMP_C', e.amount, NULL)) AS avg_fridge_temp_c,
  SUM(IFF(e.event_type='MAINT_COST', e.amount, 0))   AS maint_cost
FROM TASTY_BYTES_ICEBERG_DB.FOODTRUCK.FOODTRUCK_EVENTS_ICEBERG e
JOIN TASTY_BYTES_V2."foodtruck"."truck" t
  ON e.truck_id = t.truck_id
WHERE e.event_ts IS NOT NULL
GROUP BY 1,2,3;

CREATE OR REPLACE DYNAMIC TABLE TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_NPS_DAILY(
  REVIEW_DATE,
  TRUCK_ID,
  TRUCK_NAME,
  REVIEWS_CNT,
  PROMOTERS_CNT,
  PASSIVES_CNT,
  DETRACTORS_CNT,
  NPS_SCORE,
  AVG_RATING_1_10
)
TARGET_LAG = '1 hour'
WAREHOUSE = TB_PG_OPS_WH_01
AS
SELECT
  DATE_TRUNC('DAY', r.review_ts)::DATE AS review_date,
  r.truck_id,
  t.truck_name,
  COUNT(*) AS reviews_cnt,
  SUM(IFF(r.rating >= 9, 1, 0)) AS promoters_cnt,
  SUM(IFF(r.rating BETWEEN 7 AND 8, 1, 0)) AS passives_cnt,
  SUM(IFF(r.rating <= 6, 1, 0)) AS detractors_cnt,
  ROUND(
    ( (SUM(IFF(r.rating >= 9, 1, 0))::FLOAT / NULLIF(COUNT(*),0)) -
      (SUM(IFF(r.rating <= 6, 1, 0))::FLOAT / NULLIF(COUNT(*),0)) ) * 100
  , 2) AS nps_score,
  ROUND(AVG(r.rating), 2) AS avg_rating_1_10
FROM TASTY_BYTES_V2."foodtruck"."review" r
JOIN TASTY_BYTES_V2."foodtruck"."truck" t
  ON r.truck_id = t.truck_id
GROUP BY 1,2,3;

-- Exec Scorecard (90-day rolling window, FULL refresh)
CREATE OR REPLACE DYNAMIC TABLE TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_EXEC_DAILY_SCORECARD(
  DAY,
  TRUCK_ID,
  TRUCK_NAME,
  ORDERS_CNT,
  REVENUE,
  AVG_ORDER_VALUE,
  AVG_SPEED_KMH,
  IDLE_MINUTES,
  FUEL_GALLONS,
  AVG_FRIDGE_TEMP_C,
  MAINT_COST,
  REVIEWS_CNT,
  NPS_SCORE,
  AVG_RATING_1_10
)
TARGET_LAG = '1 hour'
WAREHOUSE = TB_PG_OPS_WH_01
REFRESH_MODE = FULL
INITIALIZE = ON_CREATE
AS
WITH keys AS (
  SELECT sales_date AS day, truck_id
  FROM TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_REVENUE_DAILY
  UNION
  SELECT ops_date AS day, truck_id
  FROM TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_OPS_DAILY
  UNION
  SELECT review_date AS day, truck_id
  FROM TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_NPS_DAILY
),
keys_90d AS (
  SELECT day, truck_id
  FROM keys
  WHERE day >= DATEADD('day', -90, CURRENT_DATE())
)
SELECT
  k.day::DATE AS day,
  k.truck_id,
  t.truck_name,
  COALESCE(r.orders_cnt, 0) AS orders_cnt,
  COALESCE(r.revenue, 0)    AS revenue,
  r.avg_order_value,
  o.avg_speed_kmh,
  o.idle_minutes,
  o.fuel_gallons,
  o.avg_fridge_temp_c,
  o.maint_cost,
  n.reviews_cnt,
  n.nps_score,
  n.avg_rating_1_10
FROM keys_90d k
JOIN TASTY_BYTES_V2."foodtruck"."truck" t
  ON t.truck_id = k.truck_id
LEFT JOIN TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_REVENUE_DAILY r
  ON r.sales_date = k.day AND r.truck_id = k.truck_id
LEFT JOIN TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_OPS_DAILY o
  ON o.ops_date = k.day AND o.truck_id = k.truck_id
LEFT JOIN TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_NPS_DAILY n
  ON n.review_date = k.day AND n.truck_id = k.truck_id;
