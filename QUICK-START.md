# 🚀 Quick Start Guide - Running 2 n8n Instances

## ⚡ TL;DR (Just Run This!)

```bash
# Option 1: Automated Script (Easiest)
start-multi-instance.bat

# Option 2: Manual (Understanding)
# See below for step-by-step
```

---

## 📋 Prerequisites

**Before you start, make sure you have:**

✅ Docker Desktop installed and running
✅ Ports 5678 and 5679 available
✅ ~4GB free RAM
✅ ~10GB free disk space

### Check Docker

```bash
docker --version
docker-compose --version
```

If not installed: Download from https://www.docker.com/products/docker-desktop/

---

## 🎯 Option 1: Automated Setup (Recommended)

### Step 1: Run the Script

Simply double-click: **`start-multi-instance.bat`**

Or from command line:
```bash
start-multi-instance.bat
```

### Step 2: Wait 30 seconds

The script will:
- Create directories
- Start Client A (port 5678)
- Start Client B (port 5679)
- Open both in your browser

### Step 3: Access Your Instances

- **Client A**: http://localhost:5678
- **Client B**: http://localhost:5679

---

## 🛠️ Option 2: Manual Setup (For Learning)

### Step 1: Create Directories

```bash
mkdir -p client-data/client-a/n8n
mkdir -p client-data/client-a/postgres
mkdir -p client-data/client-a/redis
mkdir -p client-data/client-b/n8n
mkdir -p client-data/client-b/postgres
mkdir -p client-data/client-b/redis
```

### Step 2: Start Client A

```bash
docker-compose -f docker-compose.client-a.yml up -d
```

**Wait for logs to show:**
```
Editor is now accessible via:
http://localhost:5678
```

Check logs:
```bash
docker-compose -f docker-compose.client-a.yml logs -f
```

Press `Ctrl+C` to exit logs.

### Step 3: Start Client B

```bash
docker-compose -f docker-compose.client-b.yml up -d
```

**Wait for logs to show:**
```
Editor is now accessible via:
http://localhost:5678  (internally, but exposed on 5679)
```

Check logs:
```bash
docker-compose -f docker-compose.client-b.yml logs -f
```

### Step 4: Verify Both Running

```bash
docker ps
```

**You should see 6 containers:**
1. n8n-client-a
2. postgres-client-a
3. redis-client-a
4. n8n-client-b
5. postgres-client-b
6. redis-client-b

### Step 5: Open in Browser

- Client A: http://localhost:5678
- Client B: http://localhost:5679

---

## ✅ Verification Steps

### 1. Check Container Status

```bash
check-instances.bat
```

Or manually:
```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### 2. Health Checks

```bash
# Client A
curl http://localhost:5678/healthz

# Client B
curl http://localhost:5679/healthz
```

Both should return: `{"status":"ok"}`

### 3. Test Isolation

**In Client A (localhost:5678):**
1. Complete setup (create user account)
2. Create a workflow called "Test Workflow A"
3. Save it

**In Client B (localhost:5679):**
1. Complete setup (create DIFFERENT user account)
2. You should NOT see "Test Workflow A" ✅
3. Create a workflow called "Test Workflow B"

**Verification:**
- Go back to Client A → You should NOT see "Test Workflow B" ✅
- Each instance is completely isolated! 🎉

---

## 🎮 Management Commands

### View Logs

```bash
# Client A
docker-compose -f docker-compose.client-a.yml logs -f

# Client B
docker-compose -f docker-compose.client-b.yml logs -f

# Specific container
docker logs n8n-client-a -f
```

### Restart Instances

```bash
# Restart Client A
docker-compose -f docker-compose.client-a.yml restart

# Restart Client B
docker-compose -f docker-compose.client-b.yml restart

# Restart specific container
docker restart n8n-client-b
```

### Stop Instances

```bash
# Stop all (using script)
stop-all-instances.bat

# Or manually
docker-compose -f docker-compose.client-a.yml down
docker-compose -f docker-compose.client-b.yml down
```

### Start Again (After Stopping)

```bash
docker-compose -f docker-compose.client-a.yml up -d
docker-compose -f docker-compose.client-b.yml up -d
```

---

## 🔍 Debugging

### Container Won't Start

```bash
# Check logs
docker-compose -f docker-compose.client-a.yml logs

# Common issues:
# 1. Port already in use
netstat -ano | findstr "5678"  # Check what's using the port

# 2. Docker not running
docker ps  # If error, start Docker Desktop

# 3. Out of memory
docker stats  # Check resource usage
```

### Can't Access Instance

```bash
# 1. Check if container is running
docker ps | findstr n8n-client-a

# 2. Check health
curl http://localhost:5678/healthz

# 3. Check logs
docker logs n8n-client-a --tail 50
```

### Database Connection Issues

```bash
# Check PostgreSQL is running
docker ps | findstr postgres-client-a

# View PostgreSQL logs
docker logs postgres-client-a

