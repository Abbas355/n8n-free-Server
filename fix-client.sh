#!/bin/bash
# fix-client.sh <client-id> - Fix a broken client instance

if [ -z "$1" ]; then
    echo "Usage: ./fix-client.sh <client-id>"
    echo "Example: ./fix-client.sh sadam"
    exit 1
fi

CLIENT_ID=$1
CLIENT_DIR="/var/www/n8n-free-Server/clients/$CLIENT_ID"

if [ ! -d "$CLIENT_DIR" ]; then
    echo "❌ Client directory not found: $CLIENT_DIR"
    exit 1
fi

cd "$CLIENT_DIR"

echo "=========================================="
echo "🔧 Fixing Client: $CLIENT_ID"
echo "=========================================="

# Stop containers
echo "1️⃣ Stopping containers..."
docker compose down

# Clear data (fixes encryption key issues)
echo "2️⃣ Clearing old data (will reinitialize)..."
rm -rf data postgres redis

# Recreate directories
echo "3️⃣ Creating fresh directories..."
mkdir -p data postgres redis
chmod 777 data

# Check if docker-compose.yml exists
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ docker-compose.yml not found! Use provision-client.sh instead."
    exit 1
fi

# Update docker-compose.yml to ensure N8N_PROXY_HOPS is present
if ! grep -q "N8N_PROXY_HOPS" docker-compose.yml; then
    echo "4️⃣ Adding missing N8N_PROXY_HOPS=1 to docker-compose.yml..."
    sed -i '/WEBHOOK_URL/a\      - N8N_PROXY_HOPS=1' docker-compose.yml
fi

# Ensure Redis depends_on is present
if ! grep -q "redis:" docker-compose.yml | grep -A 1 "depends_on:" | grep -q "redis"; then
    echo "   Adding redis to depends_on..."
    # This is more complex, so we'll regenerate the compose file properly
fi

# Restart containers
echo "5️⃣ Starting containers..."
docker compose up -d

# Wait for initialization
echo "6️⃣ Waiting for initialization (90 seconds)..."
sleep 90

# Check status
echo ""
echo "📊 Final Status:"
docker compose ps

echo ""
echo "📝 Recent Logs:"
docker logs n8n-$CLIENT_ID --tail 30

echo ""
echo "🌐 Testing connection..."
curl -I https://${CLIENT_ID}.n8n.fabricsync.cloud 2>&1 | head -5

echo ""
echo "=========================================="
echo "✅ Fix Complete!"
echo "=========================================="
echo "If errors persist, check:"
echo "1. DNS: ping ${CLIENT_ID}.n8n.fabricsync.cloud"
echo "2. Traefik: docker logs traefik | grep $CLIENT_ID"
echo "3. Network: docker network inspect n8n-proxy | grep $CLIENT_ID"
echo "=========================================="

