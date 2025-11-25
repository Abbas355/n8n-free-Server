#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: ./provision-client.sh <client-name>"
    exit 1
fi

CLIENT_NAME=$1
CLIENT_ID=$(echo $CLIENT_NAME | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')
CLIENT_DIR="/var/www/n8n-free-Server/clients/$CLIENT_ID"
DOMAIN="n8n.fabricsync.cloud"

echo "=========================================="
echo "Provisioning: $CLIENT_NAME"
echo "Client ID: $CLIENT_ID"
echo "URL: https://${CLIENT_ID}.${DOMAIN}"
echo "=========================================="

# Check if .env exists (keep existing credentials if re-provisioning)
if [ -f "$CLIENT_DIR/.env" ]; then
    echo "⚠️  Existing .env found, loading credentials..."
    source "$CLIENT_DIR/.env"
    if [ -z "$DB_PASSWORD" ] || [ -z "$ENCRYPTION_KEY" ]; then
        echo "⚠️  Invalid .env, generating new credentials..."
        DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        ENCRYPTION_KEY=$(openssl rand -hex 32)
    fi
else
    DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    ENCRYPTION_KEY=$(openssl rand -hex 32)
fi

mkdir -p "$CLIENT_DIR"/{data,postgres,redis}
chmod -R 777 "$CLIENT_DIR/data"

# Generate docker-compose.yml using heredoc to avoid escaping issues
cat > "$CLIENT_DIR/docker-compose.yml" <<EOF
version: '3.8'

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
        condition: service_started
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

networks:
  n8n-proxy:
    external: true
  ${CLIENT_ID}-internal:
    driver: bridge
EOF

# Save credentials
cat > "$CLIENT_DIR/.env" <<EOF
URL=https://${CLIENT_ID}.${DOMAIN}
DB_PASSWORD=${DB_PASSWORD}
ENCRYPTION_KEY=${ENCRYPTION_KEY}
EOF

cd "$CLIENT_DIR"

# Stop and remove old containers
echo "🛑 Stopping existing containers..."
docker compose down 2>/dev/null

# Start containers
echo "🚀 Starting containers..."
docker compose up -d

# Wait for services
echo "⏳ Waiting for services to initialize (60 seconds)..."
sleep 60

# Check status
echo ""
echo "📊 Container Status:"
docker compose ps

echo ""
echo "📝 n8n Logs (last 20 lines):"
docker logs n8n-${CLIENT_ID} --tail 20

echo ""
echo "=========================================="
echo "✅ Provisioning Complete!"
echo "=========================================="
echo "URL: https://${CLIENT_ID}.${DOMAIN}"
echo "Credentials saved to: $CLIENT_DIR/.env"
echo ""
echo "📋 Next steps:"
echo "1. Wait 2-3 minutes for full initialization"
echo "2. Check logs: docker logs n8n-${CLIENT_ID} -f"
echo "3. Test: curl -I https://${CLIENT_ID}.${DOMAIN}"
echo "=========================================="

