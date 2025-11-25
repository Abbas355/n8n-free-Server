#!/bin/bash
# Production-Ready Client Provisioning Script
# Handles multi-tenant n8n client provisioning with comprehensive validation and rollback

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Track if containers were started
CONTAINERS_STARTED=false

# Configuration
BASE_DIR="/var/www/n8n-free-Server"
DOMAIN="n8n.fabricsync.cloud"
LOG_FILE="${BASE_DIR}/logs/provision-$(date +%Y%m%d-%H%M%S).log"
ROLLBACK_ENABLED=true

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Exit codes
EXIT_SUCCESS=0
EXIT_PREFLIGHT_FAILED=1
EXIT_PROVISION_FAILED=2
EXIT_VALIDATION_FAILED=3
EXIT_EXISTING_CLIENT_AFFECTED=4

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1${NC}" | tee -a "$LOG_FILE" >&2
}

log_warn() {
    echo -e "${YELLOW}$(date '+%Y-%m-%d %H:%M:%S') - WARN: $1${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}$(date '+%Y-%m-%d %H:%M:%S') - SUCCESS: $1${NC}" | tee -a "$LOG_FILE"
}

# Rollback function
rollback() {
    local reason="$1"
    log_error "ROLLBACK TRIGGERED: $reason"
    
    if [ "$ROLLBACK_ENABLED" = true ] && [ "$CONTAINERS_STARTED" = true ] && [ -n "${CLIENT_DIR:-}" ] && [ -d "$CLIENT_DIR" ]; then
        log "Stopping and removing containers for rollback..."
        cd "$CLIENT_DIR" 2>/dev/null || true
        docker compose down 2>/dev/null || true
        log "Rollback completed: Containers stopped and removed"
        
        # Note: We do NOT delete data directories to preserve user data
        log "Note: Data directories preserved at $CLIENT_DIR"
    fi
    
    return 1
}

# Trap to ensure cleanup on exit (only if containers were started)
trap 'if [ $? -ne 0 ] && [ "${CONTAINERS_STARTED:-false}" = true ]; then rollback "Script failed"; fi' EXIT

# Check if client name provided
if [ -z "${1:-}" ]; then
    log_error "Usage: $0 <client-name>"
    exit $EXIT_PREFLIGHT_FAILED
fi

