# 🔧 Troubleshooting Guide

## ❌ Error: "The system cannot find the file specified"

```
open //./pipe/dockerDesktopLinuxEngine: The system cannot find the file specified
```

### Problem
Docker Desktop is not fully running or not started at all.

### Solution

#### Step 1: Check if Docker Desktop is Running

Look for the Docker icon in your **system tray** (bottom-right of screen):
- 🐋 **Docker icon present** = Docker is running
- ❌ **No Docker icon** = Docker is not running

#### Step 2: Start Docker Desktop

**Option A: Via Start Menu**
1. Press Windows key
2. Type "Docker Desktop"
3. Click "Docker Desktop"
4. Wait 30-60 seconds for it to start

**Option B: Via File Explorer**
1. Navigate to: `C:\Program Files\Docker\Docker\`
2. Double-click: `Docker Desktop.exe`
3. Wait 30-60 seconds

**Option C: Via PowerShell**
```powershell
Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
```

#### Step 3: Wait for Docker to Fully Start

**Docker Desktop startup takes time!** You'll know it's ready when:

✅ Docker icon appears in system tray
✅ Icon shows "Docker Desktop is running"
✅ You can click icon and see "Engine running"

**Typical startup time:** 30-90 seconds

#### Step 4: Verify Docker is Ready

Open PowerShell and run:
```powershell
docker info
```

**Should see:**
```
Server:
 Containers: X
 Running: X
 Paused: 0
 Stopped: X
 Images: X
```

**If you see errors**, Docker is not fully started yet. Wait another minute.

#### Step 5: Try Again

Once Docker is running, run:
```bash
start-multi-instance-safe.bat
```

This new script checks if Docker is running before starting instances.

---

## 🐛 Common Issues

### Issue 1: Docker Desktop Won't Start

**Symptoms:**
- Double-clicking Docker Desktop does nothing
- Icon doesn't appear in system tray
- Error messages about virtualization

**Solutions:**

#### A. Enable Virtualization in BIOS
1. Restart computer
2. Enter BIOS (usually F2, F10, or Delete key)
3. Find "Virtualization" or "Intel VT-x" or "AMD-V"
4. Enable it
5. Save and restart

#### B. Enable WSL 2 (Windows Subsystem for Linux)
```powershell
# Run as Administrator
wsl --install
wsl --set-default-version 2
```

Restart computer after this.

#### C. Enable Hyper-V (Windows Pro/Enterprise)
1. Open "Turn Windows features on or off"
2. Enable "Hyper-V"
3. Enable "Windows Subsystem for Linux"
4. Restart computer

#### D. Check Windows Version
Docker Desktop requires:
- Windows 10/11 Pro, Enterprise, or Education
- **OR** Windows 10/11 Home with WSL 2

---

### Issue 2: Instances Start But Can't Access

**Symptoms:**
```
✓ Client A starting...
✓ Client B starting...
```
But http://localhost:5678 doesn't load.

**Solutions:**

#### Check Container Status
```bash
docker ps
```

**Should see 6 containers:**
- n8n-client-a
- postgres-client-a
- redis-client-a
- n8n-client-b
- postgres-client-b
- redis-client-b

#### Check Logs
```bash
# Client A logs
docker-compose -f docker-compose.client-a.yml logs n8n-client-a

# Look for:
# "Editor is now accessible via:"
# "http://localhost:5678"
```

#### Common Reasons

**A. Still Starting (needs more time)**
```bash
# Wait 2-3 minutes, especially first time
# Docker needs to:
# 1. Download images (5-10 min first time)
# 2. Initialize database (1-2 min)
# 3. Run migrations (1-2 min)
# 4. Start n8n (30 sec)
```

**B. Port Already in Use**
```bash
# Check if port 5678 is already used
netstat -ano | findstr "5678"

# If something is using it, either:
# 1. Stop that application
# 2. Change port in docker-compose.client-a.yml
```

**C. Container Failed to Start**
```bash
# Check container status
docker ps -a

# If STATUS shows "Exited", check logs:
docker logs n8n-client-a
```

---

### Issue 3: "version is obsolete" Warning

**Warning Message:**
```
the attribute `version` is obsolete, it will be ignored
```

**Solution:**
This is just a **warning**, not an error. It doesn't affect functionality.

To remove it, edit the docker-compose files and remove the first line:
```yaml
version: '3.8'  # ← Delete this line
```

---

### Issue 4: Images Won't Download

**Error:**
```
Error pulling image
Error response from daemon: Get https://registry-1.docker.io/...
```

**Solutions:**

#### A. Check Internet Connection
```bash
# Test Docker Hub
ping registry-1.docker.io
```

#### B. Use Docker Hub Mirror (if in restricted region)
Edit Docker Desktop settings:
1. Right-click Docker icon → Settings
2. Docker Engine
3. Add mirror:
```json
{
  "registry-mirrors": ["https://mirror.gcr.io"]
}
```

#### C. Manual Download
```bash
docker pull n8nio/n8n:latest
docker pull postgres:16-alpine
docker pull redis:7-alpine
```

---

### Issue 5: Permission Denied

**Error:**
```
Permission denied while trying to connect to Docker daemon
```

**Solution:**
Run PowerShell/Command Prompt as **Administrator**

---

### Issue 6: Database Won't Start

**Error in logs:**
```
postgres-client-a | ERROR: database "n8n_client_a" does not exist
```

**Solution:**

#### A. Reset Database
```bash
# Stop everything
docker-compose -f docker-compose.client-a.yml down -v

