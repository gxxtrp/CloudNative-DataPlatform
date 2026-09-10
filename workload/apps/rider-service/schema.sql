-- Schema for Rider Service (riders_db)
CREATE TABLE IF NOT EXISTS riders (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(128) NOT NULL,
    vehicle_type VARCHAR(32) DEFAULT 'MOTORCYCLE',
    status VARCHAR(32) DEFAULT 'OFFLINE',
    last_latitude NUMERIC(10, 6),
    last_longitude NUMERIC(10, 6),
    last_ping_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS rider_outbox (
    id BIGSERIAL PRIMARY KEY,
    event_id VARCHAR(64) UNIQUE NOT NULL,
    aggregate_id VARCHAR(64) NOT NULL,
    event_type VARCHAR(64) NOT NULL,
    payload JSONB NOT NULL,
    status VARCHAR(16) DEFAULT 'PENDING',
    retry_count INT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    published_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS idx_rider_outbox_pending ON rider_outbox (id) WHERE status = 'PENDING';
