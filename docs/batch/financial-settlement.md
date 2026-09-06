# Batch: Daily Merchant Financial Settlement & Quality Gates

**Domain**: Merchant Financial & Analytics Engineering (`apps/settlement-engine`)  
**Scope**: Two-Sided Ledger Reconciliation, Zero-Tolerance Quality Gates & Gold Mart Publishing  

---

## 1. Batch DAG Orchestration

The daily settlement pipeline executes as an Argo Workflows DAG (`argo-workflows` in namespace `argo-workflow`), performing automated two-sided financial reconciliation:

```mermaid
flowchart TD
    DAG_START([Argo Workflows: daily-settlement-pipeline]) --> S1[Step 1: Read Delivered Orders from Bronze Parquet]
    DAG_START --> S2[Step 2: Ingest External Payment Gateway Ledger]

    S1 & S2 --> RECON[Step 3: Two-Sided Ledger Reconciliation Engine]

    subgraph Ledger["Financial Calculations"]
        RECON --> GMV[Calculate Gross Merchandise Value GMV]
        RECON --> COMM[Compute 30% Platform Commission]
        RECON --> VAT[Apply 7% VAT on Commission]
        RECON --> NET[Compute Net Merchant Payout]
    end

    NET --> GATES{Quality Gatekeeper<br/>Assertions}

    subgraph Assertions["Zero-Tolerance Financial Invariants"]
        GATES -->|Check 1| A1[NO_NEGATIVE_PAYOUTS: Payouts >= 0.00 THB]
        GATES -->|Check 2| A2[GMV_CONSERVATION: Total GMV = Comm + Payout + VAT]
        GATES -->|Check 3| A3[NO_NULL_MERCHANTS: 100% valid merchant IDs]
        GATES -->|Check 4| A4[UNIQUE_MERCHANT_PER_DAY: Primary key uniqueness]
    end

    A1 & A2 & A3 & A4 -->|ALL PASSED| PUB[Step 4: Publish to Gold Mart<br/>s3://lakehouse-gold/marts/daily_merchant_payout/]
    GATES -->|ANY FAILED| HALT[HALT Pipeline & Trigger P1 SRE Alert]
```

---

## 2. Financial Ledger Formulae

For each merchant $m$ on settlement date $D$:
1. **Gross Merchandise Value (GMV)**: $\sum \text{order.total\_amount}$ for all `DELIVERED` orders.
2. **Platform Commission (30%)**: $\text{GMV} \times 0.30$.
3. **VAT on Commission (7%)**: $\text{Commission} \times 0.07$.
4. **Net Merchant Payout**: $\text{GMV} - \text{Commission} - \text{VAT}$.

---

## 3. Quality Gate Output Audit Log

```text
┌─────────────────────────┬────────┬──────────────────────────────────────────┐
│ Quality Assertion Rule  │ Status │ Detail                                   │
├─────────────────────────┼────────┼──────────────────────────────────────────┤
│ NO_NEGATIVE_PAYOUTS     │ PASSED │ All merchant payouts are >= 0.00 THB     │
│ GMV_CONSERVATION        │ PASSED │ GMV perfectly reconciles (GMV = Comm + P)│
│ NO_NULL_MERCHANTS       │ PASSED │ 100% of records have valid merchant IDs  │
│ UNIQUE_MERCHANT_PER_DAY │ PASSED │ Primary key uniqueness verified          │
└─────────────────────────┴────────┴──────────────────────────────────────────┘

✔ Quality Gate PASSED: Gold snapshot approved for downstream Merchant POS publishing.
```
