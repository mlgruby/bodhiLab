# Pi-hole + Unbound LXC Container Setup Guide

This guide helps you install and configure Pi-hole with Unbound DNS resolver on an LXC container in your Proxmox VE environment.

## Overview

**Pi-hole** is a network-wide ad blocker that acts as a DNS sinkhole, protecting your devices from unwanted content without installing client-side software.

**Unbound** is a recursive DNS resolver that enhances privacy by querying authoritative DNS servers directly, avoiding third-party DNS providers.

## Prerequisites

- Proxmox VE 7.0+ with LXC support
- At least 1GB free RAM for the container
- 8GB+ available storage
- Network access for downloading packages
- Root access to Proxmox host

## Quick Installation

1. **Download and run the setup script:**

   ```bash
   wget -qO- https://raw.githubusercontent.com/mlgruby/bodhiLab/refs/heads/main/proxmox/pi-hole/pihole-unbound-lxc-setup.sh | bash
   ```

2. **Or clone the repository and run locally:**

   ```bash
   git clone https://github.com/mlgruby/bodhiLab.git
   cd bodhiLab/proxmox/pi-hole
   chmod +x pihole-unbound-lxc-setup.sh
   ./pihole-unbound-lxc-setup.sh
   ```

## Manual Configuration Steps

### 1. Container Planning

Before running the script, plan your container configuration:

- **Container ID**: Choose an unused ID (default: 200)
- **IP Address**: Static IP in your network (e.g., 192.168.1.100/24)
- **Gateway**: Your router's IP (e.g., 192.168.1.1)
- **Resources**: 1GB RAM, 2 CPU cores, 8GB storage (minimum)

### 2. Network Configuration

The container needs a static IP address to function as a DNS server. Common network setups:

**Home Network Example:**

- Container IP: `192.168.1.100/24`
- Gateway: `192.168.1.1`
- Bridge: `vmbr0`

**Business Network Example:**

- Container IP: `10.0.1.100/24`
- Gateway: `10.0.1.1`
- Bridge: `vmbr0`

### 3. Running the Setup Script

The script will prompt you for:

1. Container ID
2. Container IP address (CIDR format)
3. Gateway IP address
4. SSH public key path (optional)
5. Memory allocation (MB)
6. Disk size (GB)

## Post-Installation Configuration

### Accessing Pi-hole Web Interface

1. **Open your web browser and navigate to:**

   ```text
   http://[CONTAINER_IP]/admin
   ```

2. **Login with the generated password** (displayed after installation)

### Configuring Network Devices

#### Option 1: Router-level DNS (Recommended)

1. Access your router's admin interface
2. Navigate to DHCP/DNS settings
3. Set primary DNS to your container IP
4. Save and restart router

#### Option 2: Device-level DNS

Configure each device manually:

- **Windows**: Network adapter properties → IPv4 → DNS servers
- **macOS**: System Preferences → Network → Advanced → DNS
- **Linux**: `/etc/resolv.conf` or NetworkManager
- **Mobile**: WiFi settings → Advanced → DNS

### Customizing Blocklists

1. **Access Pi-hole admin interface**
2. **Navigate to Group Management → Adlists**
3. **Add popular blocklists:**

   ```text
   https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
   https://mirror1.malwaredomains.com/files/justdomains
   https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt
   https://s3.amazonaws.com/lists.disconnect.me/simple_ad.txt
   ```

4. **Update gravity:** Tools → Update Gravity

## Management Commands

### Container Management

```bash
# Start container
pct start [CONTAINER_ID]

# Stop container
pct stop [CONTAINER_ID]

# Enter container shell
pct enter [CONTAINER_ID]

# Check container status
pct status [CONTAINER_ID]

# Container resource usage
pct exec [CONTAINER_ID] -- top
```

### Pi-hole Management

```bash
# Access container and run Pi-hole commands
pct enter [CONTAINER_ID]

# Pi-hole status
pihole status

# Update Pi-hole
pihole -up

# Update blocklists
pihole -g

# Flush DNS cache
pihole restartdns

# View real-time query log
pihole -t
```

### Unbound Management

```bash
# Check Unbound status
pct exec [CONTAINER_ID] -- systemctl status unbound

# Restart Unbound
pct exec [CONTAINER_ID] -- systemctl restart unbound

# Test DNS resolution
pct exec [CONTAINER_ID] -- dig @127.0.0.1 -p 5335 google.com

# View Unbound logs
pct exec [CONTAINER_ID] -- journalctl -u unbound -f
```

## Troubleshooting

### Common Issues

#### 1. DNS Resolution Not Working

```bash
# Test container network connectivity
pct exec [CONTAINER_ID] -- ping 8.8.8.8

# Check if services are running
pct exec [CONTAINER_ID] -- systemctl status pihole-FTL
pct exec [CONTAINER_ID] -- systemctl status unbound

# Test DNS resolution manually
pct exec [CONTAINER_ID] -- nslookup google.com 127.0.0.1
```

