#!/bin/bash

# ============================================
# n8n Hosting Deployment Script
# For Ubuntu VPS - Production Ready
# ============================================

set -e

echo "============================================"
echo "  n8n Hosting Platform - VPS Deployment"
echo "============================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root: sudo bash deploy-to-vps.sh"
    exit 1
fi

# Configuration
echo "Please provide the following information:"
echo ""
read -p "Your domain name (e.g., n8nhosting.com): " DOMAIN
read -p "Your email for SSL certificates: " EMAIL

echo ""
echo "============================================"
echo "Configuration:"
echo "  Server IP: $(hostname -I | awk '{print $1}')"
echo "  Domain: $DOMAIN"
echo "  Email: $EMAIL"
echo "============================================"
echo ""
read -p "Is this correct? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Setup cancelled."
    exit 1
fi

echo ""
echo "Starting deployment..."
echo ""

# Step 1: Update system
echo "[1/12] Updating system packages..."
apt update && apt upgrade -y
apt install -y curl wget git nano ufw htop net-tools

# Step 2: Setup firewall
echo ""
echo "[2/12] Configuring firewall..."
ufw --force enable
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw status

# Step 3: Install Docker
echo ""
echo "[3/12] Installing Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
else
    echo "Docker already installed"
fi

# Step 4: Install Docker Compose (if needed)
echo ""
echo "[4/12] Checking Docker Compose..."
docker compose version

# Step 5: Create project directory structure
echo ""
echo "[5/12] Setting up directory structure..."
cd /var/www/n8n-free-Server
mkdir -p clients traefik-data/letsencrypt backups scripts logs

# Set permissions for Let's Encrypt
chmod 600 traefik-data/letsencrypt

# Step 6: Generate secure credentials
echo ""
echo "[6/12] Generating secure credentials..."
DB_SALT=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
TRAEFIK_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/")
TRAEFIK_USER="admin"

# Create hashed password for Traefik
TRAEFIK_HASHED=$(openssl passwd -apr1 "$TRAEFIK_PASSWORD")

# Step 7: Create environment file
echo ""
echo "[7/12] Creating environment configuration..."
cat > .env <<EOF
# Domain Configuration
DOMAIN=$DOMAIN
EMAIL=$EMAIL

# Server Information
SERVER_IP=$(hostname -I | awk '{print $1}')

# Security
DB_PASSWORD_SALT=$DB_SALT

# Traefik Dashboard
TRAEFIK_USER=$TRAEFIK_USER
TRAEFIK_PASSWORD=$TRAEFIK_PASSWORD
TRAEFIK_HASHED=$TRAEFIK_HASHED

# Created: $(date)
EOF

chmod 600 .env

# Step 8: Create Traefik configuration
echo ""
echo "[8/12] Creating Traefik reverse proxy configuration..."
cat > docker-compose.traefik.yml <<'EOF'
services:
  traefik:
    image: traefik:v3.0
    container_name: traefik
    restart: unless-stopped
    command:
      # API and dashboard
      - "--api.dashboard=true"
      
      # Docker provider
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.docker.network=n8n-proxy"
      
      # Entry points
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      
      # HTTP to HTTPS redirect
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
      - "--entrypoints.web.http.redirections.entrypoint.permanent=true"
      
      # Let's Encrypt (automatic SSL)
      - "--certificatesresolvers.letsencrypt.acme.email=${EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      
      # Logging
      - "--log.level=INFO"
      - "--accesslog=true"
      - "--accesslog.filepath=/var/log/traefik/access.log"
    
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
      
      # Dashboard
      - "traefik.http.routers.traefik.rule=Host(`traefik.${DOMAIN}`)"
      - "traefik.http.routers.traefik.service=api@internal"
      - "traefik.http.routers.traefik.entrypoints=websecure"
      - "traefik.http.routers.traefik.tls.certresolver=letsencrypt"
      
      # Dashboard authentication
      - "traefik.http.routers.traefik.middlewares=traefik-auth"
      - "traefik.http.middlewares.traefik-auth.basicauth.users=${TRAEFIK_USER}:${TRAEFIK_HASHED}"

