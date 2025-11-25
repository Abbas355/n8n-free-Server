# 🚀 Complete VPS Deployment Guide

## 📋 Prerequisites

- ✅ Fresh Ubuntu VPS (20.04/22.04/24.04)
- ✅ Root or sudo access
- ✅ Domain name (e.g., yourdomain.com)
- ✅ GitHub repository with your n8n project

---

## 🎯 Overview

We'll set up:
1. Server security and basics
2. Docker & Docker Compose
3. Clone your project from Git
4. Setup Traefik (reverse proxy)
5. Deploy first client instance
6. Configure DNS
7. Automatic SSL certificates
8. Monitoring and backups

**Total time:** 30-45 minutes

---

## 📝 Step-by-Step Deployment

### **Step 1: Initial Server Setup**

#### 1.1 Connect to Your VPS

```bash
# From your local machine
ssh root@YOUR_SERVER_IP
```

#### 1.2 Update System

```bash
# Update package list
apt update && apt upgrade -y

# Install essential tools
apt install -y curl wget git nano ufw htop
```

#### 1.3 Create Non-Root User (Security Best Practice)

```bash
# Create user
adduser n8nadmin

# Add to sudo group
usermod -aG sudo n8nadmin

# Switch to new user
su - n8nadmin
```

#### 1.4 Setup Firewall

```bash
# Allow SSH
sudo ufw allow OpenSSH

# Allow HTTP and HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Enable firewall
sudo ufw enable

# Check status
sudo ufw status
```

---

### **Step 2: Install Docker & Docker Compose**

#### 2.1 Install Docker

```bash
# Install Docker
curl -fsSL https://get.docker.com | sh

# Add user to docker group (no need for sudo)
sudo usermod -aG docker $USER

# Apply group changes
newgrp docker

# Test Docker
docker --version
docker ps
```

#### 2.2 Install Docker Compose (Latest)

```bash
# Docker Compose is included in Docker now, verify:
docker compose version

# Should show: Docker Compose version v2.x.x
```

---

### **Step 3: Clone Your Project from Git**

```bash
# Go to home directory
cd ~

# Clone your repository
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git n8n-hosting

# Go to project directory
cd n8n-hosting

# Check files
ls -la
```

---

### **Step 4: Setup Environment Variables**

#### 4.1 Create Main Environment File

```bash
# Create .env file
nano .env
```

**Add this content:**

```env
# Domain Configuration
DOMAIN=yourdomain.com
EMAIL=your-email@example.com

# Database Passwords (Change these!)
DB_PASSWORD_SALT=change_this_to_random_string_abc123

# Traefik Configuration
TRAEFIK_DASHBOARD_USER=admin
TRAEFIK_DASHBOARD_PASSWORD=change_this_secure_password
```

**Save:** Ctrl+O, Enter, Ctrl+X

#### 4.2 Generate Secure Passwords

```bash
# Generate random passwords
openssl rand -base64 32

# Use this for DB_PASSWORD_SALT and other secrets
```

---

### **Step 5: Create Directory Structure**

```bash
# Create directories for all components
mkdir -p ~/n8n-hosting/{clients,traefik-data,backups,scripts}

# Create Traefik config directory
mkdir -p ~/n8n-hosting/traefik-data/letsencrypt

# Set permissions
chmod 600 ~/n8n-hosting/traefik-data/letsencrypt
```

---

### **Step 6: Setup Traefik (Reverse Proxy)**

#### 6.1 Create Traefik Docker Compose File

```bash
cd ~/n8n-hosting
nano docker-compose.traefik.yml
```

**Add this content:**

```yaml
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
      
      # Let's Encrypt (automatic SSL)
      - "--certificatesresolvers.letsencrypt.acme.email=${EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      
      # Logging
      - "--log.level=INFO"
      - "--accesslog=true"
    
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
      # Dashboard (protect with auth)
      - "traefik.http.routers.traefik.rule=Host(`traefik.${DOMAIN}`)"
      - "traefik.http.routers.traefik.service=api@internal"
      - "traefik.http.routers.traefik.entrypoints=websecure"
      - "traefik.http.routers.traefik.tls.certresolver=letsencrypt"

networks:
  n8n-proxy:
    name: n8n-proxy
    driver: bridge
```

**Save:** Ctrl+O, Enter, Ctrl+X

#### 6.2 Start Traefik

```bash
# Create network
docker network create n8n-proxy

# Start Traefik
docker compose -f docker-compose.traefik.yml up -d

# Check logs
docker logs traefik -f

# Press Ctrl+C to exit logs

# Verify running
docker ps
```

---

### **Step 7: Setup DNS**

#### 7.1 Configure Wildcard DNS

Go to your domain registrar (Namecheap, GoDaddy, Cloudflare, etc.):

**Add these DNS records:**

```
Type    Name    Value           TTL
A       @       YOUR_SERVER_IP  300
A       *       YOUR_SERVER_IP  300
```

**This creates:**
- `yourdomain.com` → Your server
- `*.yourdomain.com` → Your server (all subdomains)

