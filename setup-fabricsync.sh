#!/bin/bash

# ============================================
# Setup n8n Hosting for fabricsync.cloud
# ============================================

cd /var/www/n8n-free-Server

echo "Setting up n8n hosting for fabricsync.cloud..."

# 1. Create environment file
cat > .env <<'EOF'
# Domain Configuration
DOMAIN=fabricsync.cloud
EMAIL=muhammadabbas910918@gmail.com

# Server Information
SERVER_IP=64.23.145.110

# Traefik Dashboard
TRAEFIK_USER=admin
TRAEFIK_PASSWORD=Admin@123

# Created at: $(date)
EOF

echo "✓ Environment file created"

# 2. Create Traefik configuration
cat > docker-compose.traefik.yml <<'EOF'
services:
  traefik:
    image: traefik:v3.0
    container_name: traefik
    restart: unless-stopped
    command:
      - "--api.dashboard=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.docker.network=n8n-proxy"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
      - "--certificatesresolvers.letsencrypt.acme.email=muhammadabbas910918@gmail.com"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--log.level=INFO"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik-data/letsencrypt:/letsencrypt
      - ./logs:/var/log/traefik
    networks:
      - n8n-proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik.rule=Host(`traefik.fabricsync.cloud`)"
      - "traefik.http.routers.traefik.service=api@internal"
      - "traefik.http.routers.traefik.entrypoints=websecure"
      - "traefik.http.routers.traefik.tls.certresolver=letsencrypt"

networks:
  n8n-proxy:
    name: n8n-proxy
    driver: bridge
EOF

echo "✓ Traefik configuration created"

# 3. Create provisioning script
cat > provision-client.sh <<'PROVISION_EOF'
#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: ./provision-client.sh <client-name>"
    echo "Example: ./provision-client.sh demo"
    exit 1
fi

