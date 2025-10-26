# Running Multiple n8n Instances - Step by Step Guide

## 🎯 Concept Overview

This setup demonstrates how to run **multiple isolated n8n instances** on the same machine. Each client gets their own:
- n8n application
- PostgreSQL database
- Redis queue
- Data storage
- Port

## 📂 Directory Structure

```
n8n-project/
├── docker-compose.client-a.yml    # Client A configuration
├── docker-compose.client-b.yml    # Client B configuration
├── client-data/                   # All client data (isolated)
│   ├── client-a/
│   │   ├── n8n/                   # n8n workflows, credentials
│   │   ├── postgres/              # Database files
│   │   └── redis/                 # Queue data
│   └── client-b/
│       ├── n8n/
│       ├── postgres/
│       └── redis/
└── README-MULTI-INSTANCE.md       # This file
```

## 🔑 Key Differences Between Instances

### Client A (Instance 1)
- **Port**: 5678
- **URL**: http://localhost:5678
- **Database**: `n8n_client_a`
- **Encryption Key**: `client_a_encryption_key_abcdef123456`
- **Network**: `client-a-network` (isolated)
- **Data**: `./client-data/client-a/`

### Client B (Instance 2)
- **Port**: 5679 ⚡ (DIFFERENT)
- **URL**: http://localhost:5679 ⚡
- **Database**: `n8n_client_b` ⚡ (SEPARATE)
- **Encryption Key**: `client_b_encryption_key_xyz789` ⚡ (DIFFERENT)
- **Network**: `client-b-network` ⚡ (ISOLATED)
- **Data**: `./client-data/client-b/` ⚡ (SEPARATE)

---

## 🚀 Step-by-Step Instructions

### Step 1: Create Directory Structure

```bash
# Create data directories for both clients
mkdir -p client-data/client-a/{n8n,postgres,redis,custom-nodes}
mkdir -p client-data/client-b/{n8n,postgres,redis,custom-nodes}
```

### Step 2: Start Client A (First Instance)

```bash
# Start Client A instance
docker-compose -f docker-compose.client-a.yml up -d

# Check logs
docker-compose -f docker-compose.client-a.yml logs -f

# Wait for "Editor is now accessible via:" message
```

**Access Client A**: http://localhost:5678

### Step 3: Start Client B (Second Instance)

```bash
# Start Client B instance (in a new terminal)
docker-compose -f docker-compose.client-b.yml up -d

# Check logs
docker-compose -f docker-compose.client-b.yml logs -f
```

**Access Client B**: http://localhost:5679

### Step 4: Verify Both Are Running

```bash
# Check running containers
docker ps

# You should see:
# - n8n-client-a (port 5678)
# - n8n-client-b (port 5679)
# - postgres-client-a
# - postgres-client-b
# - redis-client-a
# - redis-client-b
```

### Step 5: Test Isolation

Open both URLs in separate browser tabs:
- http://localhost:5678 (Client A)
- http://localhost:5679 (Client B)

Create a workflow in each instance - they won't see each other's data!

---

## 🛠️ Management Commands

### Start Instances
```bash
# Start Client A
docker-compose -f docker-compose.client-a.yml up -d

# Start Client B
docker-compose -f docker-compose.client-b.yml up -d

# Start both at once
docker-compose -f docker-compose.client-a.yml -f docker-compose.client-b.yml up -d
```

### Stop Instances
```bash
# Stop Client A
docker-compose -f docker-compose.client-a.yml down

# Stop Client B
docker-compose -f docker-compose.client-b.yml down

# Stop both
docker-compose -f docker-compose.client-a.yml down && docker-compose -f docker-compose.client-b.yml down
```

### View Logs
```bash
# Client A logs
docker-compose -f docker-compose.client-a.yml logs -f n8n-client-a

# Client B logs
docker-compose -f docker-compose.client-b.yml logs -f n8n-client-b
```

### Restart Instances
```bash
# Restart Client A
docker-compose -f docker-compose.client-a.yml restart

# Restart Client B
docker-compose -f docker-compose.client-b.yml restart
```

### Remove Everything (Clean Slate)
```bash
# Stop and remove containers
docker-compose -f docker-compose.client-a.yml down -v
docker-compose -f docker-compose.client-b.yml down -v

# Remove data (⚠️ WARNING: This deletes all workflows!)
rm -rf client-data/
```

---

## 📊 Resource Usage

Each instance uses approximately:
- **CPU**: 0.5-1 core
- **RAM**: 500MB-1GB
- **Disk**: 500MB-2GB (grows with workflows)

With 2 instances running:
- **Total CPU**: ~2 cores
- **Total RAM**: ~2GB
- **Total Disk**: ~4GB

---

## 🔍 How to Verify Isolation

### 1. Check Different Databases
```bash
# Connect to Client A database
docker exec -it postgres-client-a psql -U client_a_user -d n8n_client_a -c "SELECT * FROM workflow_entity;"

# Connect to Client B database
docker exec -it postgres-client-b psql -U client_b_user -d n8n_client_b -c "SELECT * FROM workflow_entity;"

# Different results = isolated ✅
```

