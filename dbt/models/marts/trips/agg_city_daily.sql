-- Daily city-level aggregations
-- Grain: One row per city per day

{{ config(
    materialized='table',
    partition_by={
        'field': 'trip_date',
        'data_type': 'date',
        'granularity': 'day'
    }
) }}

WITH trips AS (
    SELECT * FROM {{ ref('fact_trips') }}
),

aggregated AS (
    SELECT
        trip_date,
        pickup_city_key AS city_key,
        
        -- Counts
        COUNT(*) AS total_trips,
        COUNTIF(is_completed) AS completed_trips,
        COUNTIF(is_cancelled) AS cancelled_trips,
        
        -- Revenue
        SUM(fare_usd) AS gross_bookings_usd,
        SUM(driver_payout_usd) AS driver_payouts_usd,
        SUM(platform_fee_usd) AS platform_revenue_usd,
        
        -- Averages
        ROUND(AVG(fare_usd), 2) AS avg_fare_usd,
        ROUND(AVG(surge_multiplier), 2) AS avg_surge,
        ROUND(AVG(distance_miles), 2) AS avg_distance_miles,
        ROUND(AVG(duration_minutes), 2) AS avg_duration_minutes,
        
        -- Unique counts
        COUNT(DISTINCT rider_key) AS unique_riders,
        COUNT(DISTINCT driver_key) AS unique_drivers,
        
        -- Rates
        ROUND(SAFE_DIVIDE(COUNTIF(is_completed), COUNT(*)), 4) AS completion_rate,
        ROUND(SAFE_DIVIDE(COUNTIF(is_cancelled), COUNT(*)), 4) AS cancellation_rate,
        
        -- Audit
        CURRENT_TIMESTAMP() AS _loaded_at

    FROM trips
    GROUP BY trip_date, pickup_city_key
)

SELECT * FROM aggregated
