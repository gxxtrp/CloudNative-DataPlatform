"""Unit tests for Cloud-Native Data Contracts and Pydantic runtime models."""

import json
from datetime import UTC, datetime
from pathlib import Path

import jsonschema
import pytest
from linter import check_backward_compatibility, check_versioned_compatibility
from contracts.models import (
    DeadLetterPayload,
    OrderLifecycleEvent,
    OrderStatus,
    PaymentMethod,
    RiderStatus,
    RiderTelemetryEvent,
)
from pydantic import ValidationError


def load_schema(relative_path: str) -> dict:
    # Look relative to repo root or contracts/
    path = Path("contracts/schemas") / relative_path
    if not path.exists():
        path = Path(__file__).parent.parent / "schemas" / relative_path
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def test_order_lifecycle_event_valid():
    schema = load_schema("orders/orders.lifecycle.v1.json")

    event_dict = {
        "event_id": "11111111-2222-3333-4444-555555555555",
        "event_timestamp": "2026-09-06T12:00:00Z",
        "order_id": "ORD-BKK-90123",
        "order_status": "CREATED",
        "merchant_id": "MCH-TH-4819",
        "customer_id": "CUST-00912",
        "rider_id": None,
        "total_amount_baht": 350.50,
        "payment_method": "PROMPTPAY",
        "delivery_address": {
            "latitude": 13.7563,
            "longitude": 100.5018,
            "district": "Phra Nakhon",
            "province": "Bangkok"
        },
        "items": [
            {
                "item_id": "ITEM-101",
                "item_name": "Pad Thai with Prawns",
                "quantity": 2,
                "price_baht": 150.00
            },
            {
                "item_id": "ITEM-202",
                "item_name": "Thai Iced Tea",
                "quantity": 1,
                "price_baht": 50.50
            }
        ]
    }

    # Verify jsonschema validation
    jsonschema.validate(instance=event_dict, schema=schema)

    # Verify Pydantic model parsing
    model = OrderLifecycleEvent.model_validate(event_dict)
    assert model.order_id == "ORD-BKK-90123"
    assert model.order_status == OrderStatus.CREATED
    assert model.total_amount_baht == 350.50
    assert len(model.items) == 2


def test_order_lifecycle_negative_amount_fails():
    with pytest.raises(ValidationError):
        OrderLifecycleEvent(
            event_id="11111111-2222-3333-4444-555555555555",
            event_timestamp=datetime.now(UTC),
            order_id="ORD-001",
            order_status=OrderStatus.CREATED,
            merchant_id="MCH-001",
            customer_id="CUST-001",
            total_amount_baht=-50.0,  # Negative amount must fail
            payment_method=PaymentMethod.PROMPTPAY,
        )


def test_rider_telemetry_event_valid():
    schema = load_schema("riders/riders.telemetry.v1.json")

    telemetry_dict = {
        "event_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        "event_timestamp": "2026-09-06T12:00:15Z",
        "rider_id": "RDR-BKK-7788",
        "latitude": 13.7462,
        "longitude": 100.5347,
        "geohash": "w4rqpr1",
        "speed_kmh": 42.5,
        "heading_degrees": 180.0,
        "battery_level": 88,
        "rider_status": "DELIVERING_ORDER",
        "current_order_id": "ORD-BKK-90123"
    }

    # Verify jsonschema validation
    jsonschema.validate(instance=telemetry_dict, schema=schema)

    # Verify Pydantic model parsing
    model = RiderTelemetryEvent.model_validate(telemetry_dict)
    assert model.rider_id == "RDR-BKK-7788"
    assert model.rider_status == RiderStatus.DELIVERING_ORDER
    assert model.latitude == 13.7462


def test_rider_telemetry_invalid_coordinates():
    with pytest.raises(ValidationError):
        RiderTelemetryEvent(
            event_id="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            event_timestamp=datetime.now(UTC),
            rider_id="RDR-001",
            latitude=95.0,  # Latitude > 90 must fail
            longitude=100.0,
            geohash="w4rqpr1",
            rider_status=RiderStatus.AVAILABLE
        )


def test_dead_letter_payload_model():
    dlq = DeadLetterPayload(
        quarantine_id="QR-20260906-0001",
        source_topic="orders.lifecycle",
        error_type="SchemaViolation",
        error_message="Missing required field: customer_id",
        failure_timestamp=datetime.now(UTC),
        retry_count=0,
        raw_payload='{"order_id": "ORD-ERR"}'
    )
    assert dlq.quarantine_id == "QR-20260906-0001"
    assert dlq.retry_count == 0


def test_contract_linter_accepts_an_additive_optional_field():
    baseline = load_schema("orders/orders.lifecycle.v1.json")
    additive = json.loads(json.dumps(baseline))
    additive["properties"]["promotion_code"] = {"type": "string"}

    assert check_backward_compatibility(baseline, additive) == []
    assert check_versioned_compatibility(baseline, additive) == []


def test_contract_linter_rejects_a_breaking_change_without_major_version():
    baseline = load_schema("orders/orders.lifecycle.v1.json")
    breaking = json.loads(json.dumps(baseline))
    del breaking["properties"]["merchant_id"]
    breaking["metadata"]["version"] = "1.1.0"

    errors = check_versioned_compatibility(baseline, breaking)

    assert any("major version increase" in error for error in errors)
    assert any("merchant_id" in error for error in errors)


def test_order_lifecycle_v2_requires_the_versioned_envelope():
    schema = load_schema("orders/orders.lifecycle.v2.json")
    event_dict = {
        "event_id": "11111111-2222-3333-4444-555555555555",
        "event_timestamp": "2026-09-06T12:00:00Z",
        "schema_version": "2.0.0",
        "producer": "order-module",
        "order_id": "ORD-BKK-90123",
        "order_status": "CREATED",
        "merchant_id": "MCH-TH-4819",
        "customer_id": "CUST-00912",
        "total_amount_baht": 350.50,
        "payment_method": "PROMPTPAY",
    }

    jsonschema.validate(instance=event_dict, schema=schema)

    del event_dict["producer"]
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(instance=event_dict, schema=schema)
