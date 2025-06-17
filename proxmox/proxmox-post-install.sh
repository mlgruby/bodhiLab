#!/bin/bash

#################################################
# Proxmox VE Post-Installation Automation Script
#################################################
# This script automates common post-installation tasks for Proxmox VE
# Based on community best practices and official documentation
#
# Usage: bash proxmox-post-install.sh
# Run as root on freshly installed Proxmox VE system
#################################################

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
LOG_FILE="/var/log/proxmox-post-install.log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Check Proxmox version compatibility
check_proxmox_version() {
    print_info "Checking Proxmox VE version..."
    if ! command -v pveversion &> /dev/null; then
        print_error "Proxmox VE is not installed or pveversion command not found"
        exit 1
    fi
    
    PVE_VERSION=$(pveversion | grep "pve-manager" | cut -d'/' -f2 | cut -d'-' -f1)
    print_success "Detected Proxmox VE version: $PVE_VERSION"
}

# Backup original configurations
backup_configs() {
    print_header "BACKING UP ORIGINAL CONFIGURATIONS"
    
    BACKUP_DIR="/root/proxmox-config-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Backup important config files
    files_to_backup=(
        "/etc/apt/sources.list"
        "/etc/apt/sources.list.d/pve-enterprise.list"
        "/etc/apt/sources.list.d/ceph.list"
        "/etc/hosts"
        "/etc/network/interfaces"
    )
    
    for file in "${files_to_backup[@]}"; do
        if [[ -f "$file" ]]; then
            cp "$file" "$BACKUP_DIR/"
            print_success "Backed up: $file"
        fi
    done
    
    print_success "Configuration backup created at: $BACKUP_DIR"
}

# Configure package repositories
configure_repositories() {
    print_header "CONFIGURING PACKAGE REPOSITORIES"
    
    # Disable enterprise repositories (comment out)
    print_info "Disabling enterprise repositories..."
    
    # Disable Proxmox VE enterprise repository
    if [[ -f "/etc/apt/sources.list.d/pve-enterprise.list" ]]; then
        sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list
        print_success "Proxmox VE enterprise repository disabled"
    fi
    
    # Disable Ceph enterprise repository
    if [[ -f "/etc/apt/sources.list.d/ceph.list" ]]; then
        sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/ceph.list
        print_success "Ceph enterprise repository disabled"
    fi
    
    # Detect Debian version more reliably
    print_info "Detecting Debian version..."
    DEBIAN_VERSION=""
    
    # Try multiple methods to detect Debian version
    if command -v lsb_release >/dev/null 2>&1; then
        DEBIAN_VERSION=$(lsb_release -cs)
        print_info "Detected Debian version using lsb_release: $DEBIAN_VERSION"
    elif [[ -f /etc/os-release ]]; then
        DEBIAN_VERSION=$(grep VERSION_CODENAME /etc/os-release | cut -d'=' -f2)
        print_info "Detected Debian version from os-release: $DEBIAN_VERSION"
    elif [[ -f /etc/debian_version ]]; then
        # Map version numbers to codenames for common versions
        VERSION_NUM=$(cat /etc/debian_version)
        case $VERSION_NUM in
            12*) DEBIAN_VERSION="bookworm" ;;
            11*) DEBIAN_VERSION="bullseye" ;;
            10*) DEBIAN_VERSION="buster" ;;
            *) DEBIAN_VERSION="bookworm" ;; # Default to latest
        esac
        print_info "Detected Debian version from debian_version file: $DEBIAN_VERSION"
    else
        # Fallback based on Proxmox version
        PVE_MAJOR=$(echo $PVE_VERSION | cut -d'.' -f1)
        case $PVE_MAJOR in
            8) DEBIAN_VERSION="bookworm" ;;
            7) DEBIAN_VERSION="bullseye" ;;
            6) DEBIAN_VERSION="buster" ;;
            *) DEBIAN_VERSION="bookworm" ;;
        esac
        print_warning "Could not detect Debian version, using fallback: $DEBIAN_VERSION"
    fi
    
    # Add no-subscription repository
    print_info "Adding no-subscription repository..."
    if ! grep -q "pve-no-subscription" /etc/apt/sources.list; then
        echo "deb http://download.proxmox.com/debian/pve $DEBIAN_VERSION pve-no-subscription" >> /etc/apt/sources.list
        print_success "No-subscription repository added for $DEBIAN_VERSION"
    else
        print_warning "No-subscription repository already exists"
    fi
    
    # Add Debian security updates
    print_info "Ensuring Debian security repository is present..."
    if ! grep -q "security.debian.org" /etc/apt/sources.list; then
        echo "deb http://security.debian.org/debian-security $DEBIAN_VERSION-security main contrib" >> /etc/apt/sources.list
        print_success "Debian security repository added for $DEBIAN_VERSION"
    fi
    
    # Add non-free-firmware for newer Debian versions
    if [[ "$DEBIAN_VERSION" == "bookworm" ]]; then
        print_info "Adding non-free-firmware repository for Debian 12..."
        if ! grep -q "non-free-firmware" /etc/apt/sources.list; then
            sed -i 's/main contrib$/main contrib non-free-firmware/' /etc/apt/sources.list
            print_success "Non-free-firmware repository added"
        fi
    fi
}

