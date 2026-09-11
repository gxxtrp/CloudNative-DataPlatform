-- Staging model for trips
-- Source: Iceberg table via BigLake

{{ config(
    materialized='view',
    schema='silver'
) }}

WITH source AS (
    SELECT * FROM {{ source('silver', 'trips') }}
),

renamed AS (
    SELECT
        -- IDs
        trip_id,
        rider_id,
        driver_id,
        
        -- Status
        status,
        CASE 
            WHEN status = 'COMPLETED' THEN TRUE 
            ELSE FALSE 
        END AS is_completed,
        CASE 
            WHEN status = 'CANCELLED' THEN TRUE 
            ELSE FALSE 
        END AS is_cancelled,
        
        -- Location
        pickup_lat,
        pickup_lng,
        dropoff_lat,
        dropoff_lng,
        city_id,
        
        -- Timestamps
        requested_at,
        matched_at,
        started_at,
        completed_at,
        cancelled_at,
        
        -- Measures
        COALESCE(fare_usd, 0) AS fare_usd,
        COALESCE(surge_multiplier, 1.0) AS surge_multiplier,
        distance_miles,
        duration_minutes,
        
        -- Metadata
        _cdc_timestamp,
        _processed_at

    FROM source
    WHERE 
        -- Exclude soft deletes
        _cdc_operation != 'd'
)

SELECT * FROM renamed
