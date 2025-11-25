#!/bin/bash

# ============================================
# n8n Hosting VPS Quick Setup Script
# Run this on your fresh Ubuntu VPS
# ============================================

set -e  # Exit on error

echo "============================================"
echo "  n8n Hosting Platform - Quick Setup"
echo "============================================"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
    echo "⚠️  Please don't run as root"
    echo "   Run: sudo ./VPS-QUICK-START.sh"
    exit 1
fi

# Get user input
read -p "Enter your domain name (e.g., n8nhosting.com): " DOMAIN
read -p "Enter your email for SSL certificates: " EMAIL
read -p "Enter your GitHub repository URL: " GIT_REPO

echo ""
echo "============================================"
echo "Configuration:"
echo "  Domain: $DOMAIN"
echo "  Email: $EMAIL"
echo "  Git Repo: $GIT_REPO"
echo "============================================"
echo ""
read -p "Is this correct? (y/n): " CONFIRM

if [ "$CONFIRM" != "y" ]; then
    echo "Setup cancelled."
    exit 1
fi

echo ""
echo "[1/10] Updating system..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git nano ufw htop

echo ""
echo "[2/10] Setting up firewall..."
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
echo "y" | sudo ufw enable

echo ""
echo "[3/10] Installing Docker..."
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

echo ""
echo "[4/10] Cloning repository..."
cd ~
if [ -d "n8n-hosting" ]; then
    rm -rf n8n-hosting
fi
git clone $GIT_REPO n8n-hosting
cd n8n-hosting

echo ""
echo "[5/10] Creating directories..."
mkdir -p clients traefik-data/letsencrypt backups scripts
chmod 600 traefik-data/letsencrypt

echo ""
echo "[6/10] Generating secure passwords..."
DB_SALT=$(openssl rand -base64 32 | tr -d "=+/")
TRAEFIK_PASS=$(openssl rand -base64 16 | tr -d "=+/")

echo ""
echo "[7/10] Creating environment file..."
cat > .env <<EOF
# Domain Configuration
DOMAIN=$DOMAIN
EMAIL=$EMAIL

# Security
DB_PASSWORD_SALT=$DB_SALT
TRAEFIK_DASHBOARD_PASSWORD=$TRAEFIK_PASS

# Generated: $(date)
EOF

echo ""
echo "[8/10] Creating Traefik configuration..."
cat > docker-compose.traefik.yml <<'TRAEFIK_EOF'
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
      - "--certificatesresolvers.letsencrypt.acme.email=${EMAIL}"
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
    networks:
      - n8n-proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik.rule=Host(`traefik.${DOMAIN}`)"
      - "traefik.http.routers.traefik.service=api@internal"
      - "traefik.http.routers.traefik.entrypoints=websecure"
      - "traefik.http.routers.traefik.tls.certresolver=letsencrypt"

networks:
  n8n-proxy:
    name: n8n-proxy
    driver: bridge
TRAEFIK_EOF

echo ""
echo "[9/10] Starting Traefik..."
docker network create n8n-proxy 2>/dev/null || true
docker compose -f docker-compose.traefik.yml up -d

echo ""
echo "[10/10] Creating provisioning script..."
# (The provision-client.sh content would go here - already in DEPLOYMENT-GUIDE.md)
cp scripts/provision-client.sh . 2>/dev/null || echo "Note: Copy provision-client.sh manually"

echo ""
echo "============================================"
echo "  ✅ Setup Complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo ""
echo "1. Configure DNS:"
echo "   Add these records at your domain registrar:"
echo "   A    @    $(curl -s ifconfig.me)"
echo "   A    *    $(curl -s ifconfig.me)"
echo ""
echo "2. Wait 5-10 minutes for DNS propagation"
echo ""
echo "3. Provision your first client:"
echo "   ./provision-client.sh demo"
echo ""
echo "4. Access n8n:"
echo "   https://demo.$DOMAIN"
echo ""
echo "Traefik Dashboard: https://traefik.$DOMAIN"
echo "Dashboard Password: $TRAEFIK_PASS"
echo ""
echo "All credentials saved in: ~/n8n-hosting/.env"
echo "============================================"
echo ""
echo "⚠️  IMPORTANT: Log out and log back in for Docker group to take effect!"
echo "   Run: exit"
echo "   Then reconnect: ssh $USER@$(curl -s ifconfig.me)"
echo ""