# Update system packages
update_system() {
    print_header "UPDATING SYSTEM PACKAGES"
    
    print_info "Updating package lists..."
    apt update
    print_success "Package lists updated"
    
    print_info "Upgrading system packages..."
    apt full-upgrade -y
    print_success "System packages upgraded"
    
    print_info "Installing useful packages..."
    apt install -y \
        curl \
        wget \
        vim \
        htop \
        tree \
        unzip \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release
    print_success "Additional packages installed"
}

# Remove subscription nag
remove_subscription_nag() {
    print_header "REMOVING SUBSCRIPTION NAG"
    
    # Backup original file
    cp /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js.bak
    
    # Remove the subscription check
    sed -i.backup "s/data.status !== 'Active'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
    
    # Alternative method for different versions
    sed -i.backup "s/checked_command: function(orig_cmd) {/checked_command: function(orig_cmd) {\nreturn orig_cmd;/" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
    
    print_success "Subscription nag removed"
    print_warning "Note: Clear browser cache or use Ctrl+F5 to see changes"
}

# Disable high availability (for single node setups)
disable_ha() {
    print_header "CONFIGURING HIGH AVAILABILITY"
    
    read -p "Is this a single-node setup? Disable HA to save resources? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        systemctl stop pve-ha-lrm
        systemctl stop pve-ha-crm
        systemctl disable pve-ha-lrm
        systemctl disable pve-ha-crm
        print_success "High Availability services disabled"
    else
        print_info "High Availability services left enabled"
    fi
}