CLIENT_NAME=$1
CLIENT_ID=$(echo $CLIENT_NAME | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')
CLIENT_DIR="/var/www/n8n-free-Server/clients/$CLIENT_ID"
DOMAIN="fabricsync.cloud"

echo "=========================================="
echo "Provisioning: $CLIENT_NAME"
echo "Client ID: $CLIENT_ID"
echo "URL: https://${CLIENT_ID}.${DOMAIN}"
echo "=========================================="

# Generate secure credentials
DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
ENCRYPTION_KEY=$(openssl rand -hex 32)

# Create directories
mkdir -p "$CLIENT_DIR"/{data,postgres,redis}
chmod 700 "$CLIENT_DIR"

echo "✓ Directories created"

# Create docker-compose file
cat > "$CLIENT_DIR/docker-compose.yml" <<DOCKER_EOF
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
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8nuser
      - DB_POSTGRESDB_PASSWORD=${DB_PASSWORD}
      - N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - GENERIC_TIMEZONE=UTC
      - TZ=UTC
    volumes:
      - ./data:/home/node/.n8n
    networks:
      - n8n-proxy
      - ${CLIENT_ID}-internal
    depends_on:
      postgres:
        condition: service_healthy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n-${CLIENT_ID}.rule=Host(\\\`${CLIENT_ID}.${DOMAIN}\\\`)"
      - "traefik.http.routers.n8n-${CLIENT_ID}.entrypoints=websecure"
      - "traefik.http.routers.n8n-${CLIENT_ID}.tls.certresolver=letsencrypt"
      - "traefik.http.services.n8n-${CLIENT_ID}.loadbalancer.server.port=5678"
      - "traefik.docker.network=n8n-proxy"

  postgres:
    image: postgres:16-alpine
    container_name: postgres-${CLIENT_ID}
    restart: unless-stopped
    environment:
      - POSTGRES_USER=n8nuser
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_DB=n8n
      - PGDATA=/var/lib/postgresql/data/pgdata
    volumes:
      - ./postgres:/var/lib/postgresql/data
    networks:
      - ${CLIENT_ID}-internal
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U n8nuser"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
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
DOCKER_EOF

echo "✓ Docker Compose file created"

# Save credentials
cat > "$CLIENT_DIR/.env" <<CREDS_EOF
CLIENT_NAME=$CLIENT_NAME
CLIENT_ID=$CLIENT_ID
DOMAIN=$DOMAIN
URL=https://${CLIENT_ID}.${DOMAIN}
DB_PASSWORD=${DB_PASSWORD}
ENCRYPTION_KEY=${ENCRYPTION_KEY}
CREATED_AT=$(date)
CREDS_EOF

chmod 600 "$CLIENT_DIR/.env"

echo "✓ Credentials saved"

# Start instance
echo ""
echo "Starting containers..."
cd "$CLIENT_DIR"
docker compose up -d

echo ""
echo "=========================================="
echo "✅ Client provisioned successfully!"
echo "=========================================="
echo ""
echo "URL: https://${CLIENT_ID}.${DOMAIN}"
echo "Credentials: $CLIENT_DIR/.env"
echo ""
echo "Wait 2-3 minutes for initialization..."
echo ""
echo "Check logs:"
echo "  docker logs n8n-${CLIENT_ID} -f"
echo ""
echo "Check status:"
echo "  docker ps | grep ${CLIENT_ID}"
echo "=========================================="
PROVISION_EOF

chmod +x provision-client.sh

echo "✓ Provisioning script created"

# 4. Create backup script
cat > backup-all.sh <<'BACKUP_EOF'
#!/bin/bash

BACKUP_DIR="/var/www/n8n-free-Server/backups"
DATE=$(date +%Y%m%d-%H%M%S)

echo "Starting backup at $DATE..."
mkdir -p "$BACKUP_DIR/$DATE"

for CLIENT_DIR in /var/www/n8n-free-Server/clients/*/; do
    if [ -d "$CLIENT_DIR" ]; then
        CLIENT_ID=$(basename "$CLIENT_DIR")
        echo "Backing up $CLIENT_ID..."
        
        # Backup PostgreSQL
        docker exec postgres-${CLIENT_ID} pg_dump -U n8nuser n8n 2>/dev/null | gzip > "$BACKUP_DIR/$DATE/${CLIENT_ID}-postgres.sql.gz" || echo "Failed to backup $CLIENT_ID database"
        
        # Backup n8n data
        tar -czf "$BACKUP_DIR/$DATE/${CLIENT_ID}-data.tar.gz" -C "$CLIENT_DIR" data 2>/dev/null || echo "Failed to backup $CLIENT_ID data"
        
        echo "✓ $CLIENT_ID backed up"
    fi
done

# Delete backups older than 30 days
find "$BACKUP_DIR" -type d -mtime +30 -exec rm -rf {} + 2>/dev/null || true

echo ""
echo "✅ Backup completed: $BACKUP_DIR/$DATE"
BACKUP_EOF

chmod +x backup-all.sh

echo "✓ Backup script created"

# 5. Create Docker network
echo ""
echo "Creating Docker network..."
docker network create n8n-proxy 2>/dev/null || echo "Network already exists"

# 6. Start Traefik
echo ""
echo "Starting Traefik reverse proxy..."
docker compose -f docker-compose.traefik.yml up -d

# Wait for Traefik to start
sleep 5

# Check if Traefik is running
if docker ps | grep -q traefik; then
    echo "✓ Traefik is running"
else
    echo "⚠ Traefik may not have started. Check logs: docker logs traefik"
fi

echo ""
echo "============================================"
echo "  ✅ Setup Complete!"
echo "============================================"
echo ""
echo "📋 Configuration:"
echo "  Domain: fabricsync.cloud"
echo "  Server IP: 64.23.145.110"
echo "  Email: muhammadabbas910918@gmail.com"
echo ""
echo "🔧 IMPORTANT: Configure DNS"
echo "============================================"
echo "Go to your DNS provider (Cloudflare/etc) and add:"
echo ""
echo "For wildcard subdomains:"
echo "  Type: A"
echo "  Name: *.n8n"
echo "  Value: 64.23.145.110"
echo "  TTL: 300"
echo ""
echo "Or add individual subdomains:"
echo "  Type: A"
echo "  Name: demo.n8n"
echo "  Value: 64.23.145.110"
echo ""
echo "  Type: A"
echo "  Name: traefik.n8n"
echo "  Value: 64.23.145.110"
echo ""
echo "============================================"
echo ""
echo "📊 Next Steps:"
echo ""
echo "1. Configure DNS (see above)"
echo "2. Wait 5-10 minutes for DNS propagation"
echo "3. Deploy first client:"
echo "   ./provision-client.sh demo"
echo ""
echo "4. Access n8n:"
echo "   https://demo.n8n.fabricsync.cloud"
echo ""
echo "5. Traefik Dashboard:"
echo "   https://traefik.n8n.fabricsync.cloud"
echo "   Username: admin"
echo "   Password: Admin@123"
echo ""
echo "============================================"
echo ""
echo "🔍 Useful Commands:"
echo "  View containers: docker ps"
echo "  View logs: docker logs <container-name> -f"
echo "  Provision client: ./provision-client.sh <name>"
echo "  Backup all: ./backup-all.sh"
echo "  Restart Traefik: docker restart traefik"
echo ""
echo "============================================"

