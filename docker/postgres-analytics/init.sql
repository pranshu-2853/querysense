-- Analytics Database Initialization
-- Creates the analytics schema, roles, and sample tables.
-- Runs once when the postgres-analytics container is first created.

-- ============================================================
-- 1. Create analytics schema tables
-- ============================================================

CREATE TABLE customers (
    id          SERIAL PRIMARY KEY,
    first_name  VARCHAR(100) NOT NULL,
    last_name   VARCHAR(100) NOT NULL,
    email       VARCHAR(255) UNIQUE NOT NULL,
    city        VARCHAR(100),
    country     VARCHAR(100) DEFAULT 'US',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE products (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(255) NOT NULL,
    category    VARCHAR(100) NOT NULL,
    price       NUMERIC(10, 2) NOT NULL,
    stock_qty   INTEGER NOT NULL DEFAULT 0,
    is_active   BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE orders (
    id              SERIAL PRIMARY KEY,
    customer_id     INTEGER NOT NULL REFERENCES customers(id),
    status          VARCHAR(50) NOT NULL DEFAULT 'pending',
    total_amount    NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    order_date      TIMESTAMPTZ NOT NULL DEFAULT now(),
    shipped_date    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE order_items (
    id          SERIAL PRIMARY KEY,
    order_id    INTEGER NOT NULL REFERENCES orders(id),
    product_id  INTEGER NOT NULL REFERENCES products(id),
    quantity    INTEGER NOT NULL DEFAULT 1,
    unit_price  NUMERIC(10, 2) NOT NULL,
    total_price NUMERIC(10, 2) NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 2. Create read-only role for query execution
-- ============================================================

CREATE ROLE querysense_readonly WITH LOGIN PASSWORD 'readonly_password';
GRANT SELECT ON TABLE orders TO querysense_readonly;
GRANT SELECT ON TABLE order_items TO querysense_readonly;
GRANT SELECT ON TABLE products TO querysense_readonly;
GRANT SELECT ON TABLE customers TO querysense_readonly;
-- DO NOT: GRANT SELECT ON ALL TABLES IN SCHEMA public TO querysense_readonly
ALTER ROLE querysense_readonly SET statement_timeout = '10s';

-- ============================================================
-- 3. Create introspection role for schema discovery
-- ============================================================

CREATE ROLE querysense_introspect WITH LOGIN PASSWORD 'introspect_password';
GRANT SELECT ON ALL TABLES IN SCHEMA information_schema TO querysense_introspect;
GRANT SELECT ON ALL TABLES IN SCHEMA pg_catalog TO querysense_introspect;
-- This role is NEVER used for query execution