### 2. Check Network Isolation
```bash
# Client A containers
docker network inspect client-a-network

# Client B containers
docker network inspect client-b-network

# Different networks = isolated ✅
```

### 3. Create Test Workflows
1. Go to http://localhost:5678 (Client A)
2. Create a workflow called "Client A Test"
3. Go to http://localhost:5679 (Client B)
4. You won't see "Client A Test" workflow ✅

---

## 🎓 Understanding the Architecture

### What Makes Each Instance Isolated?

```yaml
1. Different Ports:
   Client A → 5678
   Client B → 5679
   
2. Separate Databases:
   Client A → postgres-client-a → n8n_client_a
   Client B → postgres-client-b → n8n_client_b
   
3. Different Encryption Keys:
   Client A → client_a_encryption_key_abcdef123456
   Client B → client_b_encryption_key_xyz789
   
4. Isolated Networks:
   Client A → client-a-network
   Client B → client-b-network
   
5. Separate File Storage:
   Client A → ./client-data/client-a/
   Client B → ./client-data/client-b/
```

### Communication Flow

```
Client A:
Browser → http://localhost:5678 → n8n-client-a → postgres-client-a ✅
                                                → redis-client-a ✅

Client B:
Browser → http://localhost:5679 → n8n-client-b → postgres-client-b ✅
                                                → redis-client-b ✅

❌ Client A CANNOT access Client B's data
❌ Client B CANNOT access Client A's data
```

---

## 🚦 Health Checks

### Check if instances are healthy:
```bash
# Client A health
curl http://localhost:5678/healthz

# Client B health
curl http://localhost:5679/healthz

# Both should return: {"status":"ok"}
```

### Check container health:
```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
```

Should show "healthy" status for all containers.

---

## 🔐 Security Notes

### Each Client Has:
1. **Unique encryption key** - Credentials encrypted differently
2. **Separate database user** - No cross-database access
3. **Isolated network** - Containers can't talk to other clients
4. **Own Redis instance** - Queue data isolated

### In Production:
- Use strong, randomly generated encryption keys
- Use environment variables for secrets (not hardcoded)
- Enable SSL/TLS
- Use firewall rules
- Regular backups per client

---

## 📈 Scaling to More Clients

### Adding Client C:

1. Copy `docker-compose.client-b.yml` to `docker-compose.client-c.yml`
2. Replace all occurrences of:
   - `client-b` → `client-c`
   - Port `5679` → `5680`
   - Database name, user, password (make unique)
   - Encryption key (generate new)
3. Start: `docker-compose -f docker-compose.client-c.yml up -d`

### Pattern for N Clients:
```
Client 1: Port 5678
Client 2: Port 5679
Client 3: Port 5680
Client N: Port 5678 + (N-1)
```

---

## 🎯 Next Steps (Automation)

Once you understand this manual setup, you can automate:

1. **Provisioning Script**: Generate docker-compose files automatically
2. **Control Panel**: Web UI to manage all clients
3. **Monitoring**: Track all instances from one dashboard
4. **Backups**: Automated per-client backups
5. **Scaling**: Kubernetes for production

---

## 🐛 Troubleshooting

### Instance Won't Start
```bash
# Check logs
docker-compose -f docker-compose.client-a.yml logs

# Common issues:
# 1. Port already in use → Change port in yml file
# 2. Database not ready → Wait 30 seconds
# 3. Disk space → Check with: df -h
```

### Can't Access Instance
```bash
# Check if container is running
docker ps | grep n8n-client-a

# Check port binding
netstat -an | grep 5678  # Windows
lsof -i :5678            # Mac/Linux

# Test health endpoint
curl http://localhost:5678/healthz
```

### Database Connection Failed
```bash
# Check PostgreSQL logs
docker logs postgres-client-a

# Verify database exists
docker exec -it postgres-client-a psql -U client_a_user -l
```

---

## 📚 Key Learnings

After completing this exercise, you understand:

✅ How to run multiple isolated n8n instances
✅ Each client gets completely separate:
   - Application instance
   - Database
   - Queue system
   - File storage
✅ How to use Docker Compose for orchestration
✅ Network isolation concepts
✅ Resource management
✅ Ready to build automation on top!

---

## 💡 Production Considerations

When moving to production:

1. **Use Kubernetes** instead of Docker Compose
2. **Managed databases** (AWS RDS, Google Cloud SQL)
3. **Managed Redis** (ElastiCache, Memorystore)
4. **Load balancer** (Nginx, Traefik)
5. **SSL certificates** (Let's Encrypt)
6. **Monitoring** (Prometheus, Grafana)
7. **Logging** (ELK stack, Loki)
8. **Backups** (Automated to S3)

---

## 🎉 Success!

You now have 2 completely isolated n8n instances running on your machine!

- **Client A**: http://localhost:5678
- **Client B**: http://localhost:5679

Each can have different:
- Users
- Workflows
- Credentials
- Executions
- Settings

This is the foundation for your n8n hosting business! 🚀

