CREATE TABLE registered_columns (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_id         UUID NOT NULL REFERENCES registered_tables(id) ON DELETE CASCADE,
    column_name      VARCHAR(255) NOT NULL,
    data_type        VARCHAR(100) NOT NULL,
    is_nullable      BOOLEAN NOT NULL DEFAULT true,
    column_default   TEXT,
    description      TEXT,
    is_pii           BOOLEAN NOT NULL DEFAULT false,
    ordinal_position INTEGER NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(table_id, column_name)
);
