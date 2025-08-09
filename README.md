# PostgreSQL 17 Docker Image with Financial Extensions

A production-ready PostgreSQL 17 Docker image optimized for financial reconciliation, audit trails, and advanced search capabilities. This image includes carefully selected extensions and configurations tailored for financial workloads.

## Features

### Core Capabilities
- **PostgreSQL 17** - Latest stable version with performance improvements
- **Financial-optimized configuration** - Tuned for reconciliation and audit workloads
- **Multi-stage build** - Optimized image size with compiled extensions
- **Health checks** - Built-in health monitoring
- **Automatic maintenance** - Scheduled vacuum, analyze, and reindex jobs

### Included Extensions

#### Search & Text Processing
- **pg_trgm** - Trigram similarity search
- **unaccent** - Remove accents from text
- **fuzzystrmatch** - Fuzzy string matching
- **pgvector** - Vector similarity search for ML/AI features
- **jsquery** - Advanced JSON querying

#### Financial & Audit
- **pgaudit** - Comprehensive audit logging for compliance
- **temporal_tables** - System-versioned temporal tables for audit trails
- **pg_partman** - Automated partition management for large datasets
- **HyperLogLog** - Cardinality estimation for analytics
- **TopN** - Frequent pattern analysis

#### Time-Series Data
- **TimescaleDB** - Time-series data optimization
- **pg_cron** - Job scheduling within PostgreSQL

#### Monitoring & Performance
- **pg_stat_statements** - Query performance tracking
- **pg_stat_kcache** - Kernel cache statistics
- **pg_qualstats** - Query qualifier statistics
- **pg_wait_sampling** - Wait event sampling and analysis

#### Data Types
- **numeral** - Roman numeral support
- **unit** - SI unit conversions
- **rational** - Rational number arithmetic
- **prefix** - Prefix matching
- **ip4r** - IPv4/IPv6 range indexing
- **debversion** - Debian version number handling

## Quick Start

### Basic Usage

```bash
docker build -t postgres-financial:17 .

docker run -d \
  --name postgres-financial \
  -e POSTGRES_PASSWORD=mysecretpassword \
  -e POSTGRES_USER=financeuser \
  -e POSTGRES_DB=financial_db \
  -p 5432:5432 \
  -v postgres_data:/var/lib/postgresql/data \
  postgres-financial:17
```

### Docker Compose

```yaml
version: '3.8'

services:
  postgres:
    build: .
    container_name: postgres-financial
    environment:
      POSTGRES_USER: financeuser
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: financial_db
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./backups:/backups
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "/usr/local/bin/health-check.sh"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  postgres_data:
```

## Configuration

### Memory Settings

The default configuration assumes 4GB of RAM available. Adjust these settings based on your system:

```sql
-- For 8GB RAM system
shared_buffers = 2GB
effective_cache_size = 6GB
maintenance_work_mem = 512MB
work_mem = 32MB

-- For 16GB RAM system
shared_buffers = 4GB
effective_cache_size = 12GB
maintenance_work_mem = 1GB
work_mem = 64MB
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_USER` | postgres | Database superuser |
| `POSTGRES_PASSWORD` | - | Required password for superuser |
| `POSTGRES_DB` | postgres | Default database name |
| `PGDATA` | /var/lib/postgresql/data | Data directory location |

### Custom Configuration

Mount a custom configuration file:

```bash
docker run -d \
  --name postgres-financial \
  -v /path/to/custom/postgresql.conf:/etc/postgresql/postgresql.conf \
  -v postgres_data:/var/lib/postgresql/data \
  postgres-financial:17 \
  postgres -c 'config_file=/etc/postgresql/postgresql.conf'
```

## Database Structure

### Pre-configured Schemas

- **reconciliation** - Core financial reconciliation tables
- **audit** - Audit trail and change tracking
- **staging** - Temporary data import/export
- **archive** - Historical data storage
- **partman** - Partition management schema

### Sample Tables

The image creates example tables demonstrating best practices:

```sql
-- Accounts table with full-text search and audit
reconciliation.accounts
  - UUID primary keys
  - Currency enum type
  - Trigram indexes for fuzzy search
  - Row-level security enabled
  - Automatic audit triggers

-- Audit log with JSONB storage
audit.change_log
  - Tracks all changes
  - JSONB for flexible schema
  - Indexed by table and timestamp
```

## Scheduled Jobs

Pre-configured maintenance jobs via pg_cron:

| Schedule | Job | Description |
|----------|-----|-------------|
| Daily 2 AM | VACUUM ANALYZE | Clean up and update statistics |
| Weekly Sunday 3 AM | REINDEX CONCURRENTLY | Rebuild indexes without locking |
| Every 6 hours | ANALYZE | Update table statistics |

## Performance Tuning

### Financial Workload Optimizations

- **Checkpoint tuning** - 90% completion target for write smoothing
- **WAL compression** - Reduced storage for transaction logs
- **Parallel query** - Optimized for analytical queries
- **Statistics target** - Higher default (100) for better query plans

### Search Performance

- **GIN indexes** - Fast text search with pg_trgm
- **Unaccent search** - Case and accent insensitive matching
- **Vector similarity** - ML-powered semantic search

## Monitoring

### Query Performance

```sql
-- Top 10 slowest queries
SELECT query, mean_exec_time, calls
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;

-- Wait events analysis
SELECT * FROM pg_wait_sampling_profile
ORDER BY count DESC;
```

### Health Checks

The built-in health check verifies:
1. PostgreSQL is accepting connections
2. Basic query execution works
3. Extensions are properly loaded

## Security

### Audit Configuration

pgAudit is configured to log:
- All write operations (INSERT, UPDATE, DELETE)
- DDL changes (CREATE, ALTER, DROP)
- Role and permission changes
- Parameter values for compliance

### Best Practices

1. Always set a strong `POSTGRES_PASSWORD`
2. Use SSL/TLS for network connections
3. Enable row-level security for multi-tenant data
4. Regular backup and test restore procedures
5. Monitor audit logs for suspicious activity

## Backup and Recovery

### WAL Archiving

WAL archiving is enabled by default:

```bash
# Backup location
/var/lib/postgresql/data/wal_archive/

# Manual backup
docker exec postgres-financial pg_basebackup \
  -D /backups/$(date +%Y%m%d) \
  -Ft -z -P
```

### Point-in-Time Recovery

```bash
# Restore from backup
docker run -d \
  --name postgres-restore \
  -v /path/to/backup:/var/lib/postgresql/data \
  -e POSTGRES_PASSWORD=mysecretpassword \
  postgres-financial:17 \
  postgres -c 'recovery_target_time=2024-01-15 14:00:00'
```

## Troubleshooting

### Common Issues

**Out of Memory**
- Reduce `shared_buffers` and `work_mem`
- Check for memory leaks in queries

**Slow Queries**
- Run `ANALYZE` to update statistics
- Check `pg_stat_statements` for problem queries
- Verify indexes are being used

**Connection Refused**
- Check firewall rules
- Verify `listen_addresses = '*'`
- Ensure health checks are passing

### Logs

```bash
# View PostgreSQL logs
docker logs postgres-financial

# Access log files
docker exec postgres-financial ls -la /var/lib/postgresql/data/pg_log/
```

## Development

### Building Custom Extensions

Add custom extensions to the Dockerfile:

```dockerfile
# Build custom extension
RUN git clone https://github.com/your/extension.git \
    && cd extension \
    && make && make install
```

### Testing

```bash
# Run tests
docker exec postgres-financial psql -U postgres -c "SELECT version();"
docker exec postgres-financial psql -U postgres -c "SELECT * FROM pg_extension;"
```

## License

This Docker image configuration is provided as-is for use with PostgreSQL. PostgreSQL is released under the PostgreSQL License. Individual extensions may have their own licenses.

## Contributing

Contributions are welcome! Please submit issues and pull requests for:
- Additional extension recommendations
- Configuration improvements
- Documentation updates
- Bug fixes

## Support

For issues specific to this Docker image, please open an issue in the repository. For PostgreSQL-specific questions, refer to the [PostgreSQL documentation](https://www.postgresql.org/docs/17/).