# Verify database exists
docker exec -it postgres-client-a psql -U client_a_user -d n8n_client_a -c "\l"
```

### Reset Everything (Nuclear Option)

```bash
# Stop and remove containers
docker-compose -f docker-compose.client-a.yml down -v
docker-compose -f docker-compose.client-b.yml down -v

# Delete all data (⚠️ WARNING: Deletes all workflows!)
rmdir /S /Q client-data

# Start fresh
start-multi-instance.bat
```

---

## 📊 Understanding What's Running

### Client A Stack
```
┌─────────────────┐
│  localhost:5678 │ ← Browser
└────────┬────────┘
         │
    ┌────▼────────────┐
    │ n8n-client-a    │ ← Application
    └────┬────────────┘
         │
    ┌────┴──────────┬──────────────┐
    │               │              │
┌───▼────┐    ┌────▼─────┐  ┌─────▼────┐
│Postgres│    │  Redis   │  │   Data   │
│client-a│    │ client-a │  │ Storage  │
└────────┘    └──────────┘  └──────────┘
```

### Client B Stack
```
┌─────────────────┐
│  localhost:5679 │ ← Browser
└────────┬────────┘
         │
    ┌────▼────────────┐
    │ n8n-client-b    │ ← Application
    └────┬────────────┘
         │
    ┌────┴──────────┬──────────────┐
    │               │              │
┌───▼────┐    ┌────▼─────┐  ┌─────▼────┐
│Postgres│    │  Redis   │  │   Data   │
│client-b│    │ client-b │  │ Storage  │
└────────┘    └──────────┘  └──────────┘
```

**No connection between Client A and Client B!**

---

## 💾 Backup & Restore

### Backup Client A

```bash
# Stop the instance
docker-compose -f docker-compose.client-a.yml stop

# Create backup
docker exec postgres-client-a pg_dump -U client_a_user n8n_client_a > backup-client-a.sql
tar -czf backup-client-a-data.tar.gz client-data/client-a

# Restart
docker-compose -f docker-compose.client-a.yml start
```

### Restore Client A

```bash
# Stop the instance
docker-compose -f docker-compose.client-a.yml down

# Restore data
tar -xzf backup-client-a-data.tar.gz

# Start and restore database
docker-compose -f docker-compose.client-a.yml up -d
docker exec -i postgres-client-a psql -U client_a_user n8n_client_a < backup-client-a.sql
```

---

## 📈 Adding More Clients

### Client C (Port 5680)

1. Copy `docker-compose.client-b.yml` to `docker-compose.client-c.yml`
2. Replace in the file:
   - `client-b` → `client-c`
   - `5679` → `5680`
   - Database password (make unique)
   - Encryption key (make unique)
3. Create directories:
   ```bash
   mkdir -p client-data/client-c/{n8n,postgres,redis}
   ```
4. Start:
   ```bash
   docker-compose -f docker-compose.client-c.yml up -d
   ```

### Pattern for More Clients

```
Client 1: Port 5678
Client 2: Port 5679
Client 3: Port 5680
Client 4: Port 5681
...and so on
```

---

## 🎯 What You've Learned

After completing this, you now understand:

✅ How to run multiple isolated n8n instances
✅ Each client has completely separate:
   - Application
   - Database
   - Queue
   - Storage
✅ How Docker Compose orchestrates services
✅ Network isolation concepts
✅ Port mapping (host:container)
✅ Volume mounting (persistent data)
✅ Health checks and monitoring

---

## 🚀 Next Steps

Once comfortable with this setup:

1. **Study the Docker Compose files**
   - Understand each configuration option
   - See how environment variables work
   - Learn about volumes and networks

2. **Build automation**
   - Script to generate docker-compose files
   - API to manage instances
   - Control panel to visualize

3. **Add monitoring**
   - Prometheus for metrics
   - Grafana for dashboards
   - Alerts for issues

4. **Plan production**
   - Use managed databases (AWS RDS)
   - Add load balancer (Nginx/Traefik)
   - SSL certificates (Let's Encrypt)
   - Multiple servers

---

## 📚 Additional Resources

- **README-MULTI-INSTANCE.md** - Detailed documentation
- **ARCHITECTURE-DIAGRAM.md** - Visual architecture
- **docker-compose.client-*.yml** - Configuration files
- **n8n Documentation**: https://docs.n8n.io/

---

## 🆘 Getting Help

If something doesn't work:

1. Check logs: `docker-compose -f docker-compose.client-a.yml logs`
2. Verify Docker is running: `docker ps`
3. Check ports: `netstat -ano | findstr "5678"`
4. Restart Docker Desktop
5. Reset everything and try again

---

## 🎉 Success Checklist

- [ ] Both instances running
- [ ] Can access Client A (localhost:5678)
- [ ] Can access Client B (localhost:5679)
- [ ] Created workflow in Client A
- [ ] Verified Client B doesn't see it
- [ ] Understand the isolation concept
- [ ] Ready to build automation!

---

**Congratulations! You're now running multiple isolated n8n instances!** 🚀

This is the foundation for your n8n hosting business. Next step: automate this process with code!

