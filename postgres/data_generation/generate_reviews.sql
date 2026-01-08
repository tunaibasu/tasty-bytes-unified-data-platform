-- generate_reviews.sql (optional)
-- Generates new reviews with ratings 1-10 and optional free-text.
-- Use only if you want fresh NPS beyond the existing dataset.

DO $$
DECLARE
  v_start_ts timestamptz := '2026-01-04 00:00:00+00';
  v_end_ts   timestamptz := '2026-01-05 23:59:59+00';
  v_reviews  integer     := 200; -- adjust
  i int;
  v_review_id uuid;
  v_truck_id uuid;
  v_customer_id uuid;
  v_ts timestamptz;
  v_rating int;
  v_source text;
  v_useful int;
  v_text text;
BEGIN
  FOR i IN 1..v_reviews LOOP
    v_review_id := gen_random_uuid();

    SELECT truck_id INTO v_truck_id
    FROM foodtruck.truck ORDER BY random() LIMIT 1;

    SELECT customer_id INTO v_customer_id
    FROM foodtruck.customer ORDER BY random() LIMIT 1;

    v_ts := v_start_ts + (random() * (v_end_ts - v_start_ts));
    v_rating := 1 + floor(random()*10);
    v_source := (ARRAY['yelp','app','google'])[1 + floor(random()*3)];
    v_useful := floor(random()*5);
    v_text := CASE
      WHEN v_rating >= 9 THEN 'Great food and quick service!'
      WHEN v_rating >= 7 THEN 'Good overall, would come again.'
      WHEN v_rating >= 5 THEN 'Average experience.'
      ELSE 'Not satisfied, needs improvement.'
    END;

    INSERT INTO foodtruck.review(
      review_id, truck_id, customer_id, review_ts, rating, review_text, source, useful_count
    )
    VALUES (
      v_review_id, v_truck_id, v_customer_id, v_ts, v_rating, v_text, v_source, v_useful
    );
  END LOOP;
END $$;

-- Validate
SELECT DATE_TRUNC('day', review_ts) AS day, COUNT(*) cnt, AVG(rating) avg_rating
FROM foodtruck.review
WHERE review_ts >= '2026-01-04 00:00:00+00'
  AND review_ts <  '2026-01-06 00:00:00+00'
GROUP BY 1
ORDER BY 1;
