# Tasty Bytes – Unified Data Platform (Snowflake + Postgres + Kafka + Iceberg)

This repo contains the end-to-end data engineering assets used for the **Tasty Bytes Unified Data Platform** interview presentation + live demo:
- Postgres transactional data generation (orders / order_items / optional delivery)
- Kafka telemetry event producer + validation steps
- Snowflake ingestion + transformations (Bronze → Silver → Iceberg + Gold Dynamic Tables → KPI Views)
- Governance (roles, safe views, Horizon tags)
- Cortex Analyst semantic models for KPI views
- Demo runbook (step-by-step “before → generate → validate”)

> Note: Some Snowflake objects (e.g., Postgres Connector app configuration) are created in Snowsight UI / Connector setup wizard.
> The repo documents the SQL objects used downstream (tables, streams, tasks, DTs, views).

## Quick links
- `demo/demo_runbook.md` – full click-by-click demo flow
- `snowflake/ingestion/` – Kafka → Raw → Typed → Iceberg objects
- `snowflake/transformations/` – Dynamic Tables + KPI Views
- `kafka/producers/` – producer scripts + sample JSON payloads
- `postgres/data_generation/` – SQL scripts to generate new orders

