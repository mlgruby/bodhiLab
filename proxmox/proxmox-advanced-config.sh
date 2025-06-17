#!/bin/bash

#################################################
# Proxmox VE Advanced Configuration Script
#################################################
# This script handles advanced post-installation configurations
# Run this after the main post-installation script
#
# Usage: bash proxmox-advanced-config.sh
# Run as root
#################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LOG_FILE="/var/log/proxmox-advanced-config.log"
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

# Configure email notifications
configure_email() {
    print_header "CONFIGURING EMAIL NOTIFICATIONS"
    
    # Check if postfix is already installed and configured
    if systemctl is-active --quiet postfix 2>/dev/null; then
        print_success "Postfix already installed and running - skipping email configuration"
        print_info "Current postfix status:"
        systemctl status postfix --no-pager -l 2>/dev/null || echo "Status not available"
        return
    fi
    
    read -p "Configure email notifications? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Installing postfix and mailutils..."
        
        # Pre-configure postfix to avoid interactive prompts
        echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
        echo "postfix postfix/mailname string $(hostname -f)" | debconf-set-selections
        
        apt install -y postfix mailutils
        
        echo "Postfix configuration:"
        echo "1. Internet Site (for direct sending)"
        echo "2. Internet with smarthost (for relay through provider)"
        echo "3. Satellite system (relay through another server)"
        
        read -p "Select configuration type (1-3): " config_type
        
        case $config_type in
            1)
                postconf -e "relayhost = "
                print_success "Configured for direct email sending"
                ;;
            2)
                read -p "Enter SMTP relay server (e.g., smtp.gmail.com:587): " relay_host
                postconf -e "relayhost = [$relay_host]"
                
                # Configure SASL authentication
                print_info "Installing SASL authentication support..."
                apt install -y libsasl2-modules
                read -p "Enter SMTP username: " smtp_user
                read -s -p "Enter SMTP password: " smtp_pass
                echo
                
                echo "[$relay_host] $smtp_user:$smtp_pass" > /etc/postfix/sasl_passwd
                chmod 600 /etc/postfix/sasl_passwd
                postmap /etc/postfix/sasl_passwd
                
                postconf -e "smtp_sasl_auth_enable = yes"
                postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
                postconf -e "smtp_sasl_security_options = noanonymous"
                postconf -e "smtp_tls_security_level = encrypt"
                print_success "Configured for smarthost relay"
                ;;
            3)
                read -p "Enter satellite server: " satellite_server
                postconf -e "relayhost = [$satellite_server]"
                print_success "Configured for satellite system"
                ;;
        esac
        
        systemctl restart postfix
        systemctl enable postfix
        
        # Test email
        read -p "Enter email address to test (or press Enter to skip): " test_email
        if [[ -n "$test_email" ]]; then
            echo "Test email from Proxmox $(hostname) - $(date)" | mail -s "Proxmox Test Email" "$test_email"
            print_success "Test email sent to $test_email"
        fi
        
        print_success "Email notifications configured"
    else
        print_info "Email configuration skipped"
    fi
}

# Configure storage
configure_storage() {
    print_header "CONFIGURING ADDITIONAL STORAGE"
    
    # List available disks
    echo "Available disks:"
    lsblk -d -o NAME,SIZE,TYPE,MODEL | grep -v sr0 || true
    echo ""
    
    read -p "Configure additional storage? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Storage configuration options:"
        echo "1. LVM (Logical Volume Manager)"
        echo "2. ZFS (Z File System)"
        echo "3. Directory storage"
        
        read -p "Select storage type (1-3): " storage_type
        
        case $storage_type in
            1)
                configure_lvm_storage
                ;;
            2)
                configure_zfs_storage
                ;;
            3)
                configure_directory_storage
                ;;
        esac
    else
        print_info "Storage configuration skipped"
    fi
}

