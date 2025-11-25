# Production Provisioning Guide

## Overview

This guide covers the production-ready multi-client n8n provisioning system with comprehensive validation, rollback mechanisms, and production-safe error handling.

## Key Features

### 1. Comprehensive Pre-Flight Checks
- Network verification (n8n-proxy network exists)
- Disk space validation (warns if < 10GB free)
- Memory availability check
- Container name conflict detection
- Existing client health verification

### 2. Health Validation
- PostgreSQL health check with retries
- Redis health check with proper startup period
- n8n health endpoint verification
- Network connectivity validation (n8n → postgres, n8n → redis)
- Traefik routing verification

### 3. Rollback Mechanism
- Automatic rollback on any validation failure
- Existing client data preserved (never deleted)
- Comprehensive logging of rollback reasons
- Clean container removal on failure

### 4. Existing Client Protection
- Health status recorded before provisioning
- Re-checked after provisioning completes
- Automatic rollback if existing clients become unhealthy
- Detailed reporting of affected clients

### 5. Production Safety
- All operations logged to timestamped files
- Credentials preserved in .env files
- Data directories never deleted
- Backup support in fix scripts

## Usage

### Provisioning a New Client

```bash
cd /var/www/n8n-free-Server
./provision-client.sh "Client Name"
```

The script will:
1. Run pre-flight checks
2. Create client directory structure
3. Generate credentials
4. Start containers
5. Validate network connectivity
6. Verify health checks
7. Check Traefik routing
8. Verify existing clients remain healthy

### Exit Codes

- `0` - Success
- `1` - Pre-flight check failed
- `2` - Container startup failed
- `3` - Health validation failed
- `4` - Existing client was affected

### Logging

All operations are logged to:
```
/var/www/n8n-free-Server/logs/provision-YYYYMMDD-HHMMSS.log
```

### Fixing a Broken Client (Production-Safe)

```bash
./fix-client-safe.sh <client-id>
```

This script:
- Creates backup before making changes
- Verifies backup before proceeding
- Only fixes configuration, never deletes data
- Preserves encryption keys and database data

## Testing

### Test All Clients

```bash
./test-all-clients.sh
```

Tests:
- Traefik status
- Network configuration
- Container health
- Database connectivity
- Redis health
- n8n health endpoints
- Network connectivity
- Traefik routing
- Resource usage

### Test New Client Creation

```bash
./test-new-client-creation.sh
```

This test:
- Records existing client health
- Creates a test client
- Verifies new client is healthy
- Verifies existing clients remain healthy
- Checks for resource conflicts
- Optionally cleans up test client

## Troubleshooting

### Redis Health Check Failing

**Issue**: Redis shows as unhealthy in tests

**Solution**: 
- Redis needs time to start (30 seconds start_period configured)
- Check Redis logs: `docker logs redis-<client-id>`
- Verify Redis health: `docker exec redis-<client-id> redis-cli ping`

### Bad Gateway Errors

**Issue**: Client shows "Bad Gateway" error

**Solution**:
1. Verify container is on n8n-proxy network:
   ```bash
   docker network inspect n8n-proxy | grep n8n-<client-id>
   ```

2. If missing, connect manually:
   ```bash
   docker network connect n8n-proxy n8n-<client-id>
   ```

3. Restart Traefik to re-discover:
   ```bash
   docker restart traefik
   ```

4. Verify N8N_PROXY_HOPS is configured in docker-compose.yml

### Existing Clients Affected

**Issue**: New client creation breaks existing clients

**Solution**:
- The provisioning script will automatically rollback if this happens
- Check logs for rollback reason
- Use `test-all-clients.sh` to identify affected clients
- Use `fix-client-safe.sh` to fix affected clients without data loss

### Container Won't Start

**Issue**: Containers fail to start

**Solution**:
1. Check logs: `docker logs <container-name>`
2. Verify docker-compose.yml syntax: `docker compose config`
3. Check resource availability (disk, memory)
4. Verify network exists: `docker network ls | grep n8n-proxy`

## Production Best Practices

1. **Always Test First**: Run `test-all-clients.sh` before provisioning
2. **Monitor Logs**: Check provision logs for any warnings
3. **Verify Health**: After provisioning, wait 2-3 minutes for full initialization
4. **Check Existing Clients**: Always verify existing clients remain healthy
5. **Backup Before Changes**: Use `fix-client-safe.sh` which creates backups automatically
6. **Monitor Resources**: Keep disk usage below 80%, memory usage below 85%

## Architecture

### Network Isolation

Each client has:
- **n8n-proxy network**: Shared network for Traefik routing
- **{client-id}-internal network**: Isolated network for postgres/redis communication

### Container Naming

- n8n: `n8n-{client-id}`
- PostgreSQL: `postgres-{client-id}`
- Redis: `redis-{client-id}`

### Data Isolation

Each client has separate:
- Data directory: `clients/{client-id}/data`
- PostgreSQL data: `clients/{client-id}/postgres`
- Redis data: `clients/{client-id}/redis`
- Configuration: `clients/{client-id}/.env`
- Docker Compose: `clients/{client-id}/docker-compose.yml`

## Monitoring

### Health Checks

All services have health checks:
- **PostgreSQL**: `pg_isready` with 30s start period
- **Redis**: `redis-cli ping` with 30s start period
- **n8n**: `/healthz` endpoint with 60s start period

### Logs

Monitor logs in real-time:
```bash
# Provisioning logs
tail -f /var/www/n8n-free-Server/logs/provision-*.log

# Container logs
docker logs n8n-<client-id> -f
docker logs traefik -f
```

## Security

### Credentials

- Credentials stored in `clients/{client-id}/.env`
- Each client has unique:
  - Database password
  - Encryption key
  - Isolated database

### Network Security

- Internal networks isolated per client
- Only n8n containers connected to n8n-proxy
- PostgreSQL and Redis not exposed externally

## Scaling

### Resource Limits

Current system supports:
- **Starter Plan** ($6/mo, 1 vCPU, 1GB RAM): 3 light users
- **Pro Plan** (Recommended): 4 vCPU, 8GB RAM for 10-15 clients
- **Premium Plan**: 8 vCPU, 16GB RAM for 30+ clients

### Adding More Clients

The provisioning system is designed to scale:
1. Run pre-flight checks to ensure resources available
2. Each client is completely isolated
3. No shared resources between clients
4. Automatic validation prevents conflicts

## Support

For issues:
1. Check logs: `/var/www/n8n-free-Server/logs/`
2. Run diagnostics: `./test-all-clients.sh`
3. Check container status: `docker ps`
4. Review Traefik logs: `docker logs traefik`

