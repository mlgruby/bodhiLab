# Pi-hole LXC Network Troubleshooting Guide

## 🚨 Common Network Issues

### Issue 1: Proxmox Firewall Blocking Container Traffic

**Symptoms:**
- Container cannot reach gateway or internet
- `ping 192.168.1.1` fails from container
- Pi-hole installation fails with "Cannot resolve hostname"

**Root Cause:**
Proxmox firewall sets `FORWARD` chain policy to `DROP`, blocking all traffic between containers and external networks.

**Solution:**
The installation script now automatically detects and fixes this issue by:
1. Detecting Proxmox firewall status
2. Checking for restrictive `FORWARD` policies
3. Temporarily disabling restrictions for container networking
4. Enabling IP forwarding and bridge forwarding

### Issue 2: Container UFW Blocking Outbound Traffic

**Symptoms:**
- Container has network interface but cannot connect out
- DNS resolution fails
- Package downloads fail

**Root Cause:**
UFW (Uncomplicated Firewall) in container is configured incorrectly, blocking outbound connections.

**Solution:**
The installation script now:
1. Resets UFW to clean state
2. Sets outbound policy to ALLOW **before** inbound policy
3. Properly configures required ports

### Issue 3: Network Interface Not Properly Initialized

**Symptoms:**
- Container has correct IP configuration
- Gateway ping fails consistently
- Network interface appears up but doesn't work

**Root Cause:**
LXC network interface sometimes doesn't initialize properly on first creation.

**Solution:**
The installation script now:
1. Tests network connectivity after container creation
2. Automatically recreates network interface with new MAC address if needed
3. Waits for proper network initialization

## 🔧 Manual Troubleshooting Steps

### Check Proxmox Firewall Status

```bash
# Check firewall status
pve-firewall status

# Check iptables FORWARD policy
iptables -L FORWARD | grep policy

# Temporarily disable for testing
systemctl stop pve-firewall
iptables -P FORWARD ACCEPT
```

### Test Container Network

```bash
# Test from container
pct exec 200 -- ping -c 3 192.168.1.1

# Test DNS resolution
pct exec 200 -- nslookup google.com

# Check container network config
pct exec 200 -- ip addr show
pct exec 200 -- ip route show
```

### Fix Container Network Interface

```bash
# Stop container
pct stop 200

# Generate new MAC and recreate interface
NEW_MAC="BC:24:11:$(openssl rand -hex 1):$(openssl rand -hex 1):$(openssl rand -hex 1)"
pct set 200 -net0 name=eth0,bridge=vmbr0,gw=192.168.1.1,hwaddr=$NEW_MAC,ip=192.168.1.100/24,type=veth

# Start container
pct start 200
```

### Fix Container UFW

```bash
# Reset UFW properly
pct exec 200 -- ufw --force reset
pct exec 200 -- ufw default allow outgoing
pct exec 200 -- ufw default deny incoming
pct exec 200 -- ufw allow 22,53,80,443
pct exec 200 -- ufw --force enable
```

## 🛡️ Proxmox Firewall - Do You Need to Disable It?

### Recommendation: **Configure, Don't Disable**

**Why disabling completely isn't ideal:**
- Removes all network security
- Exposes Proxmox management interface
- Allows unrestricted access to all containers

**Better approach - Configure properly:**

1. **Allow container networking** in Proxmox firewall:
```bash
# Edit /etc/pve/firewall/cluster.fw
[OPTIONS]
policy_in: ACCEPT
policy_out: ACCEPT

[RULES]
# Allow container bridge traffic
IN ACCEPT -source 192.168.1.0/24
OUT ACCEPT -dest 192.168.1.0/24

# Allow established connections
IN ACCEPT -match conntrack --ctstate ESTABLISHED,RELATED
```

2. **Enable IP forwarding permanently:**
```bash
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
echo 'net.bridge.bridge-nf-call-iptables=0' >> /etc/sysctl.conf
sysctl -p
```

3. **Create proper firewall rules:**
```bash
# Allow LXC bridge traffic
iptables -I FORWARD -i vmbr0 -o vmbr0 -j ACCEPT
iptables -I FORWARD -s 192.168.1.0/24 -j ACCEPT
iptables -I FORWARD -d 192.168.1.0/24 -j ACCEPT

# Save rules
iptables-save > /etc/iptables/rules.v4
```

### Temporary Disable for Testing Only

If you need to temporarily disable for testing:

```bash
# Disable firewall
systemctl stop pve-firewall
systemctl disable pve-firewall

# Clear restrictive rules
iptables -P FORWARD ACCEPT
iptables -F

# Re-enable after testing with proper config
systemctl enable pve-firewall
systemctl start pve-firewall
```

## ✅ Verification Steps

After running the installation script, verify everything works:

```bash
# 1. Test container network
pct exec 200 -- ping -c 3 192.168.1.1

# 2. Test DNS resolution
pct exec 200 -- nslookup google.com

# 3. Test Pi-hole web interface
curl -I http://192.168.1.100/admin

# 4. Check services
pct exec 200 -- systemctl status pihole-FTL
pct exec 200 -- systemctl status unbound
```

## 🎯 Key Takeaways

1. **Installation script handles most issues automatically**
2. **Proxmox firewall should be configured, not disabled**
3. **UFW configuration order matters** (outbound before inbound)
4. **Network interface recreation often fixes connectivity issues**
5. **Always test connectivity before installing services**

The updated installation script now includes comprehensive network troubleshooting and should handle these issues automatically! 🚀 