# 🧪 Test Suite for n8n Multi-Client Setup

This test suite ensures that:
1. ✅ All existing clients are healthy
2. ✅ Creating new clients doesn't break existing ones
3. ✅ New clients are properly configured and isolated
4. ✅ No resource conflicts occur

## Test Scripts

### 1. `test-all-clients.sh`
**Purpose**: Comprehensive health check for all existing clients

**What it tests**:
- Traefik reverse proxy status
- Network configuration (n8n-proxy, internal networks)
- Container health (n8n, postgres, redis)
- Database connectivity
- Redis connectivity
- n8n health endpoints
- Configuration validation (N8N_PROXY_HOPS, etc.)
- Resource conflicts
- Disk space usage

**Usage**:
```bash
cd /var/www/n8n-free-Server
chmod +x test-all-clients.sh
./test-all-clients.sh
```

**Expected Output**:
```
🧪 COMPREHENSIVE CLIENT TEST SUITE
...
✅ ALL TESTS PASSED!
```

### 2. `test-new-client-creation.sh`
**Purpose**: Test creating a new client and verify it doesn't affect existing clients

**What it tests**:
1. Records all existing clients before test
2. Verifies existing clients are healthy BEFORE new client creation
3. Creates a new test client
4. Verifies new client is healthy
5. Verifies existing clients are STILL healthy AFTER
6. Checks for resource conflicts
7. Optionally cleans up test client

**Usage**:
```bash
cd /var/www/n8n-free-Server
chmod +x test-new-client-creation.sh
./test-new-client-creation.sh
```

**Expected Output**:
```
🧪 TEST: Creating New Client
...
✅ ALL TESTS PASSED!
New client provisioning works correctly and doesn't affect existing clients.
```

## Running the Complete Test Suite

### Step 1: Test All Existing Clients
```bash
cd /var/www/n8n-free-Server
chmod +x test-all-clients.sh
./test-all-clients.sh
```

**Expected Result**: All tests should pass before proceeding.

### Step 2: Test New Client Creation
```bash
chmod +x test-new-client-creation.sh
./test-new-client-creation.sh
```

**Expected Result**: 
- New test client is created successfully
- All existing clients remain healthy
- No resource conflicts

### Step 3: If Both Tests Pass, Create Production Client
```bash
./provision-client.sh "Production Client Name"
```

## Test Scenarios Covered

### ✅ Isolation Tests
- Each client has unique container names
- Each client has isolated internal network
- Each client has separate data directories
- Each client has unique encryption keys
- No cross-client data access

### ✅ Resource Conflict Tests
- No duplicate container names
- No network name conflicts
- No port conflicts (all use subdomain routing)
- Proper network connectivity

### ✅ Health Tests
- All containers running
- Database connections working
- Redis connections working
- n8n health endpoints responding
- Traefik routing configured

### ✅ Impact Tests
- Existing clients unaffected by new client creation
- No service interruptions
- No data corruption
- No configuration conflicts

## Before Creating Production Clients

Always run the test suite before provisioning a new production client:

```bash
# 1. Test all existing clients
./test-all-clients.sh

# 2. Test new client creation (creates a temporary test client)
./test-new-client-creation.sh

# 3. If both pass, proceed with production client
./provision-client.sh "Production Client Name"
```

## Troubleshooting Test Failures

### If `test-all-clients.sh` fails:

1. **Traefik not running**:
   ```bash
   docker compose -f docker-compose.traefik.yml up -d
   ```

2. **Network missing**:
   ```bash
   docker network create n8n-proxy
   ```

3. **Container not healthy**:
   ```bash
   # Check logs
   docker logs n8n-<client-id> -f
   
   # Restart client
   cd clients/<client-id>
   docker compose restart
   ```

4. **N8N_PROXY_HOPS missing**:
   ```bash
   # Add it to docker-compose.yml
   sed -i '/WEBHOOK_URL/a\      - N8N_PROXY_HOPS=1' clients/<client-id>/docker-compose.yml
   cd clients/<client-id>
   docker compose up -d
   ```

### If `test-new-client-creation.sh` fails:

1. **Existing client broke**:
   ```bash
   # Check what happened
   docker logs n8n-<affected-client-id> -f
   
   # Fix the affected client
   ./fix-client.sh <affected-client-id>
   ```

2. **Resource conflict**:
   ```bash
   # Check for duplicates
   docker ps --format "{{.Names}}" | sort | uniq -d
   
   # Remove duplicate/test containers
   docker rm -f <duplicate-container-name>
   ```

3. **Network issues**:
   ```bash
   # Verify n8n-proxy network
   docker network inspect n8n-proxy
   
   # Connect missing containers
   docker network connect n8n-proxy n8n-<client-id>
   ```

## Continuous Testing

For production environments, consider:

1. **Automated daily tests**:
   ```bash
   # Add to crontab
   0 2 * * * /var/www/n8n-free-Server/test-all-clients.sh >> /var/log/n8n-tests.log 2>&1
   ```

2. **Pre-provisioning checks**:
   - Always run `test-all-clients.sh` before creating new clients
   - Run `test-new-client-creation.sh` in staging first

3. **Monitoring**:
   - Set up alerts for test failures
   - Monitor container health
   - Track resource usage

## Success Criteria

✅ **All tests pass** before provisioning new clients
✅ **No existing clients affected** when creating new ones
✅ **New clients are properly isolated** and configured
✅ **No resource conflicts** detected
✅ **All health checks pass** for all clients

---

## Quick Reference

```bash
# Full test suite
./test-all-clients.sh && ./test-new-client-creation.sh

# Fix a broken client
./fix-client.sh <client-id>

# Provision new client (after tests pass)
./provision-client.sh "Client Name"

# Check all clients status
./diagnose-clients.sh
```