**Examples:**
- `client-a.yourdomain.com` ✅
- `client-b.yourdomain.com` ✅
- `anything.yourdomain.com` ✅

#### 7.2 Wait for DNS Propagation

```bash
# Check DNS (takes 5-60 minutes)
nslookup yourdomain.com
nslookup traefik.yourdomain.com

# Should show your server IP
```

---

### **Step 8: Deploy First Client Instance**

#### 8.1 Create Client Provisioning Script

```bash
cd ~/n8n-hosting
nano provision-client.sh
```

**Add this content:**

```bash
#!/bin/bash

# ============================================
# Client Provisioning Script
# Usage: ./provision-client.sh client-name
# ============================================

if [ -z "$1" ]; then
    echo "Usage: ./provision-client.sh <client-name>"
    echo "Example: ./provision-client.sh acme-corp"
    exit 1
fi

CLIENT_NAME=$1
CLIENT_ID=$(echo $CLIENT_NAME | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
CLIENT_DIR="$HOME/n8n-hosting/clients/$CLIENT_ID"

echo "=========================================="
echo "Provisioning client: $CLIENT_NAME"
echo "Client ID: $CLIENT_ID"
echo "=========================================="

# Generate secure passwords
DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
ENCRYPTION_KEY=$(openssl rand -hex 32)

echo "✓ Generated secure passwords"

# Create client directory
mkdir -p "$CLIENT_DIR"/{data,postgres,redis}
echo "✓ Created directories"

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
      
      # Database
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres-${CLIENT_ID}
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8nuser
      - DB_POSTGRESDB_PASSWORD=${DB_PASSWORD}
      
      # Security
      - N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}
      
      # Queue
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis-${CLIENT_ID}
      - QUEUE_BULL_REDIS_PORT=6379
      
      # Timezone
      - GENERIC_TIMEZONE=America/New_York
      - TZ=America/New_York
    
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

echo "✓ Created docker-compose.yml"

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

echo "✓ Saved credentials"

# Start instance
cd "$CLIENT_DIR"
docker compose up -d

echo ""
echo "=========================================="
echo "✅ Client provisioned successfully!"
echo "=========================================="
echo ""
echo "URL: https://${CLIENT_ID}.${DOMAIN}"
echo "Credentials saved in: $CLIENT_DIR/.env"
echo ""
echo "Wait 2-3 minutes for initialization..."
echo "Check logs: docker logs n8n-${CLIENT_ID} -f"
echo "=========================================="
EOF

# Make script executable
chmod +x provision-client.sh
```

**Save:** Ctrl+O, Enter, Ctrl+X

#### 8.2 Provision First Client

```bash
# Load environment variables
source .env

# Provision first client
./provision-client.sh demo

# This creates: https://demo.yourdomain.com
```

#### 8.3 Check Status

```bash
# View logs
docker logs n8n-demo -f

# Look for: "Editor is now accessible via:"
# Press Ctrl+C to exit

# Check all containers
docker ps

# Should see:
# - traefik
# - n8n-demo
# - postgres-demo
# - redis-demo
```

---

### **Step 9: Test Your Deployment**

#### 9.1 Access n8n

Open browser: `https://demo.yourdomain.com`

You should see:
- ✅ n8n setup screen
- ✅ Valid SSL certificate (lock icon)
- ✅ No security warnings

#### 9.2 Create Account

1. Fill in owner account details
2. Click "Next"
3. Complete setup wizard

#### 9.3 Test Workflow

1. Create a simple workflow
2. Add a Schedule node
3. Add a HTTP Request node
4. Test execution

---

### **Step 10: Deploy More Clients**

```bash
# Provision second client
./provision-client.sh client-a

# Access: https://client-a.yourdomain.com

# Provision third client
./provision-client.sh acme-corp

# Access: https://acme-corp.yourdomain.com

# Each client is completely isolated!
```

---

### **Step 11: Setup Automatic Backups**

#### 11.1 Create Backup Script

```bash
cd ~/n8n-hosting
nano backup-all.sh
```

**Add this content:**

```bash
#!/bin/bash

# ============================================
# Backup All Clients
# ============================================

BACKUP_DIR="$HOME/n8n-hosting/backups"
DATE=$(date +%Y%m%d-%H%M%S)

echo "Starting backup at $DATE..."

# Create backup directory
mkdir -p "$BACKUP_DIR/$DATE"

# Backup each client
for CLIENT_DIR in ~/n8n-hosting/clients/*/; do
    if [ -d "$CLIENT_DIR" ]; then
        CLIENT_ID=$(basename "$CLIENT_DIR")
        echo "Backing up $CLIENT_ID..."
        
        # Backup PostgreSQL
        docker exec postgres-${CLIENT_ID} pg_dump -U n8nuser n8n | gzip > "$BACKUP_DIR/$DATE/${CLIENT_ID}-postgres.sql.gz"
        
        # Backup n8n data
        tar -czf "$BACKUP_DIR/$DATE/${CLIENT_ID}-data.tar.gz" -C "$CLIENT_DIR" data
        
        echo "✓ $CLIENT_ID backed up"
    fi
done

# Delete backups older than 30 days
find "$BACKUP_DIR" -type d -mtime +30 -exec rm -rf {} +

echo "Backup completed!"
```

