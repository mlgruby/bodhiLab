# Pi-hole + Unbound LXC Container Setup

This directory contains scripts and configurations for setting up Pi-hole + Unbound DNS server in LXC containers on Proxmox VE, with **multi-node installation support**.

## 🚀 New Multi-Node Installation Features

The setup script now supports installing Pi-hole on multiple Proxmox nodes for:
- **High Availability**: Multiple DNS servers for redundancy
- **Load Distribution**: Distribute DNS queries across nodes
- **Geographic Distribution**: Deploy across different locations in your cluster

## 📁 Directory Structure

```
pi-hole/
├── pihole-unbound-lxc-setup.sh    # Main multi-node installation script
├── update-pihole-config.sh        # Update existing Pi-hole configurations
├── config/                        # Configuration files
│   ├── setup.conf                 # Main setup defaults
│   ├── pihole.conf                # Pi-hole specific settings
│   ├── unbound.conf               # Unbound DNS resolver config
│   └── README.md                  # Configuration guide
├── NETWORK_TROUBLESHOOTING.md     # Network troubleshooting guide
└── README.md                      # This file
```

## 🏗️ Multi-Node Installation Options

### Option A: Install on ALL Nodes (Recommended)
```bash
# Installs Pi-hole on every node in your cluster
# Provides maximum redundancy and load distribution
bash pihole-unbound-lxc-setup.sh
# Choose option 'A' when prompted
```

### Option B: Select Specific Nodes
```bash
# Choose which specific nodes to install on
bash pihole-unbound-lxc-setup.sh
# Choose option 'B' and select node numbers (e.g., "1 3" for nodes 1 and 3)
```

### Option C: Single Node (Quick Setup)
```bash
# Install on current node only
bash pihole-unbound-lxc-setup.sh
# Choose option 'C' for current node only
```

## 📊 Installation Results

The script provides a comprehensive summary showing:
- ✅ **Successful installations** with web interface URLs and passwords
- ⚠️ **Partial installations** (container created but services may need manual fixing)
- ❌ **Failed installations** with error details

Example output:
```
📊 INSTALLATION SUMMARY:

✅ Node: pve1
    Container ID: 200
    Container IP: 192.168.1.100
    Pi-hole Web: http://192.168.1.100/admin
    Web Password: ABC123xyz
    Root Password: DEF456uvw

✅ Node: pve2
    Container ID: 201
    Container IP: 192.168.1.101
    Pi-hole Web: http://192.168.1.101/admin
    Web Password: GHI789rst
    Root Password: JKL012mno

📈 FINAL STATISTICS:
  Successful installations: 2
```

## 🛠️ Quick Setup

1. **Download and prepare the script:**
   ```bash
   # Download the script
   wget https://raw.githubusercontent.com/your-repo/bodhiLab/main/proxmox/pi-hole/pihole-unbound-lxc-setup.sh
   
   # Make it executable
   chmod +x pihole-unbound-lxc-setup.sh
   ```

2. **Run the script as root on any Proxmox node:**
   ```bash
   # Run the script
   ./pihole-unbound-lxc-setup.sh
   
   # Or alternatively
   bash pihole-unbound-lxc-setup.sh
   ```

3. **Choose your installation strategy:**
   - **A**: All nodes (best for high availability)
   - **B**: Select specific nodes
   - **C**: Current node only

4. **Use defaults or customize:**
   - Press Enter for quick setup with defaults
   - Enter 'n' to customize container specs, IPs, etc.

## 🔧 Default Configuration

- **Base Container ID**: 200 (increments: 200, 201, 202...)
- **Base IP Address**: 192.168.1.100 (increments: .100, .101, .102...)
- **Gateway**: 192.168.1.1
- **Resources**: 1GB RAM, 8GB disk, 2 CPU cores
- **Template**: Debian 12 (auto-selected)
- **DNS Blocklists**: High-quality Hagezi lists with 31-43% blocking rates

## 🌐 Network Configuration

Each node gets a unique configuration:
- **Node 1**: Container 200 → IP 192.168.1.100
- **Node 2**: Container 201 → IP 192.168.1.101  
- **Node 3**: Container 202 → IP 192.168.1.102

## 🔗 Using Multiple Pi-holes

After installation, configure your router or devices to use multiple DNS servers:

**Router Configuration:**
- Primary DNS: 192.168.1.100 (first Pi-hole)
- Secondary DNS: 192.168.1.101 (second Pi-hole)