# Configure automatic updates (optional)
configure_auto_updates() {
    print_header "CONFIGURING AUTOMATIC UPDATES"
    
    read -p "Enable automatic security updates? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        apt install -y unattended-upgrades
        
        # Configure unattended-upgrades
        cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Origins-Pattern {
        "origin=Debian,codename=${distro_codename}-security";
        "origin=Proxmox";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
        
        # Enable automatic updates
        cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
        
        systemctl enable unattended-upgrades
        systemctl start unattended-upgrades
        print_success "Automatic security updates enabled"
    else
        print_info "Automatic updates not configured"
    fi
}

# Configure firewall
configure_firewall() {
    print_header "CONFIGURING FIREWALL"
    
    read -p "Configure basic firewall rules? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Install UFW if not present
        print_info "Installing UFW firewall..."
        apt install -y ufw
        
        # Reset UFW to defaults (clean slate)
        ufw --force reset
        
        # Set default policies
        ufw default deny incoming
        ufw default allow outgoing
        
        # Allow SSH (critical - don't lock yourself out!)
        ufw allow 22/tcp
        print_success "SSH access allowed (port 22)"
        
        # Allow Proxmox web interface
        ufw allow 8006/tcp
        print_success "Proxmox web interface allowed (port 8006)"
        
        # Allow VNC connections for VM consoles
        ufw allow 5900:5999/tcp
        print_success "VNC console access allowed (ports 5900-5999)"
        
        # Allow SPICE connections for VM consoles
        ufw allow 3128/tcp
        print_success "SPICE console access allowed (port 3128)"
        
        # Enable firewall
        ufw --force enable
        
        print_success "Firewall enabled and configured"
        print_info "Current firewall status:"
        ufw status numbered
        
        print_warning "Important firewall notes:"
        print_warning "- SSH (port 22) is allowed from anywhere"
        print_warning "- Proxmox web (port 8006) is allowed from anywhere"
        print_warning "- Consider restricting access to specific IP ranges later"
        
    else
        print_info "Firewall configuration skipped"
    fi
}

# Configure fail2ban for additional security
configure_fail2ban() {
    print_header "CONFIGURING FAIL2BAN"
    
    read -p "Install and configure Fail2Ban for SSH protection? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        apt install -y fail2ban
        
        # Create jail.local configuration
        cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3

[proxmox]
enabled = true
port = 8006
filter = proxmox
logpath = /var/log/daemon.log
maxretry = 3
bantime = 3600
EOF

        # Create Proxmox filter
        cat > /etc/fail2ban/filter.d/proxmox.conf << 'EOF'
[Definition]
failregex = pvedaemon\[.*authentication failure; rhost=<HOST> user=.* msg=.*
ignoreregex =
EOF
        
        systemctl enable fail2ban
        systemctl start fail2ban
        print_success "Fail2Ban configured and started"
    else
        print_info "Fail2Ban configuration skipped"
    fi
}

# Set timezone
configure_timezone() {
    print_header "CONFIGURING TIMEZONE"
    
    current_timezone=$(timedatectl show --property=Timezone --value)
    print_info "Current timezone: $current_timezone"
    
    read -p "Configure timezone? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Available timezones:"
        timedatectl list-timezones | head -20
        echo "... (and more)"
        
        read -p "Enter timezone (e.g., America/New_York): " timezone
        if timedatectl set-timezone "$timezone"; then
            print_success "Timezone set to: $timezone"
        else
            print_error "Failed to set timezone"
        fi
    else
        print_info "Timezone configuration skipped"
    fi
}

# Configure CPU scaling governor
configure_cpu_governor() {
    print_header "CONFIGURING CPU SCALING"
    
    current_governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "N/A")
    print_info "Current CPU governor: $current_governor"
    
    read -p "Set CPU governor to 'performance' for better VM performance? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        apt install -y cpufrequtils
        
        # Set governor to performance
        echo 'GOVERNOR="performance"' > /etc/default/cpufrequtils
        
        # Apply immediately
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            echo performance > "$cpu" 2>/dev/null || true
        done
        
        systemctl enable cpufrequtils
        print_success "CPU governor set to performance"
    else
        print_info "CPU governor configuration skipped"
    fi
}

# Clean up
cleanup_system() {
    print_header "CLEANING UP SYSTEM"
    
    print_info "Removing unnecessary packages..."
    apt autoremove -y
    apt autoclean
    
    print_info "Cleaning package cache..."
    apt clean
    
    print_success "System cleanup completed"
}

# Generate summary report
generate_report() {
    print_header "POST-INSTALLATION SUMMARY"
    
    echo "System Information:"
    echo "  - Hostname: $(hostname)"
    echo "  - IP Address: $(hostname -I | awk '{print $1}')"
    echo "  - Proxmox Version: $(pveversion)"
    echo "  - Kernel: $(uname -r)"
    echo "  - Uptime: $(uptime -p)"
    echo ""
    
    echo "Configuration Status:"
    echo "  - Enterprise repo: Disabled"
    echo "  - No-subscription repo: Enabled"
    echo "  - System: Updated"
    echo "  - Subscription nag: Removed"
    echo ""
    
    echo "Next Steps:"
    echo "  1. Access Proxmox web interface: https://$(hostname -I | awk '{print $1}'):8006"
    echo "  2. Clear browser cache (Ctrl+F5) to remove subscription dialog"
    echo "  3. Consider rebooting the system: 'reboot'"
    echo "  4. Review firewall settings if configured"
    echo "  5. Set up storage pools and networks as needed"
    echo ""
    
    echo "Log file location: $LOG_FILE"
}

# Prompt for reboot
prompt_reboot() {
    print_header "REBOOT RECOMMENDATION"
    
    print_warning "A reboot is recommended to ensure all changes take effect properly."
    read -p "Reboot now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "System will reboot in 10 seconds... Press Ctrl+C to cancel"
        sleep 10
        reboot
    else
        print_info "Remember to reboot when convenient"
    fi
}

# Main execution
main() {
    print_header "PROXMOX VE POST-INSTALLATION AUTOMATION"
    echo "Starting post-installation configuration..."
    echo "Log file: $LOG_FILE"
    echo ""
    
    check_root
    check_proxmox_version
    backup_configs
    configure_repositories
    update_system
    remove_subscription_nag
    disable_ha
    configure_auto_updates
    configure_firewall
    configure_fail2ban
    configure_timezone
    configure_cpu_governor
    cleanup_system
    generate_report
    prompt_reboot
    
    print_success "Post-installation automation completed successfully!"
}

# Run the script
main "$@"
