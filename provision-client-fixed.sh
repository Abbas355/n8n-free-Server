#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: ./provision-client.sh <client-name>"
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

DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
ENCRYPTION_KEY=$(openssl rand -hex 32)

mkdir -p "$CLIENT_DIR"/{data,postgres,redis}
chmod -R 777 "$CLIENT_DIR/data"

echo "version: '3.8'
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
      - N8N_PROXY_HOPS=1
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8nuser
      - DB_POSTGRESDB_PASSWORD=${DB_PASSWORD}
      - N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
    volumes:
      - ./data:/home/node/.n8n
    networks:
      - n8n-proxy
      - ${CLIENT_ID}-internal
    depends_on:
      postgres:
        condition: service_healthy
    labels:
      - traefik.enable=true
      - traefik.http.routers.n8n-${CLIENT_ID}.rule=Host(\`${CLIENT_ID}.${DOMAIN}\`)
      - traefik.http.routers.n8n-${CLIENT_ID}.entrypoints=websecure
      - traefik.http.routers.n8n-${CLIENT_ID}.tls.certresolver=letsencrypt
      - traefik.http.services.n8n-${CLIENT_ID}.loadbalancer.server.port=5678
      - traefik.docker.network=n8n-proxy

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
      test: ['CMD-SHELL', 'pg_isready -U n8nuser']
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: redis-${CLIENT_ID}
    restart: unless-stopped
    volumes:
      - ./redis:/data
    networks:
      - ${CLIENT_ID}-internal

networks:
  n8n-proxy:
    external: true
  ${CLIENT_ID}-internal:
    driver: bridge" > "$CLIENT_DIR/docker-compose.yml"

echo "URL=https://${CLIENT_ID}.${DOMAIN}
DB_PASSWORD=${DB_PASSWORD}
ENCRYPTION_KEY=${ENCRYPTION_KEY}" > "$CLIENT_DIR/.env"

cd "$CLIENT_DIR"
docker compose up -d

echo ""
echo "✅ Done! URL: https://${CLIENT_ID}.${DOMAIN}"
echo "Logs: docker logs n8n-${CLIENT_ID} -f"