**Device Configuration:**
- Some devices support multiple DNS servers for automatic failover
- Others may need manual switching between Pi-holes

## 📋 Prerequisites

- Proxmox VE cluster with 1-3 nodes
- SSH key authentication between nodes (for multi-node)
- Internet connectivity on all target nodes
- Container templates available (Debian recommended)

## 🚨 Troubleshooting

If installations fail or have issues:

1. **Check the installation summary** for specific error messages
2. **Review the log file**: `/var/log/pihole-lxc-multinode-setup.log`
3. **Consult troubleshooting guide**: `NETWORK_TROUBLESHOOTING.md`
4. **Manual fix for partial installations**: Container exists but may need manual Pi-hole installation

## 🔄 Updating Configurations

Use the update script to modify existing Pi-hole configurations across all nodes:
```bash
bash update-pihole-config.sh
```

## 🏆 Benefits of Multi-Node Setup

- **High Availability**: If one node fails, others continue serving DNS
- **Load Distribution**: Spread DNS queries across multiple servers
- **Redundancy**: Multiple points of failure protection
- **Performance**: Reduced latency with geographically distributed nodes
- **Maintenance**: Update one node while others remain operational

## 🔧 Advanced Usage

For advanced configurations, edit the files in the `config/` directory before running the installation script.

---

**Note**: This script automates the complete setup process. For manual installation or troubleshooting, refer to the individual configuration files and troubleshooting guide.

## Files

- **`pihole-unbound-lxc-setup.sh`** - Automated installation script with network troubleshooting
- **`config/`** - Configuration files directory
  - **`setup.conf`** - Container and setup defaults
  - **`pihole.conf`** - Pi-hole configuration with Hagezi blocklists
  - **`unbound.conf`** - Unbound DNS resolver configuration
  - **`README.md`** - Configuration guide
- **`NETWORK_TROUBLESHOOTING.md`** - Network troubleshooting guide
- **`README.md`** - This file

## Quick Start

1. **Make the script executable:**

   ```bash
   chmod +x pihole-unbound-lxc-setup.sh
   ```

2. **Run the setup script as root on your Proxmox host:**

   ```bash
   ./pihole-unbound-lxc-setup.sh
   ```

3. **Or download and run directly:**

   ```bash
   wget https://raw.githubusercontent.com/mlgruby/bodhiLab/refs/heads/main/proxmox/pi-hole/pihole-unbound-lxc-setup.sh
   chmod +x pihole-unbound-lxc-setup.sh
   ./pihole-unbound-lxc-setup.sh
   ```

## What You Get

- **Pi-hole** - Network-wide ad blocker with premium Hagezi blocklists
- **Unbound** - Recursive DNS resolver for enhanced privacy
- **LXC Container** - Lightweight virtualization on Proxmox
- **Web Interface** - Easy management through browser
- **Firewall Protection** - UFW configured with appropriate rules
- **Network Troubleshooting** - Automatic detection and fixing of common network issues
- **Modular Configuration** - Easy customization through config files

## Requirements

- Proxmox VE 7.0+
- 1GB+ RAM available
- 8GB+ storage space
- Root access to Proxmox host
- Static IP address for container

## Network Troubleshooting

The installation script automatically handles common network issues:

- **Proxmox Firewall** - Detects and fixes restrictive FORWARD policies
- **Container Networking** - Recreates network interfaces if connectivity fails
- **UFW Configuration** - Properly configures firewall with correct order
- **DNS Resolution** - Ensures proper DNS functionality

For detailed troubleshooting information, see **`NETWORK_TROUBLESHOOTING.md`**.

## Configuration

All configuration is modular and stored in the `config/` directory:

- **`setup.conf`** - Modify container defaults, IP addresses, resources
- **`pihole.conf`** - Choose Hagezi blocklist tiers, configure DNS settings
- **`unbound.conf`** - Tune DNS resolver performance and security

## Support

For issues and questions:

- **Network Issues**: Check `NETWORK_TROUBLESHOOTING.md` first
- **Configuration**: See `config/README.md` for detailed options
- **Pi-hole Documentation**: https://docs.pi-hole.net/
- **Proxmox Documentation**: https://pve.proxmox.com/pve-docs/
- **Hagezi Blocklists**: https://github.com/hagezi/dns-blocklists 
