#!/bin/bash

# ============================================
# Working Client Provisioning Script
# Fixed all network and hostname issues
# ============================================

if [ -z "$1" ]; then
    echo "Usage: ./provision-client.sh <client-name>"
    echo "Example: ./provision-client.sh demo"
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

# Generate secure credentials
DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
ENCRYPTION_KEY=$(openssl rand -hex 32)

# Create directories with proper permissions
mkdir -p "$CLIENT_DIR"/{data,postgres,redis}
chmod -R 777 "$CLIENT_DIR/data"

echo "✓ Directories created"

# Create docker-compose file with CORRECT hostnames
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
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres-${CLIENT_ID}
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8nuser
      - DB_POSTGRESDB_PASSWORD=${DB_PASSWORD}
      - N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis-${CLIENT_ID}
      - QUEUE_BULL_REDIS_PORT=6379
    volumes:
      - ./data:/home/node/.n8n
    networks:
      - n8n-proxy
      - ${CLIENT_ID}-internal
    depends_on:
      postgres-${CLIENT_ID}:
        condition: service_healthy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n-${CLIENT_ID}.rule=Host(\`${CLIENT_ID}.${DOMAIN}\`)"
      - "traefik.http.routers.n8n-${CLIENT_ID}.entrypoints=websecure"
      - "traefik.http.routers.n8n-${CLIENT_ID}.tls.certresolver=letsencrypt"
      - "traefik.http.services.n8n-${CLIENT_ID}.loadbalancer.server.port=5678"
      - "traefik.docker.network=n8n-proxy"

  postgres-${CLIENT_ID}:
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

  redis-${CLIENT_ID}:
    image: redis:7-alpine
    container_name: redis-${CLIENT_ID}
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - ./redis:/data
    networks:
      - ${CLIENT_ID}-internal

networks:
  n8n-proxy:
    external: true
  ${CLIENT_ID}-internal:
    driver: bridge
EOF

echo "✓ Docker Compose file created"

# Save credentials
cat > "$CLIENT_DIR/.env" <<EOF
CLIENT_NAME=$CLIENT_NAME
CLIENT_ID=$CLIENT_ID
DOMAIN=$DOMAIN
URL=https://${CLIENT_ID}.${DOMAIN}
DB_PASSWORD=${DB_PASSWORD}
ENCRYPTION_KEY=${ENCRYPTION_KEY}
CREATED_AT=$(date)
EOF

chmod 600 "$CLIENT_DIR/.env"

echo "✓ Credentials saved"

# Start instance
echo ""
echo "Starting containers..."
cd "$CLIENT_DIR"
docker compose up -d

echo ""
echo "Waiting for n8n to initialize (60 seconds)..."
sleep 60

# Check if n8n is running
if docker ps | grep -q "n8n-${CLIENT_ID}"; then
    echo "✓ Container is running"
    
    # Check if n8n is healthy
    if docker logs "n8n-${CLIENT_ID}" 2>&1 | grep -q "Editor is now accessible"; then
        echo "✓ n8n is ready!"
    else
        echo "⚠ n8n may still be initializing. Check logs:"
        echo "  docker logs n8n-${CLIENT_ID} -f"
    fi
else
    echo "❌ Container failed to start. Check logs:"
    echo "  docker logs n8n-${CLIENT_ID}"
fi

echo ""
echo "=========================================="
echo "✅ Provisioning complete!"
echo "=========================================="
echo ""
echo "URL: https://${CLIENT_ID}.${DOMAIN}"
echo "Credentials: $CLIENT_DIR/.env"
echo ""
echo "Access in browser:"
echo "  https://${CLIENT_ID}.${DOMAIN}"
echo ""
echo "View logs:"
echo "  docker logs n8n-${CLIENT_ID} -f"
echo ""
echo "Check status:"
echo "  docker ps | grep ${CLIENT_ID}"
echo "=========================================="





