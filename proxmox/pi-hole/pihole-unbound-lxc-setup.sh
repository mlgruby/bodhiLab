#!/bin/bash

#################################################
# Pi-hole + Unbound LXC Container Setup Script
#################################################
# This script automates the creation and configuration of an LXC container 
# with Pi-hole and Unbound for DNS ad-blocking and privacy
#
# Usage: bash pihole-unbound-lxc-setup.sh
# Run as root on Proxmox VE host
#################################################

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
CONTAINER_ID="200"
CONTAINER_NAME="pihole-unbound"
CONTAINER_MEMORY="1024"
CONTAINER_DISK="8"
CONTAINER_CORES="2"
CONTAINER_PASSWORD="$(openssl rand -base64 12)"
CONTAINER_SSH_KEY=""
PIHOLE_WEBPASSWORD="$(openssl rand -base64 12)"

# Network configuration
CONTAINER_IP=""
CONTAINER_GATEWAY=""
CONTAINER_BRIDGE="vmbr0"
CONTAINER_STORAGE=""
TARGET_NODE=""

# Logging
LOG_FILE="/var/log/pihole-lxc-setup.log"
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

# Helper function to execute commands in container on correct node
pct_exec() {
    if [[ "$TARGET_NODE" == "$(hostname)" ]]; then
        pct exec $CONTAINER_ID -- "$@"
    else
        ssh root@$TARGET_NODE "pct exec $CONTAINER_ID -- $*"
    fi
}

