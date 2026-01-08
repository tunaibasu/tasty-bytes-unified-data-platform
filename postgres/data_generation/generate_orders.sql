-- generate_orders.sql
-- Purpose: Generate new order_header + order_item (and optional delivery) rows for demo dates.
-- Tested against table structures you shared:
--  - foodtruck.order_header (requires: order_channel, order_status, subtotal/tax/tip/total NOT NULL)
--  - foodtruck.order_item uses menu_item.base_price (not mi.price)

-- =========================
-- Parameters (edit as needed)
-- =========================
-- Date range (UTC)
-- Example: 2026-01-04 .. 2026-01-05
DO $$
DECLARE
  v_start_ts timestamptz := '2026-01-04 00:00:00+00';
  v_end_ts   timestamptz := '2026-01-05 23:59:59+00';
  v_orders   integer     := 1500;  -- number of orders to generate
BEGIN
  RAISE NOTICE 'Generating % orders between % and %', v_orders, v_start_ts, v_end_ts;
END $$;

-- =========================
-- Generate orders + items
-- =========================
DO $$
DECLARE
  v_start_ts timestamptz := '2026-01-04 00:00:00+00';
  v_end_ts   timestamptz := '2026-01-05 23:59:59+00';
  v_orders   integer     := 1500;

  v_order_id uuid;
  v_truck_id uuid;
  v_customer_id uuid;
  v_menu_item_id uuid;
  v_item_name text;
  v_unit_price numeric(10,2);
  v_qty int;
  v_subtotal numeric(10,2);
  v_tax numeric(10,2);
  v_tip numeric(10,2);
  v_total numeric(10,2);
  v_order_ts timestamptz;
  v_channel text;
  v_status text;
  v_payment text;
  v_items int;
  i int;
  j int;
BEGIN
  FOR i IN 1..v_orders LOOP
    v_order_id := gen_random_uuid();

    -- random existing truck
    SELECT truck_id INTO v_truck_id
    FROM foodtruck.truck
    ORDER BY random()
    LIMIT 1;

    -- random customer (nullable allowed)
    SELECT customer_id INTO v_customer_id
    FROM foodtruck.customer
    ORDER BY random()
    LIMIT 1;

    -- random timestamp in range
    v_order_ts := v_start_ts + (random() * (v_end_ts - v_start_ts));

    -- required enumerations
    v_channel := (ARRAY['walkup','app','delivery'])[1 + floor(random()*3)];
    v_status  := (ARRAY['placed','paid','fulfilled'])[1 + floor(random()*3)];
    v_payment := (ARRAY['card','cash','mobile','gift'])[1 + floor(random()*4)];

    -- items per order 1..4
    v_items := 1 + floor(random()*4);

    v_subtotal := 0;
    FOR j IN 1..v_items LOOP
      -- pick a menu_item from any menu (simpler and works even if menu/truck mapping is sparse)
      SELECT mi.menu_item_id, mi.item_name, mi.base_price
      INTO v_menu_item_id, v_item_name, v_unit_price
      FROM foodtruck.menu_item mi
      ORDER BY random()
      LIMIT 1;

      v_qty := 1 + floor(random()*3);

      INSERT INTO foodtruck.order_item(
        order_item_id, order_id, menu_item_id, item_name_raw, qty, unit_price, line_total
      )
      VALUES (
        gen_random_uuid(), v_order_id, v_menu_item_id, v_item_name, v_qty, v_unit_price,
        ROUND((v_unit_price * v_qty)::numeric, 2)
      );

      v_subtotal := v_subtotal + ROUND((v_unit_price * v_qty)::numeric, 2);
    END LOOP;

    v_tax := ROUND((v_subtotal * 0.085)::numeric, 2);
    v_tip := ROUND((v_subtotal * (CASE WHEN v_channel='walkup' THEN 0.05 ELSE 0.10 END))::numeric, 2);
    v_total := v_subtotal + v_tax + v_tip;

    INSERT INTO foodtruck.order_header(
      order_id, truck_id, customer_id, order_ts,
      order_channel, order_status, subtotal, tax, tip, total, payment_method
    )
    VALUES (
      v_order_id, v_truck_id, v_customer_id, v_order_ts,
      v_channel, v_status, v_subtotal, v_tax, v_tip, v_total, v_payment
    );

    -- optional: delivery row if channel=delivery
    IF v_channel = 'delivery' THEN
      INSERT INTO foodtruck.delivery(
        delivery_id, order_id, prep_time_min, delivery_time_min, distance_km
      )
      VALUES (
        gen_random_uuid(), v_order_id,
        (5 + floor(random()*20))::int,
        (10 + floor(random()*50))::int,
        ROUND((0.5 + random()*8)::numeric, 3)
      )
      ON CONFLICT (order_id) DO NOTHING;
    END IF;
  END LOOP;
END $$;

-- =========================
-- Validation queries
-- =========================
-- Orders created in range
SELECT
  DATE_TRUNC('day', order_ts) AS day,
  COUNT(*) AS orders,
  SUM(total) AS revenue
FROM foodtruck.order_header
WHERE order_ts >= '2026-01-04 00:00:00+00'
  AND order_ts <  '2026-01-06 00:00:00+00'
GROUP BY 1
ORDER BY 1;

