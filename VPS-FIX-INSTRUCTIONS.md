# 🚀 VPS Fix Instructions

## Quick Fix for Broken Clients

Since SSH password prompts don't work in automated terminals, follow these steps manually:

### **Step 1: Connect to VPS**
Open your terminal/command prompt and SSH into the server:
```bash
ssh root@64.23.145.110
```

### **Step 2: Navigate to Project Directory**
```bash
cd /var/www/n8n-free-Server
```

### **Step 3: Upload the Fix Scripts**

You have two options:

#### **Option A: Copy Scripts Directly (Recommended)**

Create the fix script on the server:

```bash
cat > VPS-FIX-ALL.sh << 'SCRIPT_EOF'
#!/bin/bash
# VPS-FIX-ALL.sh - Comprehensive fix for all clients

BASE_DIR="/var/www/n8n-free-Server"
cd "$BASE_DIR" || exit 1

echo "=========================================="
echo "🔧 COMPREHENSIVE FIX FOR ALL CLIENTS"
echo "=========================================="

# Step 1: Check Traefik
echo ""
echo "1️⃣ Checking Traefik..."
if ! docker ps | grep -q traefik; then
    echo "❌ Traefik is not running! Starting Traefik..."
    docker compose -f docker-compose.traefik.yml up -d
    sleep 5
else
    echo "✅ Traefik is running"
fi

# Step 2: Ensure n8n-proxy network exists
echo ""
echo "2️⃣ Checking n8n-proxy network..."
if ! docker network inspect n8n-proxy &>/dev/null; then
    echo "⚠️  Creating n8n-proxy network..."
    docker network create n8n-proxy
else
    echo "✅ n8n-proxy network exists"
fi

# Step 3: Fix each client
echo ""
echo "3️⃣ Fixing each client..."
for CLIENT_DIR in clients/*/; do
    if [ -d "$CLIENT_DIR" ]; then
        CLIENT_ID=$(basename "$CLIENT_DIR")
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Fixing: $CLIENT_ID"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        cd "$CLIENT_DIR" || continue
        
        # Stop containers
        echo "   Stopping containers..."
        docker compose down 2>/dev/null
        
        # Check if docker-compose.yml exists
        if [ ! -f "docker-compose.yml" ]; then
            echo "   ⚠️  No docker-compose.yml found, skipping..."
            cd "$BASE_DIR"
            continue
        fi
        
        # Add N8N_PROXY_HOPS if missing
        if ! grep -q "N8N_PROXY_HOPS" docker-compose.yml; then
            echo "   ⚠️  Adding N8N_PROXY_HOPS=1..."
            sed -i '/WEBHOOK_URL/a\      - N8N_PROXY_HOPS=1' docker-compose.yml
        fi
        
        # Clear old data if there are errors
        if docker ps -a --filter "name=n8n-$CLIENT_ID" --format "{{.Names}}" | grep -q "n8n-$CLIENT_ID"; then
            if docker logs n8n-$CLIENT_ID 2>&1 | grep -q "Database is not ready\|encryption key\|connection"; then
                echo "   ⚠️  Found errors, clearing data..."
                rm -rf data postgres redis
                mkdir -p data postgres redis
                chmod 777 data
            fi
        else
            echo "   Creating fresh data directories..."
            rm -rf data postgres redis
            mkdir -p data postgres redis
            chmod 777 data
        fi
        
        # Start containers
        echo "   Starting containers..."
        docker compose up -d
        
        sleep 10
        cd "$BASE_DIR"
    fi
done

# Step 4: Wait for initialization
echo ""
echo "4️⃣ Waiting for services to initialize (60 seconds)..."
sleep 60

# Step 5: Final status
echo ""
echo "=========================================="
echo "📊 FINAL STATUS CHECK"
echo "=========================================="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAME|traefik|n8n|postgres|redis"

echo ""
echo "Testing connections:"
for CLIENT_DIR in clients/*/; do
    if [ -d "$CLIENT_DIR" ]; then
        CLIENT_ID=$(basename "$CLIENT_DIR")
        echo ""
        echo "Testing ${CLIENT_ID}.n8n.fabricsync.cloud..."
        curl -I https://${CLIENT_ID}.n8n.fabricsync.cloud 2>&1 | head -3
    fi
done

echo ""
echo "✅ ALL FIXES COMPLETE!"
SCRIPT_EOF

chmod +x VPS-FIX-ALL.sh
```

#### **Option B: Use Git to Pull Updated Scripts**

If you've pushed the scripts to your GitHub repo:
```bash
git pull origin master
chmod +x *.sh
```

### **Step 4: Run the Comprehensive Fix**

```bash
./VPS-FIX-ALL.sh
```

### **Step 5: Fix Individual Clients (If Needed)**

For specific clients like `sadam`:

```bash
# Navigate to client directory
cd /var/www/n8n-free-Server/clients/sadam

# Stop containers
docker compose down

# Clear old data
rm -rf data postgres redis

# Recreate directories
mkdir -p data postgres redis
chmod 777 data

# Add N8N_PROXY_HOPS if missing
if ! grep -q "N8N_PROXY_HOPS" docker-compose.yml; then
    sed -i '/WEBHOOK_URL/a\      - N8N_PROXY_HOPS=1' docker-compose.yml
fi

# Start containers
docker compose up -d

# Wait and check
sleep 90
docker logs n8n-sadam --tail 30
curl -I https://sadam.n8n.fabricsync.cloud
```

### **Step 6: Verify Everything Works**

```bash
# Check all containers are running
docker ps

# Check Traefik logs for routing
docker logs traefik | tail -50

# Test each client URL
curl -I https://demo.n8n.fabricsync.cloud
curl -I https://sadam.n8n.fabricsync.cloud
```

### **Common Issues & Solutions**

1. **"Database is not ready!"**
   - Wait 60-90 seconds after container start
   - Check Postgres logs: `docker logs postgres-<client-id>`

2. **"Bad Gateway"**
   - Verify container is on `n8n-proxy` network:
     ```bash
     docker network inspect n8n-proxy | grep n8n-<client-id>
     ```
   - If missing, connect manually:
     ```bash
     docker network connect n8n-proxy n8n-<client-id>
     ```

3. **404 Page Not Found**
   - Check Traefik labels in docker-compose.yml
   - Restart Traefik: `docker restart traefik`

4. **Network Issues**
   - Verify network exists: `docker network ls | grep n8n-proxy`
   - Recreate if needed: `docker network create n8n-proxy`

## Quick Reference Commands

```bash
# View all containers
docker ps -a

# View logs
docker logs n8n-<client-id> -f

# Restart a client
cd /var/www/n8n-free-Server/clients/<client-id>
docker compose restart

# Check Traefik routing
docker logs traefik | grep <client-id>

# Verify network connectivity
docker network inspect n8n-proxy
```