networks:
  n8n-proxy:
    name: n8n-proxy
    driver: bridge
EOF

# Step 9: Create provisioning script
echo ""
echo "[9/12] Creating client provisioning script..."
cat > provision-client.sh <<'PROVISION_SCRIPT'
#!/bin/bash

# Load environment
source /var/www/n8n-free-Server/.env

if [ -z "$1" ]; then
    echo "Usage: ./provision-client.sh <client-name>"
    echo "Example: ./provision-client.sh acme-corp"
    exit 1
fi

CLIENT_NAME=$1
CLIENT_ID=$(echo $CLIENT_NAME | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')
CLIENT_DIR="/var/www/n8n-free-Server/clients/$CLIENT_ID"

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

# Create docker-compose file
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
EOF

# Save credentials
cat > "$CLIENT_DIR/.env" <<EOF
CLIENT_NAME=$CLIENT_NAME
CLIENT_ID=$CLIENT_ID
DOMAIN=$DOMAIN
DB_PASSWORD=$DB_PASSWORD
ENCRYPTION_KEY=$ENCRYPTION_KEY
URL=https://${CLIENT_ID}.${DOMAIN}
CREATED_AT=$(date)
EOF

chmod 600 "$CLIENT_DIR/.env"

# Start instance
cd "$CLIENT_DIR"
docker compose up -d

echo ""
echo "✅ Client provisioned successfully!"
echo ""
echo "URL: https://${CLIENT_ID}.${DOMAIN}"
echo "Credentials: $CLIENT_DIR/.env"
echo ""
echo "Wait 2-3 minutes for initialization..."
echo "Check logs: docker logs n8n-${CLIENT_ID} -f"
PROVISION_SCRIPT

chmod +x provision-client.sh

# Step 10: Create backup script
echo ""
echo "[10/12] Creating backup script..."
cat > backup-all.sh <<'BACKUP_SCRIPT'
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

echo "Backup completed: $BACKUP_DIR/$DATE"
BACKUP_SCRIPT

chmod +x backup-all.sh

# Step 11: Start Traefik
echo ""
echo "[11/12] Starting Traefik reverse proxy..."
docker network create n8n-proxy 2>/dev/null || echo "Network already exists"
docker compose -f docker-compose.traefik.yml up -d

sleep 5

# Step 12: Display summary
echo ""
echo "[12/12] Installation complete!"
echo ""
echo "============================================"
echo "  ✅ n8n Hosting Platform Deployed!"
echo "============================================"
echo ""
echo "📋 Server Information:"
echo "  IP Address: $(hostname -I | awk '{print $1}')"
echo "  Domain: $DOMAIN"
echo ""
echo "🔧 Next Steps:"
echo ""
echo "1. Configure DNS at your domain registrar:"
echo "   Type  Name  Value"
echo "   A     @     $(hostname -I | awk '{print $1}')"
echo "   A     *     $(hostname -I | awk '{print $1}')"
echo ""
echo "2. Wait 5-10 minutes for DNS propagation"
echo ""
echo "3. Deploy your first client:"
echo "   cd /var/www/n8n-free-Server"
echo "   ./provision-client.sh demo"
echo ""
echo "4. Access n8n:"
echo "   https://demo.$DOMAIN"
echo ""
echo "📊 Management:"
echo "  Traefik Dashboard: https://traefik.$DOMAIN"
echo "  Username: $TRAEFIK_USER"
echo "  Password: $TRAEFIK_PASSWORD"
echo ""
echo "📝 Important Files:"
echo "  Configuration: /var/www/n8n-free-Server/.env"
echo "  Provision client: ./provision-client.sh <name>"
echo "  Backup all: ./backup-all.sh"
echo ""
echo "🔍 Useful Commands:"
echo "  View all containers: docker ps"
echo "  View logs: docker logs <container-name> -f"
echo "  Restart Traefik: docker restart traefik"
echo ""
echo "============================================"
echo ""
echo "💡 SAVE THIS PASSWORD: $TRAEFIK_PASSWORD"
echo ""

