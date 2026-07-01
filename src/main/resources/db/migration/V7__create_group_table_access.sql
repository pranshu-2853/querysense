CREATE TABLE group_table_access (
    group_id    UUID NOT NULL REFERENCES data_access_groups(id) ON DELETE CASCADE,
    table_id    UUID NOT NULL REFERENCES registered_tables(id) ON DELETE CASCADE,
    granted_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (group_id, table_id)
);