configure_lvm_storage() {
    print_info "Configuring LVM storage..."
    read -p "Enter disk device (e.g., /dev/sdb): " disk_device
    read -p "Enter volume group name: " vg_name
    
    # Validate disk device exists
    if [[ ! -b "$disk_device" ]]; then
        print_error "Device $disk_device not found or not a block device"
        return 1
    fi
    
    # Check if volume group already exists
    if vgdisplay "$vg_name" >/dev/null 2>&1; then
        print_warning "Volume group '$vg_name' already exists"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # Check if device is already in use
    if pvdisplay "$disk_device" >/dev/null 2>&1; then
        print_warning "Device $disk_device is already a physical volume"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    else
        print_info "Creating physical volume on $disk_device..."
        pvcreate "$disk_device" || {
            print_error "Failed to create physical volume"
            return 1
        }
    fi
    
    if ! vgdisplay "$vg_name" >/dev/null 2>&1; then
        print_info "Creating volume group $vg_name..."
        vgcreate "$vg_name" "$disk_device" || {
            print_error "Failed to create volume group"
            return 1
        }
    fi
    
    # Add to Proxmox storage
    print_info "Adding to Proxmox storage configuration..."
    if pvesm add lvm "$vg_name" --vgname "$vg_name" --content images,rootdir 2>/dev/null; then
        print_success "LVM storage '$vg_name' configured"
    else
        print_warning "LVM created but failed to add to Proxmox (may already exist)"
    fi
}

configure_zfs_storage() {
    print_info "Configuring ZFS storage..."
    read -p "Enter disk device (e.g., /dev/sdb): " disk_device
    read -p "Enter ZFS pool name: " pool_name
    
    # Validate disk device exists
    if [[ ! -b "$disk_device" ]]; then
        print_error "Device $disk_device not found or not a block device"
        return 1
    fi
    
    # Check if ZFS pool already exists
    if zpool list "$pool_name" >/dev/null 2>&1; then
        print_warning "ZFS pool '$pool_name' already exists"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    else
        print_info "Creating ZFS pool $pool_name on $disk_device..."
        if zpool create "$pool_name" "$disk_device"; then
            print_success "ZFS pool '$pool_name' created"
        else
            print_error "Failed to create ZFS pool"
            return 1
        fi
    fi
    
    # Add to Proxmox storage
    print_info "Adding to Proxmox storage configuration..."
    if pvesm add zfspool "$pool_name" --pool "$pool_name" --content images,rootdir 2>/dev/null; then
        print_success "ZFS storage '$pool_name' configured"
    else
        print_warning "ZFS pool created but failed to add to Proxmox (may already exist)"
    fi
}

configure_directory_storage() {
    read -p "Enter directory path: " dir_path
    read -p "Enter storage ID: " storage_id
    
    mkdir -p "$dir_path"
    
    # Add to Proxmox storage
    pvesm add dir "$storage_id" --path "$dir_path" --content images,iso,vztmpl,backup,rootdir
    
    print_success "Directory storage '$storage_id' configured at $dir_path"
}

# Configure networking
configure_networking() {
    print_header "CONFIGURING ADVANCED NETWORKING"
    
    read -p "Configure Open vSwitch (OVS)? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        apt install -y openvswitch-switch
        
        print_warning "OVS installation completed. Manual configuration required through web interface."
        print_info "Go to System -> Network to configure OVS bridges"
        
        print_success "Open vSwitch installed"
    else
        print_info "OVS configuration skipped"
    fi
}

# Configure backups
configure_backup() {
    print_header "CONFIGURING BACKUP SETTINGS"
    
    read -p "Configure backup storage? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Backup storage options:"
        echo "1. Local directory"
        echo "2. NFS share"
        echo "3. SMB/CIFS share"
        
        read -p "Select backup storage type (1-3): " backup_type
        
        case $backup_type in
            1)
                read -p "Enter backup directory path: " backup_path
                mkdir -p "$backup_path"
                pvesm add dir backup-local --path "$backup_path" --content backup
                print_success "Local backup storage configured at $backup_path"
                ;;
            2)
                configure_nfs_backup
                ;;
            3)
                configure_smb_backup
                ;;
        esac
        
        # Configure backup schedule
        read -p "Create a basic backup job? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Backup jobs should be configured through the web interface:"
            print_info "Datacenter -> Backup -> Add"
        fi
    else
        print_info "Backup configuration skipped"
    fi
}

