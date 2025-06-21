# Configuration Files Guide

This directory contains modular configuration files for the Pi-hole + Unbound setup. Each file serves a specific purpose and can be customized independently.

## 📁 Configuration Files

### `setup.conf` - Main Setup Configuration
Contains default values and general settings for the installation script.

**Key Settings:**
- Container defaults (ID, memory, disk, etc.)
- Network defaults (IP, gateway)
- Template and storage preferences
- Feature flags and security settings

**Example Customization:**
```bash
# Change default container settings
DEFAULT_CONTAINER_MEMORY="2048"
DEFAULT_CONTAINER_DISK="16"

# Change default network
DEFAULT_CONTAINER_IP="10.0.1.100/24"
DEFAULT_GATEWAY="10.0.1.1"
```

### `pihole.conf` - Pi-hole Configuration
Contains all Pi-hole specific settings including blocklists, whitelists, and DNS configuration.

**Key Settings:**
- DNS upstream servers
- Blocklist URLs
- Whitelist domains
- Web interface settings
- Logging and privacy levels

**Example Customization:**
```bash
# Add more blocklists
PIHOLE_BLOCKLISTS+=(
    "https://your-custom-blocklist.com/hosts"
)

# Add whitelist domains
PIHOLE_WHITELIST+=(
    "yourdomain.com"
    "trusted-site.org"
)
```

### `unbound.conf` - Unbound DNS Configuration
Contains the complete Unbound DNS resolver configuration in standard Unbound format.

**Key Settings:**
- Performance tuning (threads, cache sizes)
- Security settings (DNSSEC, access control)
- Network access control
- Custom DNS records

**Example Customization:**
```yaml
# Performance tuning
num-threads: 4
rrset-cache-size: 512m
msg-cache-size: 256m

# Add custom DNS records
local-data: "nas.local A 192.168.1.50"
local-data: "printer.local A 192.168.1.100"
```

## 🔧 How to Customize

### 1. **Basic Customization**
Edit the configuration files directly:

```bash
cd proxmox/pi-hole/config
nano setup.conf      # Edit main settings
nano pihole.conf     # Edit Pi-hole settings  
nano unbound.conf    # Edit Unbound settings
```

### 2. **Network-Specific Setup**
For different network ranges:

```bash
# In setup.conf
DEFAULT_CONTAINER_IP="10.0.1.100/24"
DEFAULT_GATEWAY="10.0.1.1"

# In unbound.conf (add your network to access control)
access-control: 10.0.1.0/24 allow
```

### 3. **Performance Tuning**
For high-performance setups:

```bash
# In setup.conf
DEFAULT_CONTAINER_MEMORY="4096"
DEFAULT_CONTAINER_CORES="4"

# In unbound.conf
num-threads: 4
rrset-cache-size: 1g
msg-cache-size: 512m
```

### 4. **Custom Blocklists**
Add your own blocklists:

```bash
# In pihole.conf
PIHOLE_BLOCKLISTS+=(
    "https://your-organization.com/internal-blocklist"
    "https://another-source.com/ads-and-trackers"
)
```

## 🚀 Usage

After customizing the configuration files, run the setup script:

```bash
./pihole-unbound-lxc-setup.sh
```

The script will automatically:
- ✅ Load settings from `setup.conf`
- ✅ Use Pi-hole configuration from `pihole.conf`
- ✅ Apply Unbound configuration from `unbound.conf`
- ✅ Fall back to defaults if files are missing

## 🔍 Validation

The script validates your configuration and shows what settings are loaded:

```
ℹ Loaded main configuration from /path/to/config/setup.conf
✓ Using Unbound configuration from /path/to/config/unbound.conf
✓ Loading Pi-hole configuration from /path/to/config/pihole.conf
```

## 📋 Best Practices

### **1. Backup Your Configs**
```bash
cp -r config config.backup
```

### **2. Version Control**
Keep your customizations in version control:
```bash
git add config/
git commit -m "Custom Pi-hole configuration for production"
```

### **3. Environment-Specific Configs**
Create different config sets:
```bash
config/
├── production/
│   ├── setup.conf
│   ├── pihole.conf
│   └── unbound.conf
├── testing/
│   ├── setup.conf
│   ├── pihole.conf
│   └── unbound.conf
└── development/
    ├── setup.conf
    ├── pihole.conf
    └── unbound.conf
```

### **4. Test Changes**
Always test configuration changes:
```bash
# Test Unbound config syntax
unbound-checkconf config/unbound.conf

# Validate Pi-hole settings
grep -E "^[A-Z_]+=.*" config/pihole.conf
```

## 🛠️ Troubleshooting

### **Configuration Not Loading**
- Check file permissions: `chmod 644 config/*.conf`
- Verify file syntax: Look for missing quotes or syntax errors
- Check script output for loading messages

### **Invalid Settings**
- Review the default values in the original files
- Check Pi-hole and Unbound documentation for valid options
- Use the script's validation output to identify issues

### **Performance Issues**
- Adjust memory and CPU settings in `setup.conf`
- Tune Unbound cache sizes in `unbound.conf`
- Monitor container resources after deployment

## 📚 References

- [Pi-hole Documentation](https://docs.pi-hole.net/)
- [Unbound Documentation](https://nlnetlabs.nl/documentation/unbound/)
- [Proxmox Container Documentation](https://pve.proxmox.com/pve-docs/chapter-pct.html) 