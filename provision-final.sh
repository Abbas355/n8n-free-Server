#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: ./provision-client.sh <client-name>"
    exit 1
fi

CLIENT_ID=$(echo $1 | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')
DIR="/var/www/n8n-free-Server/clients/$CLIENT_ID"
DOMAIN="n8n.fabricsync.cloud"
PASS=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
KEY=$(openssl rand -hex 32)

echo "=========================================="
echo "Provisioning: $1"
echo "Client ID: $CLIENT_ID"
echo "URL: https://${CLIENT_ID}.${DOMAIN}"
echo "=========================================="

mkdir -p $DIR/{data,postgres,redis}
chmod 777 $DIR/data

cat > $DIR/docker-compose.yml << 'DOCKEREOF'
services:
  n8n-CLIENT:
    image: n8nio/n8n:latest
    container_name: n8n-CLIENT
    restart: unless-stopped
    environment:
      - N8N_HOST=CLIENT.DOMAIN
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://CLIENT.DOMAIN/
      - N8N_PROXY_HOPS=1
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres-CLIENT
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8nuser
      - DB_POSTGRESDB_PASSWORD=DBPASS
      - N8N_ENCRYPTION_KEY=ENCKEY
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis-CLIENT
    volumes:
      - ./data:/home/node/.n8n
    networks:
      - n8n-proxy
      - CLIENT-net
    labels:
      - traefik.enable=true
      - traefik.http.routers.CLIENT.rule=Host(`CLIENT.DOMAIN`)
      - traefik.http.routers.CLIENT.entrypoints=websecure
      - traefik.http.routers.CLIENT.tls.certresolver=letsencrypt
      - traefik.http.services.CLIENT.loadbalancer.server.port=5678
      - traefik.docker.network=n8n-proxy
  postgres-CLIENT:
    image: postgres:16-alpine
    container_name: postgres-CLIENT
    restart: unless-stopped
    environment:
      - POSTGRES_USER=n8nuser
      - POSTGRES_PASSWORD=DBPASS
      - POSTGRES_DB=n8n
    volumes:
      - ./postgres:/var/lib/postgresql/data
    networks:
      - CLIENT-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U n8nuser"]
      interval: 10s
  redis-CLIENT:
    image: redis:7-alpine
    container_name: redis-CLIENT
    restart: unless-stopped
    volumes:
      - ./redis:/data
    networks:
      - CLIENT-net
networks:
  n8n-proxy:
    external: true
  CLIENT-net:
    driver: bridge
DOCKEREOF

sed -i "s/CLIENT/${CLIENT_ID}/g" $DIR/docker-compose.yml
sed -i "s/DOMAIN/${DOMAIN}/g" $DIR/docker-compose.yml
sed -i "s/DBPASS/${PASS}/g" $DIR/docker-compose.yml
sed -i "s/ENCKEY/${KEY}/g" $DIR/docker-compose.yml

echo "URL=https://${CLIENT_ID}.${DOMAIN}" > $DIR/.env
echo "DB_PASSWORD=${PASS}" >> $DIR/.env
echo "ENCRYPTION_KEY=${KEY}" >> $DIR/.env

cd $DIR && docker compose up -d && sleep 60
docker logs n8n-${CLIENT_ID} --tail 20
echo ""
echo "✅ https://${CLIENT_ID}.${DOMAIN}"