configure_nfs_backup() {
    print_info "Configuring NFS backup storage..."
    read -p "Enter NFS server: " nfs_server
    read -p "Enter NFS export path: " nfs_path
    read -p "Enter storage ID: " storage_id
    
    # Install NFS client if not present
    if ! command -v mount.nfs >/dev/null 2>&1; then
        print_info "Installing NFS client..."
        apt install -y nfs-common
    else
        print_info "NFS client already installed"
    fi
    
    # Test NFS connection
    print_info "Testing NFS connection to $nfs_server:$nfs_path..."
    if timeout 10 showmount -e "$nfs_server" >/dev/null 2>&1; then
        print_success "NFS server is accessible"
    else
        print_warning "Cannot connect to NFS server or showmount failed"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # Add NFS storage
    print_info "Adding NFS storage to Proxmox..."
    if pvesm add nfs "$storage_id" --server "$nfs_server" --export "$nfs_path" --content backup 2>/dev/null; then
        print_success "NFS backup storage '$storage_id' configured"
    else
        print_error "Failed to add NFS storage (may already exist or connection failed)"
        return 1
    fi
}

configure_smb_backup() {
    print_info "Configuring SMB backup storage..."
    read -p "Enter SMB server: " smb_server
    read -p "Enter SMB share: " smb_share
    read -p "Enter SMB username: " smb_user
    read -s -p "Enter SMB password: " smb_pass
    echo
    read -p "Enter storage ID: " storage_id
    
    # Install SMB client if not present
    if ! command -v mount.cifs >/dev/null 2>&1; then
        print_info "Installing SMB client..."
        apt install -y cifs-utils
    else
        print_info "SMB client already installed"
    fi
    
    # Create credentials file
    cred_file="/etc/pve/priv/storage-${storage_id}.pw"
    print_info "Creating credentials file..."
    cat > "$cred_file" << EOF
username=$smb_user
password=$smb_pass
EOF
    chmod 600 "$cred_file"
    
    # Test SMB connection (optional, as it might require different syntax)
    print_info "Testing SMB connection..."
    if timeout 10 smbclient -L "$smb_server" -U "$smb_user%$smb_pass" >/dev/null 2>&1; then
        print_success "SMB server is accessible"
    else
        print_warning "Cannot test SMB connection (server may still work)"
    fi
    
    # Add SMB storage
    print_info "Adding SMB storage to Proxmox..."
    if pvesm add cifs "$storage_id" --server "$smb_server" --share "$smb_share" \
        --username "$smb_user" --password "$cred_file" \
        --content backup 2>/dev/null; then
        print_success "SMB backup storage '$storage_id' configured"
    else
        print_error "Failed to add SMB storage (may already exist or connection failed)"
        return 1
    fi
}

# Configure SSL certificates
configure_ssl() {
    print_header "CONFIGURING SSL CERTIFICATES"
    
    read -p "Configure custom SSL certificates? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "SSL certificate options:"
        echo "1. Let's Encrypt (ACME)"
        echo "2. Custom certificate files"
        
        read -p "Select option (1-2): " ssl_option
        
        case $ssl_option in
            1)
                configure_letsencrypt
                ;;
            2)
                configure_custom_ssl
                ;;
        esac
    else
        print_info "SSL configuration skipped"
    fi
}

configure_letsencrypt() {
    read -p "Enter domain name for certificate: " domain_name
    read -p "Enter email for Let's Encrypt: " le_email
    
    # This would typically be done through the Proxmox web interface
    print_warning "Let's Encrypt configuration:"
    print_info "1. Go to Datacenter -> ACME in web interface"
    print_info "2. Add Let's Encrypt account with email: $le_email"
    print_info "3. Add domain: $domain_name"
    print_info "4. Request certificate"
}

