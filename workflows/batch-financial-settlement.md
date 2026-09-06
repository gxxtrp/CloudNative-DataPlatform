# Workflow: Daily Merchant Financial Settlement & Reconciliation

**Workflow ID**: `batch-financial-settlement`  
**Target Domain**: Merchant Financial Settlement & Quality Gates  
**Status**: APPROVED - Ready for Implementation  
**Owning Team**: Merchant Financial & Analytics Engineering (`apps/settlement-engine`)  

---

## 1. Objective

Execute automated daily batch financial reconciliation between delivered customer orders (read from Lakehouse Bronze S3 Parquet) and external payment gateway settlement records (read from `s3://lakehouse-bronze/payment-gateway/`). Calculate merchant Gross Merchandise Value (GMV), 30% platform commission, VAT, delivery subsidies, and Net Merchant Payout. Enforce financial quality gates (zero negative payouts, zero orphaned payments) and publish the verified Gold Mart snapshot (`s3://lakehouse-gold/marts/daily_merchant_payout/`).

---

## 2. Trigger & Orchestration

- **Trigger**: Argo Workflows scheduled CronWorkflow (Daily at `02:00 UTC`), or manual trigger via `argo submit`.
- **DAG WorkflowTemplate**: `Platform-daily-settlement-pipeline` in namespace `batch`.

```
┌────────────────────────────────────────────────────────┐
│ Argo Workflows Orchestrator DAG                        │
│                                                        │
│  [Step 1: Ingest Payment Gateway Drop]                 │
│         │                                              │
│         ▼                                              │
│  [Step 2: Two-Sided Financial Reconciliation (Go)]     │
│         │ - Join Delivered Orders vs Payment Ledger    │
│         │ - Compute Commission, VAT, Net Payout        │
│         ▼                                              │
│  [Step 3: Quality Gatekeeper Assertions]               │
│         │ - Assert: Negative Payout Count == 0         │
│         │ - Assert: Orphaned Payment Count == 0        │
│         │ - Assert: Total GMV Discrepancy == 0         │
│         ▼                                              │
│  [Step 4: Publish Gold Mart & Decision Brief]          │
│           - Parquet: s3://lakehouse-gold/marts/        │
│           - Decision Brief artifact to Finance/SRE     │
└────────────────────────────────────────────────────────┘
```

---

## 3. Financial Calculation Rules

For each merchant $m$ on settlement date $D$:
1. **Gross Merchandise Value (GMV)**: $\sum \text{order.amount}$ for all completed orders.
2. **Platform Commission (30%)**: $\text{GMV} \times 0.30$.
3. **VAT on Commission (7%)**: $\text{Commission} \times 0.07$.
4. **Net Merchant Payout**: $\text{GMV} - \text{Commission} - \text{VAT}$.

---

## 4. Definition of Done

An implementer agent completes this workflow when:
1. `apps/settlement-engine` compiles as an autonomous Go container with its own `Dockerfile`.
2. Argo Workflows DAG runs the Go binary inside a batch container with parameters `--date YYYY-MM-DD`.
3. Quality gates halt the workflow with a non-zero exit code if an anomalous negative payout or unmatched transaction is detected.
4. Clean runs write the final Parquet mart to `s3://lakehouse-gold/marts/daily_merchant_payout/date=YYYY-MM-DD/` and generate an execution brief.
