#!/bin/bash
# QUICK FIX - Copy this entire script and paste into your VPS terminal

cd /var/www/n8n-free-Server

# Ensure Traefik is running
docker compose -f docker-compose.traefik.yml up -d 2>/dev/null

# Ensure network exists
docker network create n8n-proxy 2>/dev/null || true

# Fix each client
for CLIENT_DIR in clients/*/; do
    [ ! -d "$CLIENT_DIR" ] && continue
    CLIENT_ID=$(basename "$CLIENT_DIR")
    echo "🔧 Fixing $CLIENT_ID..."
    
    cd "$CLIENT_DIR" || continue
    
    # Stop and clear
    docker compose down 2>/dev/null
    rm -rf data postgres redis
    mkdir -p data postgres redis
    chmod 777 data
    
    # Add N8N_PROXY_HOPS if missing
    if [ -f docker-compose.yml ]; then
        if ! grep -q "N8N_PROXY_HOPS" docker-compose.yml; then
            sed -i '/WEBHOOK_URL/a\      - N8N_PROXY_HOPS=1' docker-compose.yml
        fi
        docker compose up -d
    fi
    
    cd /var/www/n8n-free-Server
done

echo "⏳ Waiting 90 seconds for initialization..."
sleep 90

echo "✅ Checking status..."
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "NAME|traefik|n8n|postgres|redis"

echo ""
echo "🌐 Testing URLs..."
for CLIENT_DIR in clients/*/; do
    [ ! -d "$CLIENT_DIR" ] && continue
    CLIENT_ID=$(basename "$CLIENT_DIR")
    echo -n "  ${CLIENT_ID}.n8n.fabricsync.cloud: "
    curl -s -o /dev/null -w "%{http_code}\n" https://${CLIENT_ID}.n8n.fabricsync.cloud || echo "failed"
done

echo ""
echo "✅ Done! Check logs with: docker logs n8n-<client-id> -f"

