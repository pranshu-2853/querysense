CREATE TABLE table_relationships (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_table_id     UUID NOT NULL REFERENCES registered_tables(id),
    from_column       VARCHAR(255) NOT NULL,
    to_table_id       UUID NOT NULL REFERENCES registered_tables(id),
    to_column         VARCHAR(255) NOT NULL,
    relationship_type VARCHAR(20) NOT NULL DEFAULT 'FK',
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
