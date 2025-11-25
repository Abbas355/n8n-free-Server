#!/bin/bash
# diagnose-clients.sh - Check all client instances

BASE_DIR="/var/www/n8n-free-Server"
cd "$BASE_DIR" 2>/dev/null || {
    echo "❌ Cannot access $BASE_DIR"
    exit 1
}

echo "=========================================="
echo "🔍 Diagnosing All Client Instances"
echo "=========================================="

# Check Traefik
echo ""
echo "📊 Traefik Status:"
if docker ps | grep -q traefik; then
    echo "✅ Traefik is running"
    docker ps | grep traefik
else
    echo "❌ Traefik is NOT running!"
fi

echo ""
echo "📊 All Client Containers:"
CLIENT_CONTAINERS=$(docker ps -a --format "{{.Names}}" | grep -E "^(n8n|postgres|redis)-")
if [ -z "$CLIENT_CONTAINERS" ]; then
    echo "⚠️  No client containers found"
else
    docker ps -a | grep -E "^(n8n|postgres|redis)-"
fi

echo ""
echo "=========================================="
echo "Checking each client directory:"
echo "=========================================="

for CLIENT_DIR in clients/*/; do
    if [ -d "$CLIENT_DIR" ]; then
        CLIENT_ID=$(basename "$CLIENT_DIR")
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Client: $CLIENT_ID"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        cd "$CLIENT_DIR" 2>/dev/null || continue
        
        echo "📍 Directory: $(pwd)"
        echo ""
        
        # Check containers
        echo "📦 Containers:"
        docker ps -a --filter "name=$CLIENT_ID" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || echo "   No containers found"
        
        # Check networks
        echo ""
        echo "🔗 Network Connectivity:"
        if docker ps --filter "name=n8n-$CLIENT_ID" --format "{{.Names}}" | grep -q "n8n-$CLIENT_ID"; then
            NETWORKS=$(docker inspect n8n-$CLIENT_ID 2>/dev/null | grep -A 10 "Networks" | grep -E "(n8n-proxy|${CLIENT_ID}-internal)" | head -2)
            if echo "$NETWORKS" | grep -q "n8n-proxy"; then
                echo "   ✅ Connected to n8n-proxy network"
            else
                echo "   ❌ NOT connected to n8n-proxy network!"
            fi
            if echo "$NETWORKS" | grep -q "${CLIENT_ID}-internal"; then
                echo "   ✅ Connected to ${CLIENT_ID}-internal network"
            else
                echo "   ⚠️  Not connected to ${CLIENT_ID}-internal network"
            fi
        else
            echo "   ⚠️  n8n container not running"
        fi
        
        # Check logs
        echo ""
        echo "📝 n8n Logs (last 5 lines):"
        docker logs n8n-$CLIENT_ID --tail 5 2>&1 | head -5 || echo "   ❌ Cannot read logs"
        
        # Check Postgres
        echo ""
        echo "🗄️ Postgres Status:"
        if docker ps --filter "name=postgres-$CLIENT_ID" --format "{{.Names}}" | grep -q "postgres-$CLIENT_ID"; then
            if docker exec postgres-$CLIENT_ID pg_isready -U n8nuser 2>/dev/null; then
                echo "   ✅ Postgres is ready"
            else
                echo "   ❌ Postgres NOT ready"
            fi
        else
            echo "   ⚠️  Postgres container not running"
        fi
        
        # Check docker-compose.yml
        echo ""
        echo "📄 Configuration Check:"
        if [ -f "docker-compose.yml" ]; then
            if grep -q "N8N_PROXY_HOPS" docker-compose.yml; then
                echo "   ✅ N8N_PROXY_HOPS is configured"
            else
                echo "   ❌ N8N_PROXY_HOPS is MISSING!"
            fi
            if grep -q "n8n-proxy" docker-compose.yml; then
                echo "   ✅ n8n-proxy network configured"
            else
                echo "   ❌ n8n-proxy network MISSING!"
            fi
        else
            echo "   ❌ docker-compose.yml not found!"
        fi
        
        cd "$BASE_DIR"
    fi
done

echo ""
echo "=========================================="
echo "✅ Diagnosis Complete"
echo "=========================================="
echo ""
echo "📋 Quick Fix Commands:"
echo "  To fix a client: ./fix-client.sh <client-id>"
echo "  To re-provision: ./provision-client.sh <client-name>"
echo "=========================================="