#### 2. Web Interface Not Accessible

```bash
# Check lighttpd service
pct exec [CONTAINER_ID] -- systemctl status lighttpd

# Check firewall rules
pct exec [CONTAINER_ID] -- ufw status

# Restart web service
pct exec [CONTAINER_ID] -- systemctl restart lighttpd
```

#### 3. High Memory Usage

```bash
# Check memory usage
pct exec [CONTAINER_ID] -- free -h

# Check Pi-hole cache size
pct exec [CONTAINER_ID] -- pihole -c -e

# Adjust cache size if needed
pct exec [CONTAINER_ID] -- pihole -a -c 5000
```

### Log Files

```bash
# Pi-hole logs
pct exec [CONTAINER_ID] -- tail -f /var/log/pihole.log

# Unbound logs
pct exec [CONTAINER_ID] -- journalctl -u unbound -f

# System logs
pct exec [CONTAINER_ID] -- journalctl -f
```

## Backup and Restore

### Creating Backups

```bash
# Create container backup
vzdump [CONTAINER_ID] --storage [STORAGE_NAME]

# Backup Pi-hole configuration
pct exec [CONTAINER_ID] -- tar -czf /tmp/pihole-backup.tar.gz /etc/pihole/
pct pull [CONTAINER_ID] /tmp/pihole-backup.tar.gz ./pihole-backup.tar.gz
```

### Restoring from Backup

```bash
# Restore container from backup
qmrestore [BACKUP_FILE] [NEW_CONTAINER_ID]

# Restore Pi-hole configuration
pct push [CONTAINER_ID] ./pihole-backup.tar.gz /tmp/pihole-backup.tar.gz
pct exec [CONTAINER_ID] -- tar -xzf /tmp/pihole-backup.tar.gz -C /
pct exec [CONTAINER_ID] -- systemctl restart pihole-FTL
```

## Performance Optimization

### Container Resources

```bash
# Increase memory if needed
pct set [CONTAINER_ID] --memory 2048

# Add more CPU cores
pct set [CONTAINER_ID] --cores 4

# Expand storage
pct resize [CONTAINER_ID] rootfs +4G
```

### Pi-hole Optimization

1. **Adjust cache size** based on network usage
2. **Enable query logging** for monitoring
3. **Use SSD storage** for better performance
4. **Regular blocklist updates** for effectiveness

## Security Considerations

### Firewall Configuration

The setup script configures UFW with these rules:

- SSH (port 22): Allowed
- DNS (port 53): Allowed TCP/UDP
- HTTP (port 80): Allowed
- HTTPS (port 443): Allowed
- All other incoming: Denied

### Additional Security

```bash
# Change default passwords
pct exec [CONTAINER_ID] -- pihole -a -p

# Enable HTTPS (optional)
pct exec [CONTAINER_ID] -- pihole -a -ssl

# Regular updates
pct exec [CONTAINER_ID] -- apt update && apt upgrade -y
pct exec [CONTAINER_ID] -- pihole -up
```

## High Availability Setup

For a 2-node Proxmox cluster, consider:

1. **Primary Pi-hole** on Node 1
2. **Secondary Pi-hole** on Node 2
3. **Configure router** with both IPs as DNS servers
4. **Sync configurations** between instances

### Creating Secondary Instance

```bash
# Run setup script on second node with different IP
./pihole-unbound-lxc-setup.sh

# Sync blocklists and settings
# (Manual process - consider automation)
```

## Monitoring and Maintenance

### Regular Maintenance Tasks

1. **Weekly**: Check logs for errors
2. **Monthly**: Update Pi-hole and system packages
3. **Quarterly**: Review and update blocklists
4. **Annually**: Full container backup and restore test

### Monitoring Scripts

```bash
# Create monitoring script
cat > /usr/local/bin/pihole-monitor.sh << 'EOF'
#!/bin/bash
CONTAINER_ID="200"
echo "=== Pi-hole Monitoring Report ==="
echo "Date: $(date)"
echo "Container Status: $(pct status $CONTAINER_ID)"
pct exec $CONTAINER_ID -- pihole-status.sh
EOF

chmod +x /usr/local/bin/pihole-monitor.sh
```

## Support and Resources

- **Pi-hole Documentation**: https://docs.pi-hole.net/
- **Unbound Documentation**: https://nlnetlabs.nl/documentation/unbound/
- **Proxmox VE Documentation**: https://pve.proxmox.com/pve-docs/
- **Community Forums**: https://discourse.pi-hole.net/

## License

This setup script and documentation are provided under the same license as the parent repository.

---

**Note**: Remember to update your network devices to use the Pi-hole container IP as their DNS server for the ad-blocking to take effect. 