CLIENT_NAME="$1"
CLIENT_ID=$(echo "$CLIENT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')
CLIENT_DIR="${BASE_DIR}/clients/$CLIENT_ID"

log "=========================================="
log "Provisioning: $CLIENT_NAME"
log "Client ID: $CLIENT_ID"
log "URL: https://${CLIENT_ID}.${DOMAIN}"
log "Log file: $LOG_FILE"
log "=========================================="

# Ensure log directory exists
mkdir -p "${BASE_DIR}/logs"

# ============================================
# PRE-FLIGHT CHECKS
# ============================================
log "Starting pre-flight checks..."

# 1. Verify n8n-proxy network exists
if ! docker network inspect n8n-proxy &>/dev/null; then
    log_error "n8n-proxy network not found! Creating it..."
    docker network create n8n-proxy || {
        log_error "Failed to create n8n-proxy network"
        exit $EXIT_PREFLIGHT_FAILED
    }
    log_success "n8n-proxy network created"
else
    log_success "n8n-proxy network verified"
fi

# 2. Check disk space (warn if < 10GB free)
DISK_FREE=$(df -BG "$BASE_DIR" | tail -1 | awk '{print $4}' | sed 's/G//')
if [ "$DISK_FREE" -lt 10 ]; then
    log_warn "Low disk space: ${DISK_FREE}GB free (recommended: 10GB+)"
else
    log_success "Disk space OK: ${DISK_FREE}GB free"
fi

# 3. Check memory availability
MEM_AVAILABLE=$(free -g | awk '/^Mem:/ {print $7}')
if [ "$MEM_AVAILABLE" -lt 1 ]; then
    log_warn "Low memory: ${MEM_AVAILABLE}GB available"
else
    log_success "Memory OK: ${MEM_AVAILABLE}GB available"
fi

# 4. Verify no container name conflicts
if docker ps -a --format "{{.Names}}" | grep -q "^n8n-${CLIENT_ID}$"; then
    log_warn "Container n8n-${CLIENT_ID} already exists (will be replaced)"
fi
if docker ps -a --format "{{.Names}}" | grep -q "^postgres-${CLIENT_ID}$"; then
    log_warn "Container postgres-${CLIENT_ID} already exists (will be replaced)"
fi
if docker ps -a --format "{{.Names}}" | grep -q "^redis-${CLIENT_ID}$"; then
    log_warn "Container redis-${CLIENT_ID} already exists (will be replaced)"
fi

# 5. Check existing clients health BEFORE provisioning
log "Checking existing clients health BEFORE provisioning..."
EXISTING_CLIENTS_HEALTHY=true
EXISTING_CLIENTS=()

for CLIENT_DIR_EXISTING in "${BASE_DIR}"/clients/*/; do
    if [ -d "$CLIENT_DIR_EXISTING" ] && [ "$CLIENT_DIR_EXISTING" != "$CLIENT_DIR/" ]; then
        EXISTING_CLIENT_ID=$(basename "$CLIENT_DIR_EXISTING")
        EXISTING_CLIENTS+=("$EXISTING_CLIENT_ID")
        
        if docker ps --format "{{.Names}}" | grep -q "^n8n-${EXISTING_CLIENT_ID}$"; then
            if docker exec n8n-${EXISTING_CLIENT_ID} wget -q -O- http://localhost:5678/healthz 2>/dev/null | grep -q "ok"; then
                log_success "Existing client $EXISTING_CLIENT_ID is healthy"
            else
                log_warn "Existing client $EXISTING_CLIENT_ID is not responding"
                EXISTING_CLIENTS_HEALTHY=false
            fi
        fi
    fi
done

if [ "$EXISTING_CLIENTS_HEALTHY" = false ]; then
    log_warn "Some existing clients are unhealthy, but proceeding..."
fi

# ============================================
# CREDENTIALS AND DIRECTORY SETUP
# ============================================
log "Setting up credentials and directories..."

# Check if .env exists (keep existing credentials if re-provisioning)
if [ -f "$CLIENT_DIR/.env" ]; then
    log_warn "Existing .env found, loading credentials..."
    source "$CLIENT_DIR/.env"
    if [ -z "${DB_PASSWORD:-}" ] || [ -z "${ENCRYPTION_KEY:-}" ]; then
        log_warn "Invalid .env, generating new credentials..."
        DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        ENCRYPTION_KEY=$(openssl rand -hex 32)
    else
        log_success "Loaded existing credentials from .env"
    fi
else
    DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    ENCRYPTION_KEY=$(openssl rand -hex 32)
    log_success "Generated new credentials"
fi

# Create directories with proper permissions
mkdir -p "$CLIENT_DIR"/{data,postgres,redis}
chmod -R 777 "$CLIENT_DIR/data"
log_success "Directories created"

# ============================================
# GENERATE DOCKER COMPOSE FILE
# ============================================
log "Generating docker-compose.yml..."

cat > "$CLIENT_DIR/docker-compose.yml" <<EOF
services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n-${CLIENT_ID}
    restart: unless-stopped
    environment:
      - N8N_HOST=${CLIENT_ID}.${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://${CLIENT_ID}.${DOMAIN}/
      - N8N_PROXY_HOPS=1
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8nuser
      - DB_POSTGRESDB_PASSWORD=${DB_PASSWORD}
      - N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
    volumes:
      - ./data:/home/node/.n8n
    networks:
      - n8n-proxy
      - ${CLIENT_ID}-internal
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  postgres:
    image: postgres:16-alpine
    container_name: postgres-${CLIENT_ID}
    restart: unless-stopped
    environment:
      - POSTGRES_USER=n8nuser
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_DB=n8n
    volumes:
      - ./postgres:/var/lib/postgresql/data
    networks:
      - ${CLIENT_ID}-internal
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U n8nuser"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  redis:
    image: redis:7-alpine
    container_name: redis-${CLIENT_ID}
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - ./redis:/data
    networks:
      - ${CLIENT_ID}-internal
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

networks:
  n8n-proxy:
    external: true
  ${CLIENT_ID}-internal:
    driver: bridge
EOF

log_success "docker-compose.yml generated"

# Save credentials
cat > "$CLIENT_DIR/.env" <<EOF
URL=https://${CLIENT_ID}.${DOMAIN}
DB_PASSWORD=${DB_PASSWORD}
ENCRYPTION_KEY=${ENCRYPTION_KEY}
EOF

# ============================================
# START CONTAINERS
# ============================================
cd "$CLIENT_DIR"

log "Stopping any existing containers..."
docker compose down 2>/dev/null || true

log "Starting containers..."
if ! docker compose up -d; then
    log_error "Failed to start containers"
    rollback "Container startup failed"
    exit $EXIT_PROVISION_FAILED
fi

CONTAINERS_STARTED=true
log_success "Containers started"

# ============================================
# NETWORK CONNECTIVITY VALIDATION
# ============================================
log "Validating network connectivity..."

# Wait a moment for networks to be created
sleep 5

# Verify n8n container is connected to n8n-proxy network
if ! docker network inspect n8n-proxy 2>/dev/null | grep -q "n8n-${CLIENT_ID}"; then
    log_error "n8n container not connected to n8n-proxy network"
    rollback "Network connectivity validation failed"
    exit $EXIT_VALIDATION_FAILED
fi
log_success "n8n container connected to n8n-proxy network"

# Verify internal network connectivity (n8n can reach postgres and redis)
if ! docker exec n8n-${CLIENT_ID} ping -c 2 postgres &>/dev/null; then
    log_error "n8n cannot reach postgres container"
    rollback "Internal network connectivity failed"
    exit $EXIT_VALIDATION_FAILED
fi
log_success "n8n can reach postgres"

if ! docker exec n8n-${CLIENT_ID} ping -c 2 redis &>/dev/null; then
    log_error "n8n cannot reach redis container"
    rollback "Internal network connectivity failed"
    exit $EXIT_VALIDATION_FAILED
fi
log_success "n8n can reach redis"

# ============================================
# COMPREHENSIVE HEALTH VALIDATION
# ============================================
log "Starting comprehensive health validation..."

# 1. Wait for PostgreSQL health
log "Waiting for PostgreSQL to be healthy..."
POSTGRES_HEALTHY=false
for i in {1..30}; do
    if docker exec postgres-${CLIENT_ID} pg_isready -U n8nuser &>/dev/null; then
        POSTGRES_HEALTHY=true
        break
    fi
    sleep 2
done

if [ "$POSTGRES_HEALTHY" = false ]; then
    log_error "PostgreSQL failed to become healthy within 60 seconds"
    rollback "PostgreSQL health check failed"
    exit $EXIT_VALIDATION_FAILED
fi
log_success "PostgreSQL is healthy"

# 2. Wait for Redis health
log "Waiting for Redis to be healthy..."
REDIS_HEALTHY=false
for i in {1..30}; do
    if docker exec redis-${CLIENT_ID} redis-cli ping 2>/dev/null | grep -q "PONG"; then
        REDIS_HEALTHY=true
        break
    fi
    sleep 2
done

if [ "$REDIS_HEALTHY" = false ]; then
    log_error "Redis failed to become healthy within 60 seconds"
    rollback "Redis health check failed"
    exit $EXIT_VALIDATION_FAILED
fi
log_success "Redis is healthy"

# 3. Wait for n8n health endpoint
log "Waiting for n8n health endpoint..."
N8N_HEALTHY=false
for i in {1..60}; do
    if docker exec n8n-${CLIENT_ID} wget -q -O- http://localhost:5678/healthz 2>/dev/null | grep -q "ok"; then
        N8N_HEALTHY=true
        break
    fi
    sleep 2
done

if [ "$N8N_HEALTHY" = false ]; then
    log_error "n8n health endpoint failed within 120 seconds"
    log "Checking n8n logs..."
    docker logs n8n-${CLIENT_ID} --tail 50 | tee -a "$LOG_FILE"
    rollback "n8n health check failed"
    exit $EXIT_VALIDATION_FAILED
fi
log_success "n8n health endpoint responding"

# ============================================
# TRAEFIK ROUTING VERIFICATION
# ============================================
log "Verifying Traefik routing..."

# Wait for Traefik to discover the container
log "Waiting for Traefik to discover container (up to 30 seconds)..."
TRAEFIK_DISCOVERED=false
for i in {1..15}; do
    if docker logs traefik 2>&1 | grep -q "n8n-${CLIENT_ID}" || docker ps --filter "name=traefik" --format "{{.Names}}" | grep -q traefik; then
        # Check if Traefik can route to the container
        sleep 5  # Give Traefik time to configure route
        
        # Test HTTP endpoint via Traefik (even if certificate not ready)
        if curl -k -s -o /dev/null -w "%{http_code}" "http://localhost:80" -H "Host: ${CLIENT_ID}.${DOMAIN}" | grep -qE "200|302|503"; then
            TRAEFIK_DISCOVERED=true
            break
        fi
    fi
    sleep 2
done

if [ "$TRAEFIK_DISCOVERED" = false ]; then
    log_warn "Traefik routing not immediately verified (may take longer for SSL certificate)"
    log "Container is healthy, but Traefik routing may need more time"
else
    log_success "Traefik routing verified"
fi

# ============================================
# VERIFY EXISTING CLIENTS STILL HEALTHY
# ============================================
log "Verifying existing clients are still healthy..."

AFFECTED_CLIENTS=()
for EXISTING_CLIENT_ID in "${EXISTING_CLIENTS[@]}"; do
    if docker ps --format "{{.Names}}" | grep -q "^n8n-${EXISTING_CLIENT_ID}$"; then
        if ! docker exec n8n-${EXISTING_CLIENT_ID} wget -q -O- http://localhost:5678/healthz 2>/dev/null | grep -q "ok"; then
            log_error "Existing client $EXISTING_CLIENT_ID became unhealthy after provisioning!"
            AFFECTED_CLIENTS+=("$EXISTING_CLIENT_ID")
        fi
    fi
done

if [ ${#AFFECTED_CLIENTS[@]} -gt 0 ]; then
    log_error "New client provisioning affected existing clients: ${AFFECTED_CLIENTS[*]}"
    rollback "Existing clients were affected"
    exit $EXIT_EXISTING_CLIENT_AFFECTED
fi
log_success "All existing clients remain healthy"

# ============================================
# FINAL STATUS REPORT
# ============================================
log "=========================================="
log "Provisioning Complete - Final Status"
log "=========================================="

log "Container Status:"
docker compose ps | tee -a "$LOG_FILE"

log ""
log "n8n Logs (last 20 lines):"
docker logs n8n-${CLIENT_ID} --tail 20 | tee -a "$LOG_FILE"

log ""
log_success "=========================================="
log_success "✅ PROVISIONING SUCCESSFUL!"
log_success "=========================================="
log_success "URL: https://${CLIENT_ID}.${DOMAIN}"
log_success "Credentials saved to: $CLIENT_DIR/.env"
log_success "Log file: $LOG_FILE"
log ""
log "Note: SSL certificate may take 2-3 minutes to be issued by Let's Encrypt"
log "=========================================="

# Disable rollback trap since we succeeded
CONTAINERS_STARTED=false
trap - EXIT
exit $EXIT_SUCCESS
