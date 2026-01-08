-- snowflake/transformations/kpi_views.sql
-- Views built on top of DT_EXEC_DAILY_SCORECARD

-- Daily revenue (all trucks combined)
CREATE OR REPLACE VIEW TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.V_REVENUE_DAILY(
  DAY,
  ORDERS_CNT,
  REVENUE,
  AOV
) WITH TAG (
  TASTY_BYTES_ANALYTICS.GOVERNANCE.DOMAIN='SALES',
  TASTY_BYTES_ANALYTICS.GOVERNANCE.LAYER='PRESENTATION',
  TASTY_BYTES_ANALYTICS.GOVERNANCE.OWNER_TEAM='MARKETING',
  TASTY_BYTES_ANALYTICS.GOVERNANCE.SENSITIVITY='INTERNAL'
)
AS
SELECT
  day,
  SUM(orders_cnt)  AS orders_cnt,
  SUM(revenue)     AS revenue,
  DIV0(SUM(revenue), SUM(orders_cnt)) AS aov
FROM TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_EXEC_DAILY_SCORECARD
GROUP BY 1
ORDER BY day DESC;

-- Weighted NPS daily (all trucks combined)
CREATE OR REPLACE VIEW TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.V_NPS_DAILY(
  DAY,
  REVIEWS_CNT,
  NPS_SCORE_WEIGHTED,
  AVG_RATING_1_10
) WITH TAG (
  TASTY_BYTES_ANALYTICS.GOVERNANCE.DOMAIN='NPS',
  TASTY_BYTES_ANALYTICS.GOVERNANCE.LAYER='PRESENTATION',
  TASTY_BYTES_ANALYTICS.GOVERNANCE.OWNER_TEAM='MARKETING',
  TASTY_BYTES_ANALYTICS.GOVERNANCE.SENSITIVITY='PII'
)
AS
SELECT
  day,
  SUM(reviews_cnt) AS reviews_cnt,
  ROUND(
    (
      (SUM(IFF(nps_score IS NOT NULL, (nps_score/100.0) * reviews_cnt, 0)) / NULLIF(SUM(reviews_cnt),0))
      * 100
    )
  , 2) AS nps_score_weighted,
  ROUND(AVG(avg_rating_1_10), 2) AS avg_rating_1_10
FROM TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_EXEC_DAILY_SCORECARD
GROUP BY 1
ORDER BY day DESC;

-- Ops exceptions daily
CREATE OR REPLACE VIEW TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.V_OPS_EXCEPTIONS_DAILY(
  DAY,
  TRUCK_ID,
  TRUCK_NAME,
  AVG_SPEED_KMH,
  IDLE_MINUTES,
  FUEL_GALLONS,
  AVG_FRIDGE_TEMP_C,
  MAINT_COST,
  FLAG_FRIDGE_WARM,
  FLAG_EXCESS_IDLE,
  FLAG_HIGH_MAINT_COST
) WITH TAG (
  TASTY_BYTES_ANALYTICS.GOVERNANCE.DOMAIN='OPS_TELEMETRY',
  TASTY_BYTES_ANALYTICS.GOVERNANCE.LAYER='PRESENTATION',
  TASTY_BYTES_ANALYTICS.GOVERNANCE.OWNER_TEAM='OPS',
  TASTY_BYTES_ANALYTICS.GOVERNANCE.SENSITIVITY='INTERNAL'
)
AS
SELECT
  day,
  truck_id,
  truck_name,
  avg_speed_kmh,
  idle_minutes,
  fuel_gallons,
  avg_fridge_temp_c,
  maint_cost,
  IFF(avg_fridge_temp_c IS NOT NULL AND avg_fridge_temp_c > 8, TRUE, FALSE)  AS flag_fridge_warm,
  IFF(idle_minutes IS NOT NULL AND idle_minutes > 240, TRUE, FALSE)          AS flag_excess_idle,
  IFF(maint_cost IS NOT NULL AND maint_cost > 500, TRUE, FALSE)              AS flag_high_maint_cost
FROM TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_EXEC_DAILY_SCORECARD
WHERE
  (avg_fridge_temp_c IS NOT NULL AND avg_fridge_temp_c > 8)
  OR (idle_minutes IS NOT NULL AND idle_minutes > 240)
  OR (maint_cost IS NOT NULL AND maint_cost > 500);

-- Top trucks by revenue (7/30/90)
CREATE OR REPLACE VIEW TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.V_TOP_TRUCKS_REVENUE(
  WINDOW_DAYS,
  WINDOW,
  TRUCK_ID,
  TRUCK_NAME,
  ORDERS_CNT,
  REVENUE,
  AOV,
  REVENUE_RANK
)
AS
WITH allw AS (
  SELECT 7  AS window_days, '7D'  AS window, * EXCLUDE(window) FROM (
    SELECT
      '7D' AS window, truck_id, truck_name,
      SUM(orders_cnt) AS orders_cnt,
      SUM(revenue) AS revenue,
      SUM(revenue)/NULLIF(SUM(orders_cnt),0) AS aov
    FROM TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_EXEC_DAILY_SCORECARD
    WHERE day >= DATEADD('day', -7, CURRENT_DATE)
    GROUP BY 1,2,3
  )
  UNION ALL
  SELECT 30 AS window_days, '30D' AS window, * EXCLUDE(window) FROM (
    SELECT
      '30D' AS window, truck_id, truck_name,
      SUM(orders_cnt) AS orders_cnt,
      SUM(revenue) AS revenue,
      SUM(revenue)/NULLIF(SUM(orders_cnt),0) AS aov
    FROM TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_EXEC_DAILY_SCORECARD
    WHERE day >= DATEADD('day', -30, CURRENT_DATE)
    GROUP BY 1,2,3
  )
  UNION ALL
  SELECT 90 AS window_days, '90D' AS window, * EXCLUDE(window) FROM (
    SELECT
      '90D' AS window, truck_id, truck_name,
      SUM(orders_cnt) AS orders_cnt,
      SUM(revenue) AS revenue,
      SUM(revenue)/NULLIF(SUM(orders_cnt),0) AS aov
    FROM TASTY_BYTES_ANALYTICS.FINAL_ANALYTICS.DT_EXEC_DAILY_SCORECARD
    WHERE day >= DATEADD('day', -90, CURRENT_DATE)
    GROUP BY 1,2,3
  )
)
SELECT
  window_days,
  window,
  truck_id,
  truck_name,
  orders_cnt,
  ROUND(revenue,2) AS revenue,
  ROUND(aov,8) AS aov,
  DENSE_RANK() OVER (PARTITION BY window ORDER BY revenue DESC) AS revenue_rank
FROM allw;

