# 🚀 Deploy n8n Hosting to VPS - Quick Guide

## 📋 What You Need

- ✅ Fresh Ubuntu VPS (DigitalOcean, Linode, Vultr, etc.)
- ✅ Domain name (from Namecheap, GoDaddy, etc.)
- ✅ SSH access to VPS
- ✅ This project pushed to GitHub

## ⚡ Quick Start (3 Commands!)

### **On Your VPS:**

```bash
# 1. Connect to VPS
ssh root@YOUR_SERVER_IP

# 2. Clone and run setup script
git clone YOUR_GITHUB_REPO n8n-hosting
cd n8n-hosting
chmod +x VPS-QUICK-START.sh
./VPS-QUICK-START.sh

# 3. Follow prompts and wait 5 minutes
```

**That's it!** Setup is automated.

---

## 📚 Complete Documentation

### **For First-Time Setup:**
👉 **Read: `DEPLOYMENT-GUIDE.md`**
- Complete step-by-step guide
- Explains every command
- Troubleshooting tips
- Security best practices

### **For Quick Reference:**
- `VPS-QUICK-START.sh` - Automated setup script
- `provision-client.sh` - Add new clients
- `backup-all.sh` - Backup all clients

---

## 🎯 After Setup

### **1. Configure DNS (IMPORTANT!)**

Go to your domain registrar and add:

```
Type    Name    Value           TTL
A       @       YOUR_SERVER_IP  300
A       *       YOUR_SERVER_IP  300
```

**Wait 5-10 minutes** for DNS to propagate.

### **2. Deploy First Client**

```bash
cd ~/n8n-hosting
./provision-client.sh demo

# Creates: https://demo.yourdomain.com
```

### **3. Access n8n**

Open: `https://demo.yourdomain.com`

You should see:
- ✅ n8n setup screen
- ✅ Valid SSL certificate
- ✅ Ready to use!

---

## 🎨 Client Management

### **Add New Client**
```bash
./provision-client.sh acme-corp
# Creates: https://acme-corp.yourdomain.com
```

### **View All Clients**
```bash
docker ps --filter "name=n8n-"
```

### **View Client Logs**
```bash
docker logs n8n-demo -f
```

### **Backup All Clients**
```bash
./backup-all.sh
```

---

## 📊 Architecture Overview

```
Internet (Port 443)
       ↓
   Traefik Proxy
       ↓
   Routes by subdomain
       ↓
┌──────┴──────┬──────────┬──────────┐
│             │          │          │
demo.domain  acme.domain  client3.domain
    ↓            ↓             ↓
  n8n-demo   n8n-acme    n8n-client3
  + postgres  + postgres  + postgres
  + redis     + redis     + redis
```

**Key Features:**
- ✅ Each client = unique subdomain
- ✅ Automatic SSL certificates
- ✅ Completely isolated data
- ✅ Only 2 ports used (80, 443)
- ✅ Scales to 1000+ clients

---

## 🔐 Security Features

