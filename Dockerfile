# syntax=docker/dockerfile:1
FROM postgres:17 AS base

# Build stage for compiling extensions from source
FROM base AS builder

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    postgresql-server-dev-17 \
    git \
    cmake \
    curl \
    wget \
    ca-certificates \
    libssl-dev \
    libkrb5-dev \
    && rm -rf /var/lib/apt/lists/*

# Build pg_cron 1.6.5 (latest stable for scheduled jobs)
RUN git clone https://github.com/citusdata/pg_cron.git --branch v1.6.5 --depth 1 \
    && cd pg_cron \
    && make && make install

# Build temporal_tables 1.2.2 (for audit trails and temporal data)
RUN git clone https://github.com/arkhipov/temporal_tables.git --branch v1.2.2 --depth 1 \
    && cd temporal_tables \
    && make && make install

# Build pg_partman 5.1.0 (for partition management)
RUN git clone https://github.com/pgpartman/pg_partman.git --branch v5.1.0 --depth 1 \
    && cd pg_partman \
    && make && make install

# Build HyperLogLog 2.18 (for cardinality estimation in financial analytics)
RUN git clone https://github.com/citusdata/postgresql-hll.git --branch v2.18 --depth 1 \
    && cd postgresql-hll \
    && make && make install

# Build TopN (for frequent pattern analysis)
RUN git clone https://github.com/citusdata/postgresql-topn.git --depth 1 \
    && cd postgresql-topn \
    && make && make install

# Build pg_wait_sampling (for wait event analysis)
RUN git clone https://github.com/postgrespro/pg_wait_sampling.git --depth 1 \
    && cd pg_wait_sampling \
    && make USE_PGXS=1 && make USE_PGXS=1 install

# Final production stage
FROM base AS production

ENV DEBIAN_FRONTEND=noninteractive \
    OPENSSL_ia32cap=0

# Install necessary tools (no recommends so ca-certificates isn't pulled)
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    lsb-release \
    gnupg \
 && rm -rf /var/lib/apt/lists/*

# Install all extensions in one layer
RUN apt-get update && apt-get install -y \
    postgresql-17-pgvector \
    postgresql-17-pgaudit \
    postgresql-17-pg-stat-kcache \
    postgresql-17-pg-qualstats \
    postgresql-17-similarity \
    postgresql-17-debversion \
    postgresql-17-ip4r \
    postgresql-17-jsquery \
    postgresql-17-numeral \
    postgresql-17-prefix \
    postgresql-17-rational \
    postgresql-17-unit \
    postgresql-17-timescaledb \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*


# Copy compiled extensions from builder
COPY --from=builder /usr/lib/postgresql/17/lib/*.so /usr/lib/postgresql/17/lib/
COPY --from=builder /usr/share/postgresql/17/extension/* /usr/share/postgresql/17/extension/

# Create runtime dirs (keep PGDATA empty; archive dir created at runtime)
RUN mkdir -p /docker-entrypoint-initdb.d \
    && mkdir -p /usr/share/postgresql/17 \
    && chown -R postgres:postgres /var/lib/postgresql

# PostgreSQL configuration for financial workloads
RUN mkdir -p /usr/local/share/postgresql \
    && cat > /usr/local/share/postgresql/postgresql.conf.sample <<EOF
# PostgreSQL 17 Configuration for Financial Reconciliation and Search

# Connection Settings
listen_addresses = '*'
max_connections = 200
superuser_reserved_connections = 3

# Memory Settings (adjust based on available RAM)
shared_buffers = 1GB
effective_cache_size = 3GB
maintenance_work_mem = 256MB
work_mem = 16MB
wal_buffers = 16MB

# Checkpoint Settings
checkpoint_completion_target = 0.9
checkpoint_timeout = 15min
max_wal_size = 4GB
min_wal_size = 1GB

# WAL and Replication Configuration
wal_level = replica
max_wal_senders = 5
max_replication_slots = 5
wal_keep_size = 1GB
archive_mode = on
archive_command = 'test ! -f $PGDATA/wal_archive/%f && cp %p $PGDATA/wal_archive/%f'
wal_compression = lz4

# PostgreSQL 17 specific optimizations
vacuum_buffer_usage_limit = 256kB
io_combine_limit = 128kB
summarize_wal = on

# Extension Loading
shared_preload_libraries = 'pg_stat_statements,pg_cron,pgaudit,pg_stat_kcache,pg_qualstats,pg_wait_sampling,timescaledb'

# Extension Configuration
cron.database_name = 'postgres'
cron.timezone = 'UTC'

# pgAudit Configuration for Financial Compliance
pgaudit.log = 'write, ddl, role'
pgaudit.log_catalog = off
pgaudit.log_relation = on
pgaudit.log_parameter = on

# Query Monitoring
pg_stat_statements.track = all
pg_stat_statements.max = 10000
compute_query_id = on

# Performance Monitoring
pg_stat_kcache.track = 'top'
pg_qualstats.enabled = true
pg_qualstats.track_constants = true
pg_qualstats.sample_rate = 0.1
pg_wait_sampling.history_size = 10000

# TimescaleDB
timescaledb.max_background_workers = 8

# Query Planning
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
parallel_tuple_cost = 0.1
parallel_setup_cost = 1000

# Logging
logging_collector = on
log_directory = 'pg_log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_line_prefix = '%m [%p] %q%u@%d '
log_statement = 'ddl'
log_duration = off
log_min_duration_statement = 1000
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_temp_files = 0

# Auto-explain for slow queries
session_preload_libraries = 'auto_explain'
auto_explain.log_min_duration = '1s'
auto_explain.log_analyze = true
auto_explain.log_buffers = true
auto_explain.log_format = 'json'

# Locale and Formatting
lc_messages = 'en_US.utf8'
lc_monetary = 'en_US.utf8'
lc_numeric = 'en_US.utf8'
lc_time = 'en_US.utf8'
default_text_search_config = 'pg_catalog.english'
EOF

# Ensure WAL archive directory exists at runtime (before SQL init scripts)
RUN printf '%s\n' '#!/bin/sh' \
  'set -e' \
  'mkdir -p "$PGDATA/wal_archive"' \
  'chown -R postgres:postgres "$PGDATA/wal_archive"' \
  > /docker-entrypoint-initdb.d/00-create-wal-archive.sh \
  && chmod +x /docker-entrypoint-initdb.d/00-create-wal-archive.sh

# Create initialization script for extensions
RUN cat > /docker-entrypoint-initdb.d/01-extensions.sql <<'EOF'
-- Core Extensions
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Search Extensions
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
CREATE EXTENSION IF NOT EXISTS vector;

-- Financial and Audit Extensions
CREATE EXTENSION IF NOT EXISTS pgaudit;
CREATE EXTENSION IF NOT EXISTS temporal_tables;
CREATE EXTENSION IF NOT EXISTS hll;
CREATE EXTENSION IF NOT EXISTS topn;

-- Partitioning
CREATE SCHEMA IF NOT EXISTS partman;
CREATE EXTENSION IF NOT EXISTS pg_partman SCHEMA partman;

-- Time-series
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Monitoring
CREATE EXTENSION IF NOT EXISTS pg_stat_kcache;
CREATE EXTENSION IF NOT EXISTS pg_qualstats;
CREATE EXTENSION IF NOT EXISTS pg_wait_sampling;

-- Scheduled Jobs (requires database specification)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- JSON Processing
CREATE EXTENSION IF NOT EXISTS jsquery;

-- Full-text Search Configurations
CREATE TEXT SEARCH CONFIGURATION financial (COPY = english);
ALTER TEXT SEARCH CONFIGURATION financial
    ALTER MAPPING FOR asciiword, word WITH unaccent, english_stem;
EOF

# Create health check script
RUN cat > /usr/local/bin/health-check.sh <<'EOF'
#!/bin/bash
set -eo pipefail

host="$(hostname --ip-address || echo '127.0.0.1')"
user="${POSTGRES_USER:-postgres}"
db="${POSTGRES_DB:-$POSTGRES_USER}"
export PGPASSWORD="${POSTGRES_PASSWORD:-}"

pg_isready --host "$host" --username "$user" --dbname "$db" --quiet

psql --host "$host" --username "$user" --dbname "$db" --quiet --no-align --tuples-only \
    --command "SELECT 1;" > /dev/null

psql --host "$host" --username "$user" --dbname "$db" --quiet --no-align --tuples-only \
    --command "SELECT count(*) FROM pg_extension;" > /dev/null

echo "Health check passed"
EOF

RUN chmod +x /usr/local/bin/health-check.sh

# Create financial-specific database initialization
RUN cat > /docker-entrypoint-initdb.d/02-financial-setup.sql <<'EOF'
-- Create schemas for financial data organization
CREATE SCHEMA IF NOT EXISTS reconciliation;
CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS archive;

-- Create custom types for financial data
CREATE TYPE currency_code AS ENUM ('USD', 'EUR', 'GBP', 'JPY', 'CHF', 'CAD', 'AUD', 'CNY');

-- Create base tables with proper data types
CREATE TABLE IF NOT EXISTS reconciliation.accounts (
    account_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_number VARCHAR(50) UNIQUE NOT NULL,
    account_name TEXT NOT NULL,
    account_type VARCHAR(50) NOT NULL,
    currency currency_code NOT NULL DEFAULT 'USD',
    balance NUMERIC(19,4) NOT NULL DEFAULT 0,
    last_reconciled TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT positive_balance CHECK (balance >= 0)
);

-- Create indexes for search performance
CREATE INDEX idx_accounts_name_trgm ON reconciliation.accounts 
    USING gin (account_name gin_trgm_ops);
CREATE INDEX idx_accounts_number ON reconciliation.accounts 
    USING btree (account_number);
CREATE INDEX idx_accounts_type ON reconciliation.accounts 
    USING btree (account_type);

-- Enable row-level security for multi-tenant support
ALTER TABLE reconciliation.accounts ENABLE ROW LEVEL SECURITY;

-- Create audit trigger function
CREATE OR REPLACE FUNCTION audit.log_changes() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit.change_log(table_name, operation, new_data, changed_by)
        VALUES (TG_TABLE_NAME, TG_OP, row_to_json(NEW), current_user);
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit.change_log(table_name, operation, old_data, new_data, changed_by)
        VALUES (TG_TABLE_NAME, TG_OP, row_to_json(OLD), row_to_json(NEW), current_user);
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit.change_log(table_name, operation, old_data, changed_by)
        VALUES (TG_TABLE_NAME, TG_OP, row_to_json(OLD), current_user);
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create audit log table
CREATE TABLE IF NOT EXISTS audit.change_log (
    id BIGSERIAL PRIMARY KEY,
    table_name TEXT NOT NULL,
    operation TEXT NOT NULL,
    old_data JSONB,
    new_data JSONB,
    changed_by TEXT NOT NULL,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create index on audit log
CREATE INDEX idx_audit_log_table_time ON audit.change_log(table_name, changed_at DESC);

-- Schedule regular maintenance jobs with pg_cron
SELECT cron.schedule('vacuum-analyze', '0 2 * * *', 'VACUUM ANALYZE;');
SELECT cron.schedule('reindex-concurrent', '0 3 * * 0', 'REINDEX DATABASE CONCURRENTLY postgres;');
SELECT cron.schedule('update-statistics', '0 */6 * * *', 'ANALYZE;');
EOF

# Set proper permissions
RUN chown -R postgres:postgres /docker-entrypoint-initdb.d \
    && chmod 755 /docker-entrypoint-initdb.d/*.sql

# Health check configuration
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=60s \
    CMD /usr/local/bin/health-check.sh

# Switch to postgres user for security
USER postgres

# Expose PostgreSQL port
EXPOSE 5432

# Set the default command to run PostgreSQL
CMD ["postgres"]
