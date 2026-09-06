# Workflow: Data Contract & Schema Evolution Governance

**Workflow ID**: `data-contract-schema-evolution`  
**Target Role**: Data Platform Engineer  
**Status**: DRAFT - Ready for Implementation  
**Category**: Data Governance & Developer Enablement  

---

## 1. Objective
Enforce strict data contracts between upstream microservices (Order Checkout, Merchant POS, Rider Dispatch App) and downstream analytical lakehouses. This workflow prevents breaking schema changes, enforces backward compatibility, and auto-generates runtime validation models for the streaming workers.

---

## 2. Trigger
- **Event Trigger (CI)**: Git pull request modifying or adding files under `contracts/schemas/**/*.json`.
- **Manual Trigger**: Developer runs `make contract-check` or `uv run python scripts/validate_contracts.py`.

---

## 3. Contract Specification & Directory Layout

### 3.1 Repository Structure
```
contracts/
├── schemas/
│   ├── orders/
│   │   ├── orders.lifecycle.v1.json
│   │   └── orders.lifecycle.v2.json
│   └── riders/
│       └── riders.telemetry.v1.json
└── generated/
    ├── __init__.py
    ├── orders_v1.py   # Auto-generated Pydantic Models
    └── riders_v1.py   # Auto-generated Pydantic Models
```

### 3.2 Canonical Contract Schema Definition
Every schema file MUST adhere to the Platform Data Contract Meta-Schema:
- `$schema`: Standard JSON Schema Draft-07
- `title`: Canonical event name (e.g. `OrderLifecycleEvent`)
- `metadata`:
  - `domain`: `food_delivery` | `rider_fleet` | `payment`
  - `owner_team`: e.g. `team-food-checkout@Platform.com`
  - `version`: Semantic version string (`1.0.0`)
  - `sla_freshness_seconds`: Maximum acceptable event latency (e.g. `60`)
- `properties`: Strongly-typed fields with `description` and formatting (e.g. ISO-8601 timestamps, geohash, positive decimals for currency).

---

## 4. Execution Steps (Autonomous Pipeline)

### Step 1: Meta-Schema & Syntax Validation
The CI runner scans all modified JSON schemas:
- Validates syntax against JSON Schema Draft-07.
- Asserts required metadata tags (`domain`, `owner_team`, `version`, `sla_freshness_seconds`).

### Step 2: Semantic Backward Compatibility Linter ("Push Right")
The validator fetches the baseline schema from the `main` branch:
```bash
uv run python scripts/contract_linter.py --target contracts/schemas/orders/orders.lifecycle.v1.json --baseline git:main
```
**Compatibility Rules Enforced**:
1. ❌ **Breaking**: Removal of any existing property.
2. ❌ **Breaking**: Modifying the `type` of an existing property (e.g., `integer` -> `string`).
3. ❌ **Breaking**: Adding a new required property without a default value.
4. ✅ **Compatible**: Adding an optional property or a field with an explicit default.
5. ✅ **Compatible**: Relaxing constraints (e.g., expanding enum options).

### Step 3: Pydantic Code Generation
If compatibility passes, the workflow automatically generates typed Python models into `contracts/generated/`:
```bash
uv run datamodel-codegen --input contracts/schemas/orders/orders.lifecycle.v1.json --output contracts/generated/orders_v1.py --input-file-type jsonschema
```

---

## 5. Checkpoint & Decision Brief

### Checkpoint Rule
If the change is 100% backward compatible, CI passes autonomously. If a **Breaking Change** is detected, the workflow blocks merge and posts an **Impact Brief** requiring human Data Platform Lead approval.

### Brief Format
```markdown
### ⚠️ Data Contract Evolution Brief: BREAKING CHANGE DETECTED
- **Target Contract**: `contracts/schemas/orders/orders.lifecycle.v1.json`
- **Owner Team**: `team-food-checkout@Platform.com`
- **Incompatible Changes**:
  - ❌ Deleted Field: `payment_method` (was required by Silver Reconciliation mart)
  - ❌ Changed Type: `total_amount_baht` from `number` to `string`
- **Downstream Lakehouse Impact**:
  - Table `s3://Platform-silver-lakehouse/silver_orders_state` will fail ingestion.
  - Table `s3://Platform-gold-lakehouse/gold_daily_merchant_payouts` will miss payment attributes.
- **Recommended Remediation**:
  1. Restore `payment_method` as deprecated optional.
  2. If type change is required, issue a new major contract version: `orders.lifecycle.v2.json`.
- **Action Required**: Data Platform Lead override [Approve Migration / Reject]?
```

---

## 6. Automated Verification & Definition of Done

1. **Self-Validation**: `make contract-test` validates all schemas in `contracts/schemas/` without syntax errors.
2. **Backward Compatibility Assertion**: Running compatibility check against simulated mutations correctly flags breaking changes and passes non-breaking ones.
3. **Artifact Generation**: Generated Pydantic files in `contracts/generated/` compile cleanly with `mypy --strict`.