- ✅ Firewall enabled (UFW)
- ✅ Automatic HTTPS (Let's Encrypt)
- ✅ Data encryption per client
- ✅ Isolated networks
- ✅ Fail2ban protection
- ✅ Automatic security updates

---

## 💾 Backups

### **Automatic Daily Backups**

Configured via cron job:
- Runs at 2 AM daily
- Backs up all client databases
- Backs up all client data
- Keeps 30 days of backups

### **Manual Backup**
```bash
./backup-all.sh
```

### **View Backups**
```bash
ls -lh ~/n8n-hosting/backups/
```

---

## 📈 Monitoring

### **System Monitor**
```
http://YOUR_SERVER_IP:19999
```

### **Traefik Dashboard**
```
https://traefik.yourdomain.com
```

### **Docker Stats**
```bash
docker stats
```

---

## 🛠️ Common Commands

### **Server Management**
```bash
# View all containers
docker ps

# View system resources
htop

# Check disk space
df -h

# View Docker disk usage
docker system df
```

### **Client Management**
```bash
# Restart client
docker restart n8n-demo

# Stop client
cd ~/n8n-hosting/clients/demo
docker compose down

# Start client
cd ~/n8n-hosting/clients/demo
docker compose up -d

# View logs
docker logs n8n-demo -f
```

### **Traefik Management**
```bash
# View logs
docker logs traefik -f

# Restart Traefik
docker restart traefik

# Check certificates
docker exec traefik cat /letsencrypt/acme.json | jq
```

---

## 🚨 Troubleshooting

### **Can't access website?**

1. **Check DNS:**
   ```bash
   nslookup demo.yourdomain.com
   # Should return your server IP
   ```

2. **Check Traefik:**
   ```bash
   docker logs traefik
   ```

3. **Check client:**
   ```bash
   docker logs n8n-demo
   ```

4. **Check firewall:**
   ```bash
   sudo ufw status
   # Ports 80 and 443 should be open
   ```

### **SSL certificate issues?**

```bash
# Check Let's Encrypt logs
docker logs traefik | grep acme

# Restart Traefik
docker restart traefik
```

### **Container won't start?**

```bash
# Check logs
docker logs n8n-demo

# Check disk space
df -h

# Check memory
free -h
```

---

## 📊 Server Requirements

### **Minimum (10 clients)**
- 2 CPU cores
- 4 GB RAM
- 40 GB SSD
- 1 TB bandwidth

### **Recommended (50 clients)**
- 4 CPU cores
- 8 GB RAM
- 100 GB SSD
- 3 TB bandwidth

### **Optimal (100+ clients)**
- 8 CPU cores
- 16 GB RAM
- 200 GB SSD
- 5 TB bandwidth

---

## 💰 Cost Estimate

### **Monthly Costs:**

```
VPS Server (4 CPU, 8GB): $20-40/month
Domain Name: $10-15/year
Monitoring: Free (netdata)
SSL Certificates: Free (Let's Encrypt)
Backups: Included

Total: ~$25-45/month
```

### **Revenue (50 clients @ $50/month):**
```
Revenue: $2,500/month
Costs: $40/month
Profit: $2,460/month ($29,520/year)
```

---

## 🎯 Next Steps

### **Phase 1: Setup ✅**
- Deploy to VPS
- Configure DNS
- Test with demo client

### **Phase 2: Automation**
- Build control panel
- Setup billing (Stripe)
- Email automation
- Client onboarding

### **Phase 3: Scale**
- Add monitoring alerts
- Setup CDN (Cloudflare)
- Multi-server deployment
- Load balancing

---

## 📚 Learning Resources

### **Your Documentation:**
- `DEPLOYMENT-GUIDE.md` - Complete setup guide
- `PRODUCTION-ROUTING.md` - Subdomain routing explained
- `PORT-VS-SUBDOMAIN.md` - Architecture comparison
- `TROUBLESHOOTING.md` - Common issues

### **External Resources:**
- n8n Docs: https://docs.n8n.io/
- Traefik Docs: https://doc.traefik.io/traefik/
- Docker Docs: https://docs.docker.com/

---

## ✅ Deployment Checklist

Before going live:

- [ ] VPS server configured
- [ ] Docker installed
- [ ] Traefik running
- [ ] DNS configured
- [ ] First client deployed
- [ ] HTTPS working
- [ ] Backups configured
- [ ] Monitoring setup
- [ ] Test workflow executed
- [ ] Documentation reviewed

---

## 🎉 Success Criteria

You know it's working when:

✅ `https://demo.yourdomain.com` loads  
✅ Valid SSL certificate (lock icon)  
✅ Can create and run workflows  
✅ Multiple clients working simultaneously  
✅ Automatic backups running  
✅ Monitoring shows all systems healthy  

---

## 🆘 Need Help?

### **Check Logs:**
```bash
# Traefik logs
docker logs traefik -f

# Client logs
docker logs n8n-demo -f

# System logs
journalctl -xe
```

### **Common Issues:**
1. DNS not propagated → Wait 10-15 minutes
2. Port blocked → Check firewall
3. SSL issues → Check Traefik logs
4. Container won't start → Check disk space

---

## 🚀 You're Ready!

You now have:
- ✅ Production-ready n8n hosting platform
- ✅ Automatic SSL for all clients
- ✅ Subdomain-based routing
- ✅ Automated backups
- ✅ System monitoring
- ✅ Scalable architecture

**Start adding clients and grow your business!** 💼

---

**Questions?** Refer to `DEPLOYMENT-GUIDE.md` for detailed explanations.

**Happy Hosting!** 🎊