configure_custom_ssl() {
    read -p "Enter path to certificate file: " cert_file
    read -p "Enter path to private key file: " key_file
    
    if [[ -f "$cert_file" && -f "$key_file" ]]; then
        cp "$cert_file" /etc/pve/local/pve-ssl.pem
        cp "$key_file" /etc/pve/local/pve-ssl.key
        
        systemctl restart pveproxy
        
        print_success "Custom SSL certificate installed"
    else
        print_error "Certificate or key file not found"
    fi
}

# Configure monitoring
configure_monitoring() {
    print_header "CONFIGURING SYSTEM MONITORING"
    
    # Check if monitoring tools are already installed
    tools_installed=0
    monitoring_tools=("iotop" "iftop" "ncdu" "smartmontools" "lm-sensors")
    
    for tool in "${monitoring_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1 || dpkg -l | grep -q "^ii.*$tool" 2>/dev/null; then
            ((tools_installed++))
        fi
    done
    
    if [[ $tools_installed -eq ${#monitoring_tools[@]} ]]; then
        print_success "All monitoring tools already installed - skipping"
        return
    fi
    
    read -p "Install additional monitoring tools? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Install monitoring tools
        print_info "Installing monitoring tools..."
        apt install -y \
            iotop \
            iftop \
            ncdu \
            smartmontools \
            lm-sensors
        
        # Configure sensors
        print_info "Detecting hardware sensors..."
        sensors-detect --auto >/dev/null 2>&1 || print_warning "Sensor detection completed (some sensors may not be detected)"
        
        # Enable SMART monitoring
        if ! systemctl is-active --quiet smartd 2>/dev/null; then
            print_info "Enabling SMART monitoring..."
            systemctl enable smartd
            systemctl start smartd
        else
            print_info "SMART monitoring already active"
        fi
        
        print_success "Additional monitoring tools installed"
        print_info "Available tools: iotop, iftop, ncdu, sensors, smartctl"
        
        # Show quick sensor test
        if command -v sensors >/dev/null 2>&1; then
            print_info "Current sensor readings:"
            sensors 2>/dev/null | head -10 || print_info "No sensors detected or sensors not configured"
        fi
    else
        print_info "Monitoring tools installation skipped"
    fi
}

# Configure performance optimizations
configure_performance() {
    print_header "APPLYING PERFORMANCE OPTIMIZATIONS"
    
    read -p "Apply performance optimizations? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Kernel parameters for virtualization
        cat >> /etc/sysctl.conf << 'EOF'

# Proxmox performance optimizations
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_congestion_control = bbr
EOF
        
        # Apply immediately
        sysctl -p
        
        # Configure huge pages if system has enough RAM
        total_ram=$(free -m | awk '/^Mem:/{print $2}')
        if [[ $total_ram -gt 8192 ]]; then
            read -p "Configure huge pages for better performance? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                # Calculate 25% of RAM for huge pages
                hugepages=$((total_ram / 4 / 2))  # 2MB huge pages
                echo "vm.nr_hugepages = $hugepages" >> /etc/sysctl.conf
                sysctl -p
                print_success "Huge pages configured: $hugepages pages"
            fi
        fi
        
        print_success "Performance optimizations applied"
    else
        print_info "Performance optimization skipped"
    fi
}

# Main execution
main() {
    print_header "PROXMOX VE ADVANCED CONFIGURATION"
    echo "Starting advanced configuration..."
    echo "Log file: $LOG_FILE"
    echo ""
    
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
    
    configure_email
    configure_storage
    configure_networking
    configure_backup
    configure_ssl
    configure_monitoring
    configure_performance
    
    print_header "ADVANCED CONFIGURATION COMPLETED"
    print_success "All advanced configurations completed successfully!"
    print_info "Review the log file for details: $LOG_FILE"
    
    print_warning "Some configurations may require manual completion through the web interface"
}

# Run the script
main "$@"
