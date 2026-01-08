# Postgres Data Generation (Demo)

Scripts here generate **new transactional data** in Postgres so the Snowflake KPIs (Revenue/AOV) continue beyond the historical window.

- `generate_orders.sql` – generates orders + order_items for a chosen date range
- `generate_reviews.sql` – (optional) generate new reviews (if you want fresh NPS too)

> Tip: run in pgAdmin with **autocommit ON** (or run each DO $$ block independently) to avoid "transaction is aborted" issues.
