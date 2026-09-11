-- Fact table for trips
-- Grain: One row per trip

{{ config(
    materialized='incremental',
    unique_key='trip_id',
    partition_by={
        'field': 'trip_date',
        'data_type': 'date',
        'granularity': 'day'
    },
    cluster_by=['city_id', 'is_completed']
) }}

WITH trips AS (
    SELECT * FROM {{ ref('stg_trips') }}
    {% if is_incremental() %}
    WHERE requested_at > (SELECT MAX(requested_at) FROM {{ this }})
    {% endif %}
),

users AS (
    SELECT * FROM {{ ref('stg_users') }}
    WHERE is_current = TRUE
),

drivers AS (
    SELECT * FROM {{ ref('stg_drivers') }}
    WHERE is_current = TRUE
),

final AS (
    SELECT
        -- Surrogate key
        {{ dbt_utils.generate_surrogate_key(['t.trip_id']) }} AS trip_key,
        
        -- Natural key
        t.trip_id,
        
        -- Dimension keys
        u.user_key AS rider_key,
        d.driver_key,
        t.city_id AS pickup_city_key,
        DATE(t.requested_at) AS trip_date,
        
        -- Measures
        t.fare_usd,
        t.surge_multiplier,
        t.distance_miles,
        t.duration_minutes,
        
        -- Calculated measures
        ROUND(t.fare_usd * 0.75, 2) AS driver_payout_usd,
        ROUND(t.fare_usd * 0.25, 2) AS platform_fee_usd,
        
        -- Flags
        t.is_completed,
        t.is_cancelled,
        
        -- Timestamps
        t.requested_at,
        t.completed_at,
        
        -- Audit
        CURRENT_TIMESTAMP() AS _loaded_at

    FROM trips t
    LEFT JOIN users u ON t.rider_id = u.user_id
    LEFT JOIN drivers d ON t.driver_id = d.driver_id
)

SELECT * FROM final
