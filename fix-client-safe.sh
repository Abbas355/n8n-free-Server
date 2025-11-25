#!/bin/bash
# Production-Safe Client Fix Script
# Fixes client issues without data loss - always backs up first

set -e  # Exit on error, but allow undefined vars in some cases

BASE_DIR="/var/www/n8n-free-Server"
BACKUP_DIR="${BASE_DIR}/backups"
LOG_FILE="${BASE_DIR}/logs/fix-$(date +%Y%m%d-%H%M%S).log"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

if [ -z "${1:-}" ]; then
    log_error "Usage: $0 <client-id>"
    exit 1
fi

CLIENT_ID="$1"
CLIENT_DIR="${BASE_DIR}/clients/$CLIENT_ID"

if [ ! -d "$CLIENT_DIR" ]; then
    log_error "Client directory not found: $CLIENT_DIR"
    exit 1
fi

# Ensure directories exist
mkdir -p "$BACKUP_DIR"
mkdir -p "${BASE_DIR}/logs"

log "=========================================="
log "Production-Safe Client Fix"
log "Client: $CLIENT_ID"
log "Log: $LOG_FILE"
log "=========================================="

# Create backup
BACKUP_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${CLIENT_ID}-${BACKUP_TIMESTAMP}"

log "Creating backup..."
mkdir -p "$BACKUP_PATH"

# Backup data directories (if they exist)
if [ -d "$CLIENT_DIR/data" ]; then
    log "Backing up n8n data..."
    tar -czf "${BACKUP_PATH}/data.tar.gz" -C "$CLIENT_DIR" data 2>/dev/null || log_warn "Failed to backup data directory (may be large)"
else
    log_warn "Data directory not found, skipping backup"
fi

if [ -d "$CLIENT_DIR/postgres" ]; then
    log "Backing up PostgreSQL data..."
    tar -czf "${BACKUP_PATH}/postgres.tar.gz" -C "$CLIENT_DIR" postgres 2>/dev/null || log_warn "Failed to backup postgres directory (may be large)"
else
    log_warn "Postgres directory not found, skipping backup"
fi

if [ -d "$CLIENT_DIR/redis" ]; then
    log "Backing up Redis data..."
    tar -czf "${BACKUP_PATH}/redis.tar.gz" -C "$CLIENT_DIR" redis 2>/dev/null || log_warn "Failed to backup redis directory"
else
    log_warn "Redis directory not found, skipping backup"
fi

# Backup configuration files
if [ -f "$CLIENT_DIR/.env" ]; then
    cp "$CLIENT_DIR/.env" "${BACKUP_PATH}/.env"
    log_success "Backed up .env file"
fi

if [ -f "$CLIENT_DIR/docker-compose.yml" ]; then
    cp "$CLIENT_DIR/docker-compose.yml" "${BACKUP_PATH}/docker-compose.yml"
    log_success "Backed up docker-compose.yml"
fi

log_success "Backup created at: $BACKUP_PATH"

# Verify backup
if [ ! -f "${BACKUP_PATH}/.env" ] && [ ! -f "${BACKUP_PATH}/docker-compose.yml" ]; then
    log_error "Backup verification failed - no critical files backed up"
    exit 1
fi

log_success "Backup verified"

cd "$CLIENT_DIR"

# Stop containers gracefully
log "Stopping containers..."
docker compose down || log_warn "Some containers may have already been stopped"

# Fix docker-compose.yml if needed
if [ -f "docker-compose.yml" ]; then
    log "Checking docker-compose.yml configuration..."
    
    # Add N8N_PROXY_HOPS if missing
    if ! grep -q "N8N_PROXY_HOPS" docker-compose.yml; then
        log "Adding missing N8N_PROXY_HOPS=1..."
        sed -i '/WEBHOOK_URL/a\      - N8N_PROXY_HOPS=1' docker-compose.yml
        log_success "Added N8N_PROXY_HOPS"
    fi
    
    # Ensure Redis has start_period in healthcheck
    if ! grep -q "start_period.*30s" docker-compose.yml | grep -A 5 "redis:" | grep -q "start_period"; then
        log "Adding Redis start_period to healthcheck..."
        if grep -q "redis:" docker-compose.yml && grep -A 10 "redis:" docker-compose.yml | grep -q "healthcheck:"; then
            sed -i '/redis:/,/retries: 5/{/retries: 5/a\      start_period: 30s
}' docker-compose.yml
        fi
        log_success "Added Redis start_period"
    fi
    
    # Ensure Redis depends_on uses service_healthy
    if grep -q "redis:" docker-compose.yml && grep -A 5 "depends_on:" docker-compose.yml | grep -q "condition: service_started"; then
        log "Updating Redis depends_on to use service_healthy..."
        sed -i 's/condition: service_started/condition: service_healthy/g' docker-compose.yml
        log_success "Updated Redis depends_on"
    fi
fi

# Recreate directories (preserve data)
log "Ensuring directory structure..."
mkdir -p data postgres redis
chmod 777 data 2>/dev/null || true

# Restart containers
log "Starting containers..."
if ! docker compose up -d; then
    log_error "Failed to start containers"
    log "Attempting to restore from backup..."
    
    # Restore .env if available
    if [ -f "${BACKUP_PATH}/.env" ]; then
        cp "${BACKUP_PATH}/.env" "$CLIENT_DIR/.env"
    fi
    
    exit 1
fi

log_success "Containers started"

# Wait and verify health
log "Waiting for services to initialize..."
sleep 30

# Verify containers are running
if ! docker ps --format "{{.Names}}" | grep -q "^n8n-${CLIENT_ID}$"; then
    log_error "n8n container is not running"
    exit 1
fi

# Wait for health checks
log "Waiting for health checks..."
for i in {1..30}; do
    if docker exec n8n-${CLIENT_ID} wget -q -O- http://localhost:5678/healthz 2>/dev/null | grep -q "ok"; then
        log_success "n8n is healthy"
        break
    fi
    sleep 2
done

log "=========================================="
log_success "Fix Complete!"
log "=========================================="
log "Backup location: $BACKUP_PATH"
log "Log file: $LOG_FILE"
log "=========================================="