# Remove data
rmdir /S /Q client-data\client-a\postgres

# Start again
docker-compose -f docker-compose.client-a.yml up -d
```

#### B. Check PostgreSQL Logs
```bash
docker logs postgres-client-a
```

---

### Issue 7: Out of Disk Space

**Error:**
```
no space left on device
```

**Solution:**

#### Check Docker Disk Usage
```bash
docker system df
```

#### Clean Up Old Images/Containers
```bash
# Remove stopped containers
docker container prune

# Remove unused images
docker image prune -a

# Remove unused volumes
docker volume prune

# Nuclear option (removes everything)
docker system prune -a --volumes
```

---

## 🔍 Diagnostic Commands

### Check Docker Status
```bash
docker info
docker version
docker ps
docker ps -a  # Include stopped containers
```

### Check Logs
```bash
# All logs
docker-compose -f docker-compose.client-a.yml logs

# Specific container
docker logs n8n-client-a

# Follow logs (live)
docker logs n8n-client-a -f

# Last 50 lines
docker logs n8n-client-a --tail 50
```

### Check Health
```bash
# Container health
docker inspect n8n-client-a | findstr Health

# n8n health endpoint
curl http://localhost:5678/healthz
curl http://localhost:5679/healthz
```

### Check Ports
```bash
# What's using port 5678?
netstat -ano | findstr "5678"

# Docker port mapping
docker port n8n-client-a
```

### Check Networks
```bash
# List networks
docker network ls

# Inspect network
docker network inspect client-a-network
```

### Check Volumes
```bash
# List volumes
docker volume ls

# Inspect volume
docker volume inspect client-data_client-a-n8n-data
```

---

## 🆘 Emergency Reset

If nothing works, **nuclear option**:

```bash
# 1. Stop all containers
docker-compose -f docker-compose.client-a.yml down -v
docker-compose -f docker-compose.client-b.yml down -v

# 2. Remove all data
rmdir /S /Q client-data

# 3. Remove all Docker resources (⚠️ WARNING: This removes EVERYTHING)
docker system prune -a --volumes -f

# 4. Restart Docker Desktop
# Right-click Docker icon → Quit Docker Desktop
# Start Docker Desktop again

# 5. Wait for Docker to fully start

# 6. Try again
start-multi-instance-safe.bat
```

---

## 📞 Getting More Help

### Check Docker Desktop Logs
1. Right-click Docker icon
2. Click "Troubleshoot"
3. View logs

### Run Docker Diagnostics
1. Right-click Docker icon
2. Click "Troubleshoot"
3. Click "Run diagnostics"

### Check System Requirements
- **Windows 10/11** (64-bit)
- **4GB RAM minimum** (8GB recommended)
- **20GB free disk space**
- **Virtualization enabled** in BIOS

---

## ✅ Verification Checklist

Before running the setup, verify:

- [ ] Docker Desktop is installed
- [ ] Docker Desktop is running (icon in system tray)
- [ ] `docker info` works without errors
- [ ] `docker ps` works without errors
- [ ] Ports 5678 and 5679 are free
- [ ] Internet connection is working
- [ ] At least 4GB RAM available
- [ ] At least 10GB disk space available

---

## 🎯 Step-by-Step First-Time Setup

If this is your first time:

1. **Install Docker Desktop** (if not installed)
   - Download: https://www.docker.com/products/docker-desktop/
   - Install and restart computer

2. **Start Docker Desktop**
   - Look for Docker icon in system tray
   - Wait until status is "Engine running"

3. **Verify Docker works**
   ```bash
   docker run hello-world
   ```
   Should download and run successfully.

4. **Pull images (saves time later)**
   ```bash
   docker pull n8nio/n8n:latest
   docker pull postgres:16-alpine
   docker pull redis:7-alpine
   ```
   This takes 5-10 minutes.

5. **Run setup**
   ```bash
   start-multi-instance-safe.bat
   ```

6. **Wait patiently**
   - First run takes 3-5 minutes
   - Subsequent runs take 30-60 seconds

7. **Access instances**
   - Client A: http://localhost:5678
   - Client B: http://localhost:5679

---

## 📊 Expected Behavior

### Normal Startup Sequence

```
[0/5] Checking Docker... ✓
[1/5] Creating directories... ✓
[2/5] Pulling images... (5-10 min first time)
[3/5] Starting Client A... ✓
[4/5] Starting Client B... ✓
[5/5] Waiting 60 seconds... ⏳
      Checking health... ✓
      
Setup Complete!
Client A: http://localhost:5678 ← Should be accessible
Client B: http://localhost:5679 ← Should be accessible
```

### What You Should See

**In Docker Desktop:**
- 6 containers running (green status)
- n8n-client-a, postgres-client-a, redis-client-a
- n8n-client-b, postgres-client-b, redis-client-b

**In Browser:**
- http://localhost:5678 → n8n welcome screen
- http://localhost:5679 → n8n welcome screen (different instance)

---

**Still having issues?** Let me know the exact error message and I'll help! 🚀

