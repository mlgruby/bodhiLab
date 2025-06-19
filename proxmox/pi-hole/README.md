# Pi-hole + Unbound for Proxmox LXC

This directory contains scripts and documentation for setting up Pi-hole with Unbound DNS resolver on LXC containers in Proxmox VE.

## Files

- **`pihole-unbound-lxc-setup.sh`** - Automated installation script
- **`Pi-hole_Unbound_LXC_Guide.md`** - Complete setup and management guide
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

- **Pi-hole** - Network-wide ad blocker and DNS sinkhole
- **Unbound** - Recursive DNS resolver for enhanced privacy
- **LXC Container** - Lightweight virtualization on Proxmox
- **Web Interface** - Easy management through browser
- **Firewall Protection** - UFW configured with appropriate rules

## Requirements

- Proxmox VE 7.0+
- 1GB+ RAM available
- 8GB+ storage space
- Root access to Proxmox host
- Static IP address for container

## Documentation

For detailed installation instructions, troubleshooting, and management commands, see `Pi-hole_Unbound_LXC_Guide.md`.

## Support

For issues and questions:

- Check the comprehensive guide first
- Review Pi-hole documentation: https://docs.pi-hole.net/
- Visit Proxmox documentation: https://pve.proxmox.com/pve-docs/ 