# Helper function to push files to container on correct node
pct_push() {
    local source_file="$1"
    local dest_file="$2"
    
    if [[ "$TARGET_NODE" == "$(hostname)" ]]; then
        pct push $CONTAINER_ID "$source_file" "$dest_file"
    else
        # Copy file to remote node first, then push to container
        scp "$source_file" "root@$TARGET_NODE:/tmp/$(basename $source_file)"
        ssh root@$TARGET_NODE "pct push $CONTAINER_ID /tmp/$(basename $source_file) $dest_file && rm /tmp/$(basename $source_file)"
    fi
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Check if running on Proxmox
check_proxmox() {
    if ! command -v pct &> /dev/null; then
        print_error "This script must be run on a Proxmox VE host"
        exit 1
    fi
    print_success "Proxmox VE environment detected"
}

# Get user configuration
get_user_config() {
    print_header "CONFIGURATION SETUP"
    
    # Quick setup option
    echo ""
    print_info "🚀 QUICK SETUP OPTION:"
    print_info "   • Container ID: 200"
    print_info "   • Container IP: 192.168.1.100/24" 
    print_info "   • Gateway: 192.168.1.1"
    print_info "   • Node: Current node (auto-detected)"
    print_info "   • Template: Debian (auto-selected)"
    print_info "   • Storage: First available option"
    print_info "   • Memory: 1024MB, Disk: 8GB"
    echo ""
    read -p "Use quick setup with defaults above? (Y/n): " quick_setup
    
    if [[ "$quick_setup" =~ ^[Nn]$ ]]; then
        print_info "Proceeding with custom configuration..."
    else
        print_success "Using quick setup with defaults!"
        CONTAINER_IP="192.168.1.100/24"
        CONTAINER_GATEWAY="192.168.1.1"
        TARGET_NODE=$(hostname)  # Use current node
        USE_DEFAULTS="true"
        return 0
    fi
    echo ""
    
    # Container ID
    read -p "Enter Container ID (default: $CONTAINER_ID): " input_id
    CONTAINER_ID=${input_id:-$CONTAINER_ID}
    
    # Check if container ID already exists
    if pct list | grep -q "^$CONTAINER_ID"; then
        print_error "Container ID $CONTAINER_ID already exists"
        exit 1
    fi
    
    # Node Selection
    print_info "Available Proxmox nodes in cluster:"
    pvecm nodes 2>/dev/null | grep -E "^[[:space:]]*[0-9]+" | awk '{printf "%d. %s (Status: %s)\n", NR, $2, $3}' | tee /tmp/node_list.txt
    
    # Check if we have multiple nodes
    node_count=$(wc -l < /tmp/node_list.txt)
    current_node=$(hostname)
    
    if [[ $node_count -gt 1 ]]; then
        echo ""
        print_info "💡 Current node: $current_node"
        print_info "💡 Tip: Press Enter to use current node ($current_node)"
        
        while [[ -z "$TARGET_NODE" ]]; do
            read -p "Select node number from the list above (default: current node): " node_num
            
            if [[ -z "$node_num" ]]; then
                # Use current node as default
                TARGET_NODE=$current_node
                print_success "Using current node: $TARGET_NODE"
            elif [[ "$node_num" =~ ^[0-9]+$ ]]; then
                TARGET_NODE=$(sed -n "${node_num}p" /tmp/node_list.txt | awk '{print $2}')
                if [[ -n "$TARGET_NODE" ]]; then
                    print_success "Selected node: $TARGET_NODE"
                else
                    print_error "Invalid selection. Please choose a number from the list."
                    TARGET_NODE=""
                fi
            else
                print_error "Please enter a valid number or press Enter for current node."
            fi
        done
    else
        TARGET_NODE=$current_node
        print_success "Single node detected: $TARGET_NODE"
    fi
    
    rm -f /tmp/node_list.txt
    
    # Container IP
    DEFAULT_IP="192.168.1.100/24"
    while [[ -z "$CONTAINER_IP" ]]; do
        read -p "Enter Container IP address (default: $DEFAULT_IP): " input_ip
        CONTAINER_IP=${input_ip:-$DEFAULT_IP}
        if [[ ! $CONTAINER_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
            print_error "Invalid IP address format. Please use CIDR notation (e.g., 192.168.1.100/24)"
            CONTAINER_IP=""
        fi
    done
    
    # Container Gateway
    DEFAULT_GATEWAY="192.168.1.1"
    while [[ -z "$CONTAINER_GATEWAY" ]]; do
        read -p "Enter Gateway IP address (default: $DEFAULT_GATEWAY): " input_gateway
        CONTAINER_GATEWAY=${input_gateway:-$DEFAULT_GATEWAY}
        if [[ ! $CONTAINER_GATEWAY =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            print_error "Invalid gateway IP address format"
            CONTAINER_GATEWAY=""
        fi
    done
    
    # Storage Selection
    if [[ "$USE_DEFAULTS" == "true" ]]; then
        print_info "Using defaults - auto-selecting first available storage..."
        pvesm status | grep -E "(local|nvme|lvm)" | awk '{printf "%d. %s (Type: %s, Status: %s)\n", NR, $1, $2, $4}' > /tmp/storage_list.txt
        CONTAINER_STORAGE=$(head -1 /tmp/storage_list.txt | awk '{print $2}')
        print_success "Auto-selected storage: $CONTAINER_STORAGE"
        rm -f /tmp/storage_list.txt
    else
        print_info "Available storage options:"
        pvesm status | grep -E "(local|nvme|lvm)" | awk '{printf "%d. %s (Type: %s, Status: %s)\n", NR, $1, $2, $4}' | tee /tmp/storage_list.txt
    
    echo ""
    print_info "💡 Tip: Press Enter to select option 1 (first storage option)"
    while [[ -z "$CONTAINER_STORAGE" ]]; do
        read -p "Select storage number from the list above (default: 1): " storage_num
        storage_num=${storage_num:-1}  # Default to option 1
        if [[ "$storage_num" =~ ^[0-9]+$ ]]; then
            CONTAINER_STORAGE=$(sed -n "${storage_num}p" /tmp/storage_list.txt | awk '{print $2}')
            if [[ -n "$CONTAINER_STORAGE" ]]; then
                print_success "Selected storage: $CONTAINER_STORAGE"
            else
                print_error "Invalid selection. Please choose a number from the list."
                CONTAINER_STORAGE=""
            fi
        else
            print_error "Please enter a valid number."
        fi
    done
    rm -f /tmp/storage_list.txt
    fi
    
    # SSH Key (optional)
    read -p "Enter SSH public key path (optional, press Enter to skip): " ssh_key_path
    if [[ -n "$ssh_key_path" && -f "$ssh_key_path" ]]; then
        CONTAINER_SSH_KEY=$(cat "$ssh_key_path")
        print_success "SSH key loaded"
    fi
    
    # Memory
    read -p "Enter memory allocation in MB (default: $CONTAINER_MEMORY): " input_memory
    CONTAINER_MEMORY=${input_memory:-$CONTAINER_MEMORY}
    
    # Storage
    read -p "Enter disk size in GB (default: $CONTAINER_DISK): " input_disk
    CONTAINER_DISK=${input_disk:-$CONTAINER_DISK}
    
    print_success "Configuration completed"
    echo "Container ID: $CONTAINER_ID"
    echo "Target Node: $TARGET_NODE"
    echo "Container IP: $CONTAINER_IP"
    echo "Gateway: $CONTAINER_GATEWAY"
    echo "Storage: $CONTAINER_STORAGE"
    echo "Memory: ${CONTAINER_MEMORY}MB"
    echo "Disk: ${CONTAINER_DISK}GB"
    echo "Root Password: $CONTAINER_PASSWORD"
    echo "Pi-hole Web Password: $PIHOLE_WEBPASSWORD"
}

# Select and download container template
select_template() {
    print_header "CONTAINER TEMPLATE SELECTION"
    
    # Skip if using defaults
    if [[ "$USE_DEFAULTS" == "true" ]]; then
        print_info "Using defaults - auto-selecting Debian template..."
        
        # Get available templates
        pveam list local | grep -E "\.(tar\.xz|tar\.zst|tar\.gz)$" | awk '{print NR ". " $1 " (" $3 ")"}' > /tmp/template_list.txt
        
        # Try to find Debian template
        DEBIAN_LINE=$(grep -i "debian" /tmp/template_list.txt | head -1)
        if [[ -n "$DEBIAN_LINE" ]]; then
            TEMPLATE=$(echo "$DEBIAN_LINE" | awk '{print $2}' | sed 's/local:vztmpl\///')
            print_success "Auto-selected template: $TEMPLATE"
        else
            # Fallback to first template
            TEMPLATE=$(head -1 /tmp/template_list.txt | awk '{print $2}' | sed 's/local:vztmpl\///')
            print_warning "Debian not found, using first available: $TEMPLATE"
        fi
        
        rm -f /tmp/template_list.txt
        return 0
    fi
    
    # Check available templates
    print_info "Available container templates:"
    
    # Get available templates and format them
    pveam list local | grep -E "\.(tar\.xz|tar\.zst|tar\.gz)$" | awk '{print NR ". " $1 " (" $3 ")"}' | tee /tmp/template_list.txt
    
    # Check if any templates are available
    if [[ ! -s /tmp/template_list.txt ]]; then
        print_warning "No templates found locally. Downloading recommended template..."
        print_info "Downloading Debian 12 template (recommended for Pi-hole)..."
        pveam download local debian-12-standard
        pveam list local | grep "debian-12-standard" | awk '{print "1. " $1 " (" $3 ")"}' > /tmp/template_list.txt
    fi
    
    echo ""
    print_info "Recommended: Choose Debian-based template for best Pi-hole compatibility"
    print_info "💡 Tip: Press Enter to auto-select Debian template (recommended)"
    echo ""
    
    # Template selection
    while [[ -z "$TEMPLATE" ]]; do
        # Try to find Debian template as default
        DEFAULT_TEMPLATE_NUM=$(grep -n "debian" /tmp/template_list.txt | head -1 | cut -d: -f1)
        if [[ -z "$DEFAULT_TEMPLATE_NUM" ]]; then
            DEFAULT_TEMPLATE_NUM=1  # Fallback to first option
        fi
        
        read -p "Select template number from the list above (default: $DEFAULT_TEMPLATE_NUM - Debian recommended): " template_num
        template_num=${template_num:-$DEFAULT_TEMPLATE_NUM}
        
        if [[ "$template_num" =~ ^[0-9]+$ ]]; then
            TEMPLATE_FULL=$(sed -n "${template_num}p" /tmp/template_list.txt | awk '{print $2}')
            if [[ -n "$TEMPLATE_FULL" ]]; then
                TEMPLATE=$(echo "$TEMPLATE_FULL" | sed 's/local:vztmpl\///')
                print_success "Selected template: $TEMPLATE"
                
                # Validate template compatibility
                if echo "$TEMPLATE" | grep -qE "(alpine|busybox)"; then
                    print_warning "Alpine/BusyBox templates may require additional configuration for Pi-hole"
                    read -p "Are you sure you want to continue with this template? (y/N): " confirm
                    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                        TEMPLATE=""
                        continue
                    fi
                fi
            else
                print_error "Invalid selection. Please choose a number from the list."
                TEMPLATE=""
            fi
        else
            print_error "Please enter a valid number."
        fi
    done
    
    rm -f /tmp/template_list.txt
    print_success "Template selection completed: $TEMPLATE"
}

# Create LXC container
create_container() {
    print_header "CREATING LXC CONTAINER"
    
    print_info "Creating container with ID $CONTAINER_ID on node $TARGET_NODE..."
    
    # Create container command
    if [[ "$TARGET_NODE" == "$(hostname)" ]]; then
        # Creating on current node
        create_cmd="pct create $CONTAINER_ID local:vztmpl/${TEMPLATE} \
            --hostname $CONTAINER_NAME \
            --memory $CONTAINER_MEMORY \
            --rootfs $CONTAINER_STORAGE:$CONTAINER_DISK \
            --cores $CONTAINER_CORES \
            --net0 name=eth0,bridge=$CONTAINER_BRIDGE,ip=$CONTAINER_IP,gw=$CONTAINER_GATEWAY \
            --onboot 1 \
            --unprivileged 1 \
            --features nesting=1 \
            --password $CONTAINER_PASSWORD"
    else
        # Creating on remote node
        create_cmd="ssh root@$TARGET_NODE 'pct create $CONTAINER_ID local:vztmpl/${TEMPLATE} \
            --hostname $CONTAINER_NAME \
            --memory $CONTAINER_MEMORY \
            --rootfs $CONTAINER_STORAGE:$CONTAINER_DISK \
            --cores $CONTAINER_CORES \
            --net0 name=eth0,bridge=$CONTAINER_BRIDGE,ip=$CONTAINER_IP,gw=$CONTAINER_GATEWAY \
            --onboot 1 \
            --unprivileged 1 \
            --features nesting=1 \
            --password $CONTAINER_PASSWORD'"
    fi
    
    # Add SSH key if provided
    if [[ -n "$CONTAINER_SSH_KEY" ]]; then
        create_cmd="$create_cmd --ssh-public-keys <(echo '$CONTAINER_SSH_KEY')"
    fi
    
    eval $create_cmd
    print_success "Container $CONTAINER_ID created successfully"
    
    # Start container
    print_info "Starting container..."
    if [[ "$TARGET_NODE" == "$(hostname)" ]]; then
        pct start $CONTAINER_ID
    else
        ssh root@$TARGET_NODE "pct start $CONTAINER_ID"
    fi
    sleep 10
    print_success "Container started"
}

# Configure container for Pi-hole and Unbound
configure_container() {
    print_header "CONFIGURING CONTAINER"
    
    # Detect container OS type
    if echo "$TEMPLATE" | grep -q "alpine"; then
        print_info "Detected Alpine Linux - configuring for Alpine..."
        
        print_info "Updating Alpine packages..."
        pct_exec apk update && pct_exec apk upgrade
        
        print_info "Installing required packages for Alpine..."
        pct_exec apk add curl wget sudo unzip bind-tools net-tools bash
        
        # Install systemd-compatible init for Pi-hole
        pct_exec apk add openrc
        pct_exec rc-update add local default
        
        print_warning "Alpine detected: Pi-hole may require additional manual configuration"
    else
        print_info "Detected Debian/Ubuntu - using standard configuration..."
        
        print_info "Updating container packages..."
        pct_exec bash -c "apt update && apt upgrade -y"
        
        print_info "Installing required packages..."
        pct_exec bash -c "apt install -y curl wget sudo unzip dnsutils net-tools"
    fi
    
    print_success "Container base configuration completed"
}

# Install Unbound
install_unbound() {
    print_header "INSTALLING UNBOUND"
    
    print_info "Installing Unbound DNS resolver..."
    pct_exec bash -c "apt install -y unbound"
    
    print_info "Configuring Unbound..."
    
    # Create Unbound configuration
    cat > /tmp/unbound.conf << 'EOF'
server:
    # If no logfile is specified, syslog is used
    # logfile: "/var/log/unbound/unbound.log"
    verbosity: 0

    interface: 127.0.0.1
    port: 5335
    do-ip4: yes
    do-udp: yes
    do-tcp: yes

    # May be set to yes if you have IPv6 connectivity
    do-ip6: no

    # You want to leave this to no unless you have *native* IPv6. With 6to4 and
    # Terredo tunnels your web browser should favor IPv4 for the same reasons
    prefer-ip6: no

    # Use this only when you downloaded the list of primary root servers!
    # If you use the default dns-root-data package, unbound will find it automatically
    #root-hints: "/var/lib/unbound/root.hints"

    # Trust glue only if it is within the server's authority
    harden-glue: yes

    # Require DNSSEC data for trust-anchored zones, if such data is absent, the zone becomes BOGUS
    harden-dnssec-stripped: yes

    # Don't use Capitalization randomization as it known to cause DNSSEC issues sometimes
    # see https://discourse.pi-hole.net/t/unbound-stubby-or-dns-over-https-upstream-dns-server/9378 for further details
    use-caps-for-id: no

    # Reduce EDNS reassembly buffer size.
    # IP fragmentation is unreliable on the Internet today, and can cause
    # transmission failures when large DNS messages are sent via UDP. Even
    # when fragmentation does work, it may not be secure; it is theoretically
    # possible to spoof parts of a fragmented DNS message, without easy
    # detection at the receiving end. Recently, there was an excellent study
    # >>> Defragmenting DNS - Determining the optimal maximum UDP response size for DNS <<<
    # by Axel Koolhaas, and Tjeerd Slokker (https://indico.dns-oarc.net/event/36/contributions/776/)
    # in collaboration with NLnet Labs explored DNS using real world data from the
    # the RIPE Atlas probes and the researchers suggested different values for
    # IPv4 and IPv6 and in different scenarios. They advise that servers should
    # be configured to limit DNS messages sent over UDP to a size that will not
    # trigger fragmentation on typical network links. DNS servers can switch
    # from UDP to TCP when a DNS response is too big to fit in this limited
    # buffer size. This value has also been suggested in DNS Flag Day 2020.
    edns-buffer-size: 1232

    # Perform prefetching of close to expired message cache entries
    # This only applies to domains that have been frequently queried
    prefetch: yes

    # One thread should be sufficient, can be increased on beefy machines. In reality for most users running on small networks or on a single machine, it should be unnecessary to seek performance enhancement by increasing num-threads above 1.
    num-threads: 1

    # Ensure kernel buffer is large enough to not lose messages in traffic spikes
    so-rcvbuf: 1m

    # Ensure privacy of local IP ranges
    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: 172.16.0.0/12
    private-address: 10.0.0.0/8
    private-address: fd00::/8
    private-address: fe80::/10
EOF

    # Copy configuration to container
    pct_push /tmp/unbound.conf /etc/unbound/unbound.conf.d/pi-hole.conf
    
    # Start and enable Unbound
    pct_exec bash -c "systemctl enable unbound && systemctl start unbound"
    
    # Clean up
    rm /tmp/unbound.conf
    
    print_success "Unbound installed and configured"
}

# Install Pi-hole
install_pihole() {
    print_header "INSTALLING PI-HOLE"
    
    print_info "Creating Pi-hole configuration..."
    
    # Create setupVars.conf for automated installation
    cat > /tmp/setupVars.conf << EOF
PIHOLE_INTERFACE=eth0
IPV4_ADDRESS=$CONTAINER_IP
IPV6_ADDRESS=
QUERY_LOGGING=true
INSTALL_WEB_SERVER=true
INSTALL_WEB_INTERFACE=true
LIGHTTPD_ENABLED=true
CACHE_SIZE=10000
DNS_FQDN_REQUIRED=true
DNS_BOGUS_PRIV=true
DNSMASQ_LISTENING=single
PIHOLE_DNS_1=127.0.0.1#5335
PIHOLE_DNS_2=
BLOCKING_ENABLED=true
WEBPASSWORD=$PIHOLE_WEBPASSWORD
EOF

    # Copy configuration to container
    pct_push /tmp/setupVars.conf /etc/pihole/setupVars.conf
    
    print_info "Installing Pi-hole..."
    pct_exec bash -c "curl -sSL https://install.pi-hole.net | bash /dev/stdin --unattended"
    
    # Clean up
    rm /tmp/setupVars.conf
    
    print_success "Pi-hole installed successfully"
}

# Configure firewall
configure_firewall() {
    print_header "CONFIGURING FIREWALL"
    
    print_info "Installing and configuring UFW firewall..."
    
    pct_exec bash -c "
        apt install -y ufw
        ufw --force enable
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow ssh
        ufw allow 53/tcp
        ufw allow 53/udp
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw --force enable
    "
    
    print_success "Firewall configured"
}

# Final configuration and testing
finalize_setup() {
    print_header "FINALIZING SETUP"
    
    print_info "Testing DNS resolution..."
    
    # Test Unbound
    if pct_exec bash -c "dig @127.0.0.1 -p 5335 google.com +short" > /dev/null 2>&1; then
        print_success "Unbound DNS resolution test passed"
    else
        print_warning "Unbound DNS resolution test failed"
    fi
    
    # Test Pi-hole
    if pct_exec bash -c "dig @127.0.0.1 google.com +short" > /dev/null 2>&1; then
        print_success "Pi-hole DNS resolution test passed"
    else
        print_warning "Pi-hole DNS resolution test failed"
    fi
    
    # Create status script
    cat > /tmp/pihole-status.sh << 'EOF'
#!/bin/bash
echo "=== Pi-hole + Unbound Status ==="
echo "Container IP: $(hostname -I | awk '{print $1}')"
echo "Pi-hole Status: $(systemctl is-active pihole-FTL)"
echo "Unbound Status: $(systemctl is-active unbound)"
echo "DNS Test: $(dig @127.0.0.1 google.com +short | head -1)"
echo "Web Interface: http://$(hostname -I | awk '{print $1}')/admin"
EOF
    
    pct_push /tmp/pihole-status.sh /usr/local/bin/pihole-status.sh
    pct_exec bash -c "chmod +x /usr/local/bin/pihole-status.sh"
    
    rm /tmp/pihole-status.sh
    
    print_success "Setup finalized"
}

# Main execution
main() {
    print_header "PI-HOLE + UNBOUND LXC CONTAINER SETUP"
    
    check_root
    check_proxmox
    get_user_config
    select_template
    create_container
    configure_container
    install_unbound
    install_pihole
    configure_firewall
    finalize_setup
    
    print_header "SETUP COMPLETED SUCCESSFULLY"
    print_success "Container ID: $CONTAINER_ID"
    print_success "Container IP: $CONTAINER_IP"
    print_success "Pi-hole Web Interface: http://${CONTAINER_IP%/*}/admin"
    print_success "Pi-hole Web Password: $PIHOLE_WEBPASSWORD"
    print_success "Container Root Password: $CONTAINER_PASSWORD"
    
    print_info "To check status, run: pct exec $CONTAINER_ID -- pihole-status.sh"
    print_info "To access container: pct enter $CONTAINER_ID"
    
    print_warning "Don't forget to:"
    print_warning "1. Update your router's DNS settings to point to $CONTAINER_IP"
    print_warning "2. Or configure individual devices to use $CONTAINER_IP as DNS server"
    print_warning "3. Access the Pi-hole admin interface to customize blocklists"
    
    echo "Installation log saved to: $LOG_FILE"
}

# Run main function
main "$@" 
