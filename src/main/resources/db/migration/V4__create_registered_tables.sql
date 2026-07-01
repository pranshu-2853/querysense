CREATE TABLE registered_tables (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    schema_name     VARCHAR(255) NOT NULL DEFAULT 'public',
    table_name      VARCHAR(255) NOT NULL,
    description     TEXT,
    row_count_est   BIGINT,
    is_whitelisted  BOOLEAN NOT NULL DEFAULT false,
    last_synced_at  TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(schema_name, table_name)
);
