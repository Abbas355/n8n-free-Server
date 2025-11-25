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
    cd "$BASE_DIR"
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
        
        # Check if docker-compose.yml exists and is valid
        if [ ! -f "docker-compose.yml" ]; then
            echo "   ⚠️  No docker-compose.yml found, skipping..."
            cd "$BASE_DIR"
            continue
        fi
        
        # Check if N8N_PROXY_HOPS is missing
        if ! grep -q "N8N_PROXY_HOPS" docker-compose.yml; then
            echo "   ⚠️  Adding N8N_PROXY_HOPS=1..."
            # Use sed to add N8N_PROXY_HOPS after WEBHOOK_URL
            sed -i '/WEBHOOK_URL/a\      - N8N_PROXY_HOPS=1' docker-compose.yml
        fi
        
        # Clear old data if there are connection issues
        if docker ps -a --filter "name=n8n-$CLIENT_ID" --format "{{.Names}}" | grep -q "n8n-$CLIENT_ID"; then
            echo "   Checking container logs for errors..."
            if docker logs n8n-$CLIENT_ID 2>&1 | grep -q "Database is not ready\|encryption key\|connection"; then
                echo "   ⚠️  Found database/connection errors, clearing data..."
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
        
        # Wait a bit
        sleep 10
        
        cd "$BASE_DIR"
    fi
done

# Step 4: Wait for all to initialize
echo ""
echo "4️⃣ Waiting for all services to initialize (60 seconds)..."
sleep 60

# Step 5: Final status check
echo ""
echo "=========================================="
echo "📊 FINAL STATUS CHECK"
echo "=========================================="
echo ""
echo "All containers:"
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
echo "=========================================="
echo "✅ ALL FIXES COMPLETE!"
echo "=========================================="
echo ""
echo "📋 Next Steps:"
echo "1. Wait 2-3 minutes for full initialization"
echo "2. Check logs: docker logs n8n-<client-id> -f"
echo "3. Access: https://<client-id>.n8n.fabricsync.cloud"
echo "=========================================="

