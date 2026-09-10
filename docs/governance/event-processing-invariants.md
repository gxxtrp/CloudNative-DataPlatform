# Event Processing Invariants

## Scope

These invariants define the interface between Product publishers and the Data Platform. They apply to Order Lifecycle and Rider Telemetry contracts from v2 onward.

## Publisher obligations

- Every Lifecycle Event and Rider Telemetry record has an immutable `event_id`. Retrying publication must reuse it.
- Every record states its `schema_version` and `producer`.
- `event_timestamp` is the UTC time at which the business fact occurred, not the time a processor received it.
- Order Lifecycle events use `order_id` as their ordering key. Rider Telemetry uses `rider_id` as its ordering key.
- A Product publisher commits operational state and its outbox record atomically. Publication retry occurs from the outbox after that commit.

## Data Platform obligations

- Intake validates the declared contract version before a record enters curated data.
- Intake is idempotent by `event_id`; a retry must not create a second logical record.
- Invalid input becomes a Quarantine Record containing the source topic, reason, raw input, failure time, and replay eligibility.
- Raw history is immutable and partitioned by contract family and event date. Curated data remains reproducible from raw history.
- A replay has an operation identifier and cannot overwrite the evidence that caused quarantine.

## Quality and publication

- Curated Order data permits only defined Order Lifecycle states.
- Merchant Daily Settlement publishes only after uniqueness, source-freshness, GMV-conservation, and non-negative payout checks pass.
- A failing quality check blocks publication and emits an actionable alert with a runbook link.

## Service objectives

| Signal | Initial objective | Alert condition |
|---|---:|---|
| Order Lifecycle freshness | 30 seconds | p95 exceeds 30 seconds for 10 minutes |
| Rider Telemetry freshness | 15 seconds | p95 exceeds 15 seconds for 10 minutes |
| Quarantine rate | under 0.1% | exceeds 0.1% for 10 minutes |
| Settlement publication | daily by 08:00 ICT | missing or quality gate failed |