**Save and make executable:**

```bash
chmod +x backup-all.sh
```

#### 11.2 Setup Cron Job (Daily Backups)

```bash
# Edit crontab
crontab -e

# Add this line (backup at 2 AM daily):
0 2 * * * /home/n8nadmin/n8n-hosting/backup-all.sh >> /home/n8nadmin/n8n-hosting/backups/backup.log 2>&1
```

**Save:** Ctrl+O, Enter, Ctrl+X

---

### **Step 12: Monitoring Setup**

#### 12.1 Install Monitoring Tools

```bash
# Install system monitoring
sudo apt install -y netdata

# Start netdata
sudo systemctl start netdata
sudo systemctl enable netdata

# Access: http://YOUR_SERVER_IP:19999
```

#### 12.2 Docker Stats

```bash
# View resource usage
docker stats

# Check specific container
docker stats n8n-demo
```

---

### **Step 13: Security Hardening**

#### 13.1 Setup Fail2ban (Prevent Brute Force)

```bash
# Install fail2ban
sudo apt install -y fail2ban

# Start service
sudo systemctl start fail2ban
sudo systemctl enable fail2ban

# Check status
sudo fail2ban-client status
```

#### 13.2 Setup Automatic Updates

```bash
# Install unattended-upgrades
sudo apt install -y unattended-upgrades

# Enable automatic updates
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

---

## 📊 Quick Reference Commands

### **Managing Traefik**
```bash
# View logs
docker logs traefik -f

# Restart
docker restart traefik

# Stop
docker compose -f docker-compose.traefik.yml down

# Start
docker compose -f docker-compose.traefik.yml up -d
```

### **Managing Clients**
```bash
# View all clients
docker ps --filter "name=n8n-"

# View client logs
docker logs n8n-demo -f

# Restart client
docker restart n8n-demo

# Stop client
cd ~/n8n-hosting/clients/demo
docker compose down

# Start client
cd ~/n8n-hosting/clients/demo
docker compose up -d
```

### **Backup & Restore**
```bash
# Manual backup
./backup-all.sh

# List backups
ls -lh ~/n8n-hosting/backups/

# Restore client (example)
cd ~/n8n-hosting/clients/demo
docker compose down
tar -xzf ~/n8n-hosting/backups/20240101-120000/demo-data.tar.gz
docker compose up -d
```

### **System Monitoring**
```bash
# Disk usage
df -h

# Docker disk usage
docker system df

# Memory usage
free -h

# CPU usage
htop

# View all containers
docker ps -a

# View logs
docker logs <container-name> -f
```

---

## 🎯 Client Provisioning Workflow

### **1. Receive Client Signup**
```bash
# Client: "Acme Corp" signs up
# You run:
./provision-client.sh acme-corp

# URL created: https://acme-corp.yourdomain.com
```

### **2. Send Welcome Email**
```
Subject: Your n8n Workspace is Ready!

Hi Acme Corp,

Your dedicated n8n automation workspace is ready:
URL: https://acme-corp.yourdomain.com

Get started:
1. Click the link above
2. Create your admin account
3. Start building workflows!

Support: support@yourdomain.com
```

### **3. Client Can Immediately Access**
- ✅ Secure HTTPS
- ✅ Own subdomain
- ✅ Isolated data
- ✅ Full n8n features

---

## 🚨 Troubleshooting

### **Can't Access Website**
```bash
# Check DNS
nslookup demo.yourdomain.com

# Check Traefik
docker logs traefik

# Check client
docker logs n8n-demo

# Check firewall
sudo ufw status
```

### **SSL Certificate Issues**
```bash
# Check Let's Encrypt logs
docker logs traefik | grep letsencrypt

# Verify domain points to server
curl -I https://demo.yourdomain.com

# Restart Traefik
docker restart traefik
```

### **Container Won't Start**
```bash
# Check logs
docker logs n8n-demo

# Check disk space
df -h

# Check memory
free -h

# Restart Docker
sudo systemctl restart docker
```

---

## ✅ Post-Deployment Checklist

- [ ] Server secured (firewall, fail2ban)
- [ ] Docker installed and working
- [ ] Traefik running and accessible
- [ ] DNS configured (wildcard A record)
- [ ] First client deployed and accessible
- [ ] HTTPS working (valid certificate)
- [ ] Backups configured (cron job)
- [ ] Monitoring setup (netdata)
- [ ] Documentation saved
- [ ] Test workflow created and executed

---

## 🎉 Success!

You now have a **production-ready n8n hosting platform!**

**What you can do:**
✅ Deploy unlimited clients
✅ Each client has own subdomain
✅ Automatic SSL certificates
✅ Automatic backups
✅ System monitoring
✅ Secure and scalable

**Next steps:**
1. Build control panel for client management
2. Setup billing integration (Stripe)
3. Create client onboarding automation
4. Add monitoring alerts
5. Setup CDN (Cloudflare)

---

**Need help?** Check the logs or refer back to this guide!

🚀 **Happy Hosting!**

