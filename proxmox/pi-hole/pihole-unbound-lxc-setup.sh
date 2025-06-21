#!/bin/bash

#################################################
# Pi-hole + Unbound LXC Container Setup Script
# Multi-Node Installation Support
#################################################
# This script automates the creation and configuration of LXC containers 
# with Pi-hole and Unbound for DNS ad-blocking and privacy
# Supports installation on multiple Proxmox nodes for redundancy
#
# Usage: bash pihole-unbound-lxc-setup.sh
# Run as root on Proxmox VE host
#################################################

set -e  # Exit on any error

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables (with defaults from config file)
BASE_CONTAINER_ID="${DEFAULT_CONTAINER_ID:-200}"
CONTAINER_NAME="${DEFAULT_CONTAINER_NAME:-pihole-unbound}"
CONTAINER_MEMORY="${DEFAULT_CONTAINER_MEMORY:-1024}"
CONTAINER_DISK="${DEFAULT_CONTAINER_DISK:-8}"
CONTAINER_CORES="${DEFAULT_CONTAINER_CORES:-2}"
CONTAINER_PASSWORD="$(openssl rand -base64 12)"
CONTAINER_SSH_KEY=""
PIHOLE_WEBPASSWORD="$(openssl rand -base64 12)"

# Network configuration
BASE_CONTAINER_IP="${DEFAULT_CONTAINER_IP:-192.168.1.100}"
CONTAINER_GATEWAY="${DEFAULT_GATEWAY:-192.168.1.1}"
CONTAINER_BRIDGE="${DEFAULT_CONTAINER_BRIDGE:-vmbr0}"
CONTAINER_STORAGE=""

# Multi-node variables
declare -a SELECTED_NODES=()
declare -a INSTALLATION_RESULTS=()

# Logging
LOG_FILE="/var/log/pihole-lxc-multinode-setup.log"
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

# Load configuration files
load_config() {
    if [[ -f "$CONFIG_DIR/setup.conf" ]]; then
        source "$CONFIG_DIR/setup.conf"
        print_info "Loaded main configuration from $CONFIG_DIR/setup.conf"
    else
        print_warning "Main configuration file not found, using defaults"
    fi
}

# Helper function to execute commands in container on correct node
pct_exec() {
    local target_node="$1"
    local container_id="$2"
    shift 2
    
    if [[ "$target_node" == "$(hostname)" ]]; then
        pct exec $container_id -- "$@"
    else
        ssh root@$target_node "pct exec $container_id -- $*"
    fi
}

# Helper function to push files to container on correct node
pct_push() {
    local target_node="$1"
    local container_id="$2"
    local source_file="$3"
    local dest_file="$4"
    
    if [[ "$target_node" == "$(hostname)" ]]; then
        pct push $container_id "$source_file" "$dest_file"
    else
        # Copy file to remote node first, then push to container
        scp "$source_file" "root@$target_node:/tmp/$(basename $source_file)"
        ssh root@$target_node "pct push $container_id /tmp/$(basename $source_file) $dest_file && rm /tmp/$(basename $source_file)"
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

# Multi-node selection function
select_target_nodes() {
    print_header "MULTI-NODE SELECTION"
    
    # Get available nodes
    print_info "Scanning Proxmox cluster for available nodes..."
    pvecm nodes 2>/dev/null | grep -E "^[[:space:]]*[0-9]+" | awk '{printf "%d. %s (Status: %s)\n", NR, $2, $3}' | tee /tmp/node_list.txt
    
    local node_count=$(wc -l < /tmp/node_list.txt)
    local current_node=$(hostname)
    
    if [[ $node_count -eq 0 ]]; then
        print_error "No cluster nodes found. Ensure this is a Proxmox cluster."
        exit 1
    elif [[ $node_count -eq 1 ]]; then
        local single_node=$(awk '{print $2}' /tmp/node_list.txt)
        print_info "Single node cluster detected: $single_node"
        SELECTED_NODES=("$single_node")
        rm -f /tmp/node_list.txt
        return 0
    fi
    
    echo ""
    print_info "💡 Current node: $current_node"
    print_info "🚀 MULTI-NODE INSTALLATION OPTIONS:"
    echo "   A. Install on ALL nodes (recommended for full redundancy)"
    echo "   B. Select specific nodes"
    echo "   C. Quick install on current node only"
    echo ""
    
    while [[ ${#SELECTED_NODES[@]} -eq 0 ]]; do
        read -p "Choose installation option (A/B/C): " selection
        
        case $selection in
            [Aa]*)
                # Install on all nodes
                while IFS= read -r line; do
                    local node_name=$(echo "$line" | awk '{print $2}')
                    SELECTED_NODES+=("$node_name")
                done < /tmp/node_list.txt
                print_success "Selected ALL nodes for installation: ${SELECTED_NODES[*]}"
                ;;
            [Bb]*)
                # Select specific nodes
                print_info "Select nodes by entering their numbers separated by spaces (e.g., 1 3 for nodes 1 and 3)"
                print_info "Available nodes:"
                cat /tmp/node_list.txt
                echo ""
                
                while [[ ${#SELECTED_NODES[@]} -eq 0 ]]; do
                    read -p "Enter node numbers (space-separated): " -a node_numbers
                    
                    for num in "${node_numbers[@]}"; do
                        if [[ "$num" =~ ^[0-9]+$ ]]; then
                            local node_name=$(sed -n "${num}p" /tmp/node_list.txt | awk '{print $2}')
                            if [[ -n "$node_name" ]]; then
                                SELECTED_NODES+=("$node_name")
                            else
                                print_error "Invalid node number: $num"
                                SELECTED_NODES=()
                                break
                            fi
                        else
                            print_error "Invalid input: $num (must be a number)"
                            SELECTED_NODES=()
                            break
                        fi
                    done
                    
                    if [[ ${#SELECTED_NODES[@]} -gt 0 ]]; then
                        # Remove duplicates
                        local unique_nodes=($(printf '%s\n' "${SELECTED_NODES[@]}" | sort -u))
                        SELECTED_NODES=("${unique_nodes[@]}")
                        print_success "Selected nodes: ${SELECTED_NODES[*]}"
                    fi
                done
                ;;
            [Cc]*)
                # Quick install on current node
                SELECTED_NODES=("$current_node")
                print_success "Selected current node only: $current_node"
                ;;
            *)
                print_error "Invalid selection. Please choose A, B, or C."
                ;;
        esac
    done
    
    rm -f /tmp/node_list.txt
    
    print_info "Final selection: Installing Pi-hole on ${#SELECTED_NODES[@]} node(s)"
    for i in "${!SELECTED_NODES[@]}"; do
        print_info "  Node $((i+1)): ${SELECTED_NODES[i]}"
    done
}

# Get user configuration for multi-node setup
get_user_config() {
    print_header "CONFIGURATION SETUP"
    
    # Quick setup option
    echo ""
    print_info "🚀 QUICK SETUP OPTION:"
    print_info "   • Base Container ID: $BASE_CONTAINER_ID (will increment for each node)"
    print_info "   • Base Container IP: $BASE_CONTAINER_IP (will increment for each node)"
    print_info "   • Gateway: $CONTAINER_GATEWAY"
    print_info "   • Template: Debian (auto-selected)"
    print_info "   • Storage: First available option"
    print_info "   • Memory: ${CONTAINER_MEMORY}MB, Disk: ${CONTAINER_DISK}GB"
    echo ""
    read -p "Use quick setup with defaults above? (Y/n): " quick_setup
    
    if [[ "$quick_setup" =~ ^[Nn]$ ]]; then
        print_info "Proceeding with custom configuration..."
        
        # Base Container ID
        read -p "Enter base Container ID (will increment for each node) (default: $BASE_CONTAINER_ID): " input_id
        BASE_CONTAINER_ID=${input_id:-$BASE_CONTAINER_ID}
        
        # Base Container IP
        while [[ -z "$validated_ip" ]]; do
            read -p "Enter base Container IP (will increment for each node) (default: $BASE_CONTAINER_IP): " input_ip
            BASE_CONTAINER_IP=${input_ip:-$BASE_CONTAINER_IP}
            if [[ $BASE_CONTAINER_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                validated_ip="true"
            else
                print_error "Invalid IP address format"
                BASE_CONTAINER_IP=""
            fi
        done
        
        # Container Gateway
        while [[ -z "$validated_gateway" ]]; do
            read -p "Enter Gateway IP address (default: $CONTAINER_GATEWAY): " input_gateway
            CONTAINER_GATEWAY=${input_gateway:-$CONTAINER_GATEWAY}
            if [[ $CONTAINER_GATEWAY =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                validated_gateway="true"
            else
                print_error "Invalid gateway IP address format"
                CONTAINER_GATEWAY=""
            fi
        done
        
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
    else
        print_success "Using quick setup with defaults!"
        USE_DEFAULTS="true"
    fi
    
    print_success "Configuration completed"
    echo "Base Container ID: $BASE_CONTAINER_ID"
    echo "Base Container IP: $BASE_CONTAINER_IP"
    echo "Gateway: $CONTAINER_GATEWAY"
    echo "Memory: ${CONTAINER_MEMORY}MB"
    echo "Disk: ${CONTAINER_DISK}GB"
    echo "Nodes to install: ${#SELECTED_NODES[@]}"
}

# Select and download container template
select_template() {
    print_header "CONTAINER TEMPLATE SELECTION"
    
    # Skip if using defaults
    if [[ "$USE_DEFAULTS" == "true" ]]; then
        print_info "Using defaults - auto-selecting template..."
        
        # Get available templates
        pveam list local | grep -v "^NAME" | grep -E "tar\.(xz|zst|gz)" | awk '{print NR ". " $1 " (" $2 ")"}' > /tmp/template_list.txt
        
        # Check if any templates are available
        if [[ ! -s /tmp/template_list.txt ]]; then
            print_error "No templates available locally. Please download a template first:"
            print_error "  pveam available | grep debian"
            print_error "  pveam download local <template-name>"
            rm -f /tmp/template_list.txt
            exit 1
        fi
        
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
    print_info "Checking for templates..."
    pveam list local | grep -v "^NAME" | grep -E "tar\.(xz|zst|gz)" | awk '{print NR ". " $1 " (" $2 ")"}' | tee /tmp/template_list.txt
    
    # Debug output
    echo "Template list contents:"
    cat /tmp/template_list.txt
    
    # Check if any templates are available
    if [[ ! -s /tmp/template_list.txt ]]; then
        print_warning "No templates found locally."
        print_info "Available templates for download:"
        
        # Show available templates for download
        pveam available | grep -E "(debian|ubuntu)" | head -5
        
        print_error "Please download a template first using:"
        print_error "  pveam available | grep debian"
        print_error "  pveam download local <template-name>"
        print_error ""
        print_error "Example: pveam download local debian-12-standard_12.7-1_amd64.tar.zst"
        exit 1
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
        pct_exec "$TARGET_NODE" "$CONTAINER_ID" apk update && pct_exec "$TARGET_NODE" "$CONTAINER_ID" apk upgrade
        
        print_info "Installing required packages for Alpine..."
        pct_exec "$TARGET_NODE" "$CONTAINER_ID" apk add curl wget sudo unzip bind-tools net-tools bash
        
        # Install systemd-compatible init for Pi-hole
        pct_exec "$TARGET_NODE" "$CONTAINER_ID" apk add openrc
        pct_exec "$TARGET_NODE" "$CONTAINER_ID" rc-update add local default
        
        print_warning "Alpine detected: Pi-hole may require additional manual configuration"
    else
        print_info "Detected Debian/Ubuntu - using standard configuration..."
        
        print_info "Updating container packages..."
        pct_exec "$TARGET_NODE" "$CONTAINER_ID" bash -c "apt update && apt upgrade -y"
        
        print_info "Installing required packages..."
        pct_exec "$TARGET_NODE" "$CONTAINER_ID" bash -c "apt install -y curl wget sudo unzip dnsutils net-tools"
    fi
    
    print_success "Container base configuration completed"
}

# Install Unbound
install_unbound() {
    print_header "INSTALLING UNBOUND"
    
    print_info "Installing Unbound DNS resolver..."
    pct_exec "$TARGET_NODE" "$CONTAINER_ID" bash -c "apt install -y unbound"
    
    print_info "Configuring Unbound..."
    
    # Use external Unbound configuration file
    if [[ -f "$CONFIG_DIR/unbound.conf" ]]; then
        print_success "Using Unbound configuration from $CONFIG_DIR/unbound.conf"
        cp "$CONFIG_DIR/unbound.conf" /tmp/unbound.conf
    else
        print_warning "External Unbound config not found, using built-in configuration"
        # Fallback to simple built-in configuration
        cat > /tmp/unbound.conf << 'EOF'
server:
    verbosity: 1
    interface: 127.0.0.1
    port: 5335
    do-ip4: yes
    do-udp: yes
    do-tcp: yes
    do-ip6: no
    prefer-ip6: no
    harden-glue: yes
    harden-dnssec-stripped: yes
    use-caps-for-id: no
    edns-buffer-size: 1232
    prefetch: yes
    num-threads: 1
    so-rcvbuf: 1m
    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: 172.16.0.0/12
    private-address: 10.0.0.0/8
    private-address: fd00::/8
    private-address: fe80::/10
EOF
    fi

    # Copy configuration to container
    pct_push "$TARGET_NODE" "$CONTAINER_ID" /tmp/unbound.conf /etc/unbound/unbound.conf.d/pi-hole.conf
    
    # Start and enable Unbound
    pct_exec "$TARGET_NODE" "$CONTAINER_ID" bash -c "systemctl enable unbound && systemctl start unbound"
    
    # Clean up
    rm /tmp/unbound.conf
    
    print_success "Unbound installed and configured"
}

# Install Pi-hole
install_pihole() {
    print_header "INSTALLING PI-HOLE"
    
    print_info "Creating Pi-hole configuration..."
    
    # Load Pi-hole configuration from external file
    if [[ -f "$CONFIG_DIR/pihole.conf" ]]; then
        print_success "Loading Pi-hole configuration from $CONFIG_DIR/pihole.conf"
        source "$CONFIG_DIR/pihole.conf"
    else
        print_warning "External Pi-hole config not found, using defaults"
        # Set default values
        PIHOLE_INTERFACE="eth0"
        PIHOLE_IPV6_ADDRESS=""
        PIHOLE_QUERY_LOGGING="true"
        PIHOLE_INSTALL_WEB_SERVER="true"
        PIHOLE_INSTALL_WEB_INTERFACE="true"
        PIHOLE_LIGHTTPD_ENABLED="true"
        PIHOLE_CACHE_SIZE="10000"
        PIHOLE_DNS_FQDN_REQUIRED="true"
        PIHOLE_DNS_BOGUS_PRIV="true"
        PIHOLE_DNSMASQ_LISTENING="single"
        PIHOLE_DNS_1="127.0.0.1#5335"
        PIHOLE_DNS_2=""
        PIHOLE_BLOCKING_ENABLED="true"
    fi
    
    # Create setupVars.conf for automated installation
    cat > /tmp/setupVars.conf << EOF
PIHOLE_INTERFACE=$PIHOLE_INTERFACE
IPV4_ADDRESS=$CONTAINER_IP
IPV6_ADDRESS=$PIHOLE_IPV6_ADDRESS
QUERY_LOGGING=$PIHOLE_QUERY_LOGGING
INSTALL_WEB_SERVER=$PIHOLE_INSTALL_WEB_SERVER
INSTALL_WEB_INTERFACE=$PIHOLE_INSTALL_WEB_INTERFACE
LIGHTTPD_ENABLED=$PIHOLE_LIGHTTPD_ENABLED
CACHE_SIZE=$PIHOLE_CACHE_SIZE
DNS_FQDN_REQUIRED=$PIHOLE_DNS_FQDN_REQUIRED
DNS_BOGUS_PRIV=$PIHOLE_DNS_BOGUS_PRIV
DNSMASQ_LISTENING=$PIHOLE_DNSMASQ_LISTENING
PIHOLE_DNS_1=$PIHOLE_DNS_1
PIHOLE_DNS_2=$PIHOLE_DNS_2
BLOCKING_ENABLED=$PIHOLE_BLOCKING_ENABLED
WEBPASSWORD=$PIHOLE_WEBPASSWORD
EOF

    # Copy configuration to container
    pct_push "$TARGET_NODE" "$CONTAINER_ID" /tmp/setupVars.conf /etc/pihole/setupVars.conf
    
    print_info "Installing Pi-hole..."
    
    # Test internet connectivity before attempting download
    if ! pct_exec "$TARGET_NODE" "$CONTAINER_ID" timeout 30 curl -s --connect-timeout 10 https://install.pi-hole.net >/dev/null 2>&1; then
        print_error "❌ Cannot reach Pi-hole installation server"
        print_warning "This usually indicates network connectivity issues"
        rm /tmp/setupVars.conf
        return 1
    fi
    
    # Attempt Pi-hole installation with timeout
    if pct_exec "$TARGET_NODE" "$CONTAINER_ID" timeout 600 bash -c "curl -sSL https://install.pi-hole.net | bash /dev/stdin --unattended"; then
        print_success "✓ Pi-hole installed successfully"
    else
        print_error "❌ Pi-hole installation failed"
        print_warning "Check container internet connectivity and try manual installation"
        rm /tmp/setupVars.conf
        return 1
    fi
    
    # Verify Pi-hole services are running
    sleep 5
    if pct_exec "$TARGET_NODE" "$CONTAINER_ID" systemctl is-active --quiet pihole-FTL; then
        print_success "✓ Pi-hole service is running"
    else
        print_warning "⚠ Pi-hole service may not be running properly"
    fi
    
    # Clean up
    rm /tmp/setupVars.conf
}

# Fix Proxmox firewall forwarding issues
fix_proxmox_firewall() {
    print_header "CHECKING PROXMOX FIREWALL"
    
    # Check if Proxmox firewall is causing issues
    firewall_status=$(pve-firewall status 2>/dev/null || echo "not_found")
    
    if [[ "$firewall_status" == *"disabled/running"* ]] || [[ "$firewall_status" == *"enabled/running"* ]]; then
        print_warning "Proxmox firewall detected and may block container traffic"
        
        # Check if FORWARD policy is DROP
        if iptables -L FORWARD 2>/dev/null | grep -q "policy DROP"; then
            print_warning "Proxmox firewall has DROP policy for FORWARD chain - this blocks container networking"
            
            read -p "Temporarily disable Proxmox firewall restrictions to allow container traffic? (Y/n): " -r
            if [[ ! "$REPLY" =~ ^[Nn]$ ]]; then
                print_info "Clearing Proxmox firewall restrictions..."
                
                # Stop firewall service
                systemctl stop pve-firewall 2>/dev/null || true
                
                # Set permissive policies for container networking
                iptables -P FORWARD ACCEPT 2>/dev/null || true
                
                # Allow bridge forwarding
                echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true
                echo 0 > /proc/sys/net/bridge/bridge-nf-call-iptables 2>/dev/null || true
                
                print_success "✓ Proxmox firewall restrictions cleared for container networking"
                print_warning "⚠ Note: You may want to configure Proxmox firewall properly later for security"
            else
                print_info "Proceeding with Proxmox firewall enabled - may cause connectivity issues"
            fi
        else
            print_success "✓ Proxmox firewall seems configured properly"
        fi
    else
        print_success "✓ No Proxmox firewall issues detected"
    fi
}

# Test and fix container networking
test_fix_container_network() {
    print_header "TESTING CONTAINER NETWORK"
    
    print_info "Testing container network connectivity..."
    
    # Test gateway connectivity
    if ! pct_exec "$TARGET_NODE" "$CONTAINER_ID" timeout 10 ping -c 3 "$CONTAINER_GATEWAY" >/dev/null 2>&1; then
        print_warning "Container cannot reach gateway $CONTAINER_GATEWAY"
        
        # Try fixing by recreating network interface
        print_info "Attempting to fix network by recreating container interface..."
        
        # Generate new MAC address to force interface recreation
        NEW_MAC=$(printf 'BC:24:11:%02X:%02X:%02X\n' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
        
        print_info "Stopping container to recreate network interface..."
        if [[ "$TARGET_NODE" == "$(hostname)" ]]; then
            pct stop $CONTAINER_ID
            sleep 3
            pct set $CONTAINER_ID -net0 name=eth0,bridge=$CONTAINER_BRIDGE,gw=$CONTAINER_GATEWAY,hwaddr=$NEW_MAC,ip=$CONTAINER_IP,type=veth
            pct start $CONTAINER_ID
        else
            ssh root@$TARGET_NODE "pct stop $CONTAINER_ID"
            sleep 3
            ssh root@$TARGET_NODE "pct set $CONTAINER_ID -net0 name=eth0,bridge=$CONTAINER_BRIDGE,gw=$CONTAINER_GATEWAY,hwaddr=$NEW_MAC,ip=$CONTAINER_IP,type=veth"
            ssh root@$TARGET_NODE "pct start $CONTAINER_ID"
        fi
        
        # Wait for container to start and network to initialize
        print_info "Waiting for container network to initialize..."
        sleep 15
        
        # Test again
        if pct_exec "$TARGET_NODE" "$CONTAINER_ID" timeout 10 ping -c 3 "$CONTAINER_GATEWAY" >/dev/null 2>&1; then
            print_success "✓ Network connectivity restored after interface recreation"
        else
            print_error "✗ Network connectivity still failed after interface recreation"
            print_warning "Manual troubleshooting may be required"
            return 1
        fi
    else
        print_success "✓ Container network connectivity verified"
    fi
    
    # Test DNS resolution
    print_info "Testing DNS resolution..."
    if ! pct_exec "$TARGET_NODE" "$CONTAINER_ID" timeout 10 nslookup google.com >/dev/null 2>&1; then
        print_info "Configuring DNS resolution..."
        
        # Try router/gateway as DNS first
        pct_exec "$TARGET_NODE" "$CONTAINER_ID" bash -c "echo 'nameserver $CONTAINER_GATEWAY' > /etc/resolv.conf"
        
        if pct_exec "$TARGET_NODE" "$CONTAINER_ID" timeout 10 nslookup google.com >/dev/null 2>&1; then
            print_success "✓ DNS resolution fixed using gateway"
        else
            print_warning "Gateway DNS not working, trying public DNS..."
            pct_exec "$TARGET_NODE" "$CONTAINER_ID" bash -c "echo 'nameserver 1.1.1.1' > /etc/resolv.conf"
            pct_exec "$TARGET_NODE" "$CONTAINER_ID" bash -c "echo 'nameserver 8.8.8.8' >> /etc/resolv.conf"
            
            if pct_exec "$TARGET_NODE" "$CONTAINER_ID" timeout 10 nslookup google.com >/dev/null 2>&1; then
                print_success "✓ DNS resolution fixed using public DNS"
            else
                print_error "✗ DNS resolution still not working"
                return 1
            fi
        fi
    else
        print_success "✓ DNS resolution working"
    fi
    
    return 0
}

# Configure firewall
configure_firewall() {
    print_header "CONFIGURING FIREWALL"
    
    print_info "Installing and configuring UFW firewall..."
    
    pct_exec "$TARGET_NODE" "$CONTAINER_ID" bash -c "
        # Install UFW
        apt update >/dev/null 2>&1 && apt install -y ufw >/dev/null 2>&1
        
        # Reset to clean state to avoid issues
        ufw --force reset >/dev/null 2>&1
        
        # Set proper default policies - CRITICAL: Allow outgoing first!
        ufw default allow outgoing >/dev/null 2>&1
        ufw default deny incoming >/dev/null 2>&1
        
        # Allow required services
        ufw allow ssh >/dev/null 2>&1
        ufw allow 53/tcp >/dev/null 2>&1
        ufw allow 53/udp >/dev/null 2>&1
        ufw allow 80/tcp >/dev/null 2>&1
        ufw allow 443/tcp >/dev/null 2>&1
        
        # Enable firewall
        ufw --force enable >/dev/null 2>&1
    "
    
    print_success "✓ Firewall configured"
}

# Final configuration and testing
finalize_setup() {
    print_header "FINALIZING SETUP"
    
    print_info "Testing DNS resolution..."
    
    # Test Unbound
    if pct_exec "$TARGET_NODE" "$CONTAINER_ID" bash -c "dig @127.0.0.1 -p 5335 google.com +short" > /dev/null 2>&1; then
        print_success "Unbound DNS resolution test passed"
    else
        print_warning "Unbound DNS resolution test failed"
    fi
    
    # Test Pi-hole
    if pct_exec "$TARGET_NODE" "$CONTAINER_ID" bash -c "dig @127.0.0.1 google.com +short" > /dev/null 2>&1; then
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
    
    pct_push "$TARGET_NODE" "$CONTAINER_ID" /tmp/pihole-status.sh /usr/local/bin/pihole-status.sh
    pct_exec "$TARGET_NODE" "$CONTAINER_ID" bash -c "chmod +x /usr/local/bin/pihole-status.sh"
    
    rm /tmp/pihole-status.sh
    
    print_success "Setup finalized"
}

# Install Pi-hole on a single node
install_on_single_node() {
    local target_node="$1"
    local container_id="$2"
    local container_ip="$3"
    local node_index="$4"
    
    print_header "INSTALLING ON NODE: $target_node (Container ID: $container_id)"
    
    # Generate unique passwords for this container
    local container_password="$(openssl rand -base64 12)"
    local pihole_webpassword="$(openssl rand -base64 12)"
    
    # Store this installation info
    local install_info="Node:$target_node|ID:$container_id|IP:$container_ip|RootPW:$container_password|WebPW:$pihole_webpassword"
    
    # Set current installation variables (for compatibility with existing functions)
    CONTAINER_ID="$container_id"
    CONTAINER_IP="$container_ip/24"
    TARGET_NODE="$target_node"
    CONTAINER_PASSWORD="$container_password"
    PIHOLE_WEBPASSWORD="$pihole_webpassword"
    
    # Get storage for this node
    if [[ "$USE_DEFAULTS" == "true" ]]; then
        if [[ "$target_node" == "$(hostname)" ]]; then
            CONTAINER_STORAGE=$(pvesm status | grep -E "(local|nvme|lvm)" | head -1 | awk '{print $1}')
        else
            CONTAINER_STORAGE=$(ssh root@$target_node "pvesm status | grep -E '(local|nvme|lvm)' | head -1 | awk '{print \$1}'")
        fi
    else
        # For custom config, use first available storage on each node
        if [[ "$target_node" == "$(hostname)" ]]; then
            CONTAINER_STORAGE=$(pvesm status | grep -E "(local|nvme|lvm)" | head -1 | awk '{print $1}')
        else
            CONTAINER_STORAGE=$(ssh root@$target_node "pvesm status | grep -E '(local|nvme|lvm)' | head -1 | awk '{print \$1}'")
        fi
    fi
    
    print_info "Using storage: $CONTAINER_STORAGE on node $target_node"
    
    # Check if container ID already exists on this node
    local existing_container=""
    if [[ "$target_node" == "$(hostname)" ]]; then
        existing_container=$(pct list | grep "^$container_id" || true)
    else
        existing_container=$(ssh root@$target_node "pct list | grep '^$container_id'" || true)
    fi
    
    if [[ -n "$existing_container" ]]; then
        print_error "Container ID $container_id already exists on node $target_node"
        INSTALLATION_RESULTS+=("FAILED:$install_info|Error:Container ID exists")
        return 1
    fi
    
    # Run installation steps
    if ! select_template; then
        print_error "Template selection failed for node $target_node"
        INSTALLATION_RESULTS+=("FAILED:$install_info|Error:Template selection failed")
        return 1
    fi
    
    if ! create_container; then
        print_error "Container creation failed for node $target_node"
        INSTALLATION_RESULTS+=("FAILED:$install_info|Error:Container creation failed")
        return 1
    fi
    
    if ! configure_container; then
        print_error "Container configuration failed for node $target_node"
        INSTALLATION_RESULTS+=("FAILED:$install_info|Error:Container configuration failed")
        return 1
    fi
    
    # Test network connectivity - CRITICAL: Skip Pi-hole installation if this fails
    if ! test_fix_container_network; then
        print_error "❌ Network connectivity failed for container $container_id on $target_node"
        print_warning "Container created but Pi-hole installation skipped due to network issues"
        INSTALLATION_RESULTS+=("PARTIAL:$install_info|Error:Network connectivity failed")
        return 1
    fi
    
    if ! install_unbound; then
        print_error "Unbound installation failed for node $target_node"
        INSTALLATION_RESULTS+=("FAILED:$install_info|Error:Unbound installation failed")
        return 1
    fi
    
    # Install Pi-hole - Continue even if this fails
    if ! install_pihole; then
        print_error "❌ Pi-hole installation failed for container $container_id on $target_node"
        INSTALLATION_RESULTS+=("PARTIAL:$install_info|Error:Pi-hole installation failed")
        return 1
    fi
    
    if ! configure_firewall; then
        print_warning "Firewall configuration failed for node $target_node (non-critical)"
    fi
    
    if ! finalize_setup; then
        print_warning "Finalization failed for node $target_node (non-critical)"
    fi
    
    print_success "✅ Installation completed successfully on $target_node"
    INSTALLATION_RESULTS+=("SUCCESS:$install_info")
    return 0
}

# Generate IP for each node
generate_node_ip() {
    local base_ip="$1"
    local index="$2"
    
    # Split IP into octets
    IFS='.' read -r octet1 octet2 octet3 octet4 <<< "$base_ip"
    
    # Increment last octet by index
    local new_octet4=$((octet4 + index))
    
    # Handle overflow (basic implementation)
    if [[ $new_octet4 -gt 254 ]]; then
        new_octet4=$((new_octet4 - 254))
        octet3=$((octet3 + 1))
    fi
    
    echo "$octet1.$octet2.$octet3.$new_octet4"
}

# Multi-node installation orchestrator
install_on_multiple_nodes() {
    print_header "MULTI-NODE INSTALLATION ORCHESTRATOR"
    
    local total_nodes=${#SELECTED_NODES[@]}
    print_info "Starting installation on $total_nodes node(s)..."
    
    # Pre-flight checks
    print_info "Performing pre-flight checks..."
    
    # Check SSH connectivity to remote nodes
    for node in "${SELECTED_NODES[@]}"; do
        if [[ "$node" != "$(hostname)" ]]; then
            if ! ssh -o ConnectTimeout=5 root@$node "echo 'SSH test successful'" >/dev/null 2>&1; then
                print_error "Cannot connect to node $node via SSH"
                print_error "Ensure SSH key authentication is set up for root user"
                exit 1
            fi
        fi
    done
    
    print_success "All pre-flight checks passed"
    
    # Install on each node
    for i in "${!SELECTED_NODES[@]}"; do
        local node="${SELECTED_NODES[i]}"
        local container_id=$((BASE_CONTAINER_ID + i))
        local container_ip=$(generate_node_ip "$BASE_CONTAINER_IP" "$i")
        
        print_info "[$((i+1))/$total_nodes] Installing on node: $node"
        print_info "  Container ID: $container_id"
        print_info "  Container IP: $container_ip"
        
        # Install on this node (run in background for parallel installation)
        if [[ "$total_nodes" -gt 1 ]]; then
            # Parallel installation for multiple nodes
            {
                install_on_single_node "$node" "$container_id" "$container_ip" "$i"
            } &
            
            # Store background process PID
            local pid=$!
            print_info "Started installation on $node (PID: $pid)"
            
            # Don't overwhelm the system - stagger starts
            if [[ $((i % 2)) -eq 1 ]]; then
                sleep 30  # Stagger every other installation by 30 seconds
            fi
        else
            # Sequential installation for single node
            install_on_single_node "$node" "$container_id" "$container_ip" "$i"
        fi
    done
    
    # Wait for all background processes to complete
    if [[ "$total_nodes" -gt 1 ]]; then
        print_info "Waiting for all installations to complete..."
        wait
        print_success "All installations finished"
    fi
}

# Display installation results
display_results() {
    print_header "INSTALLATION RESULTS SUMMARY"
    
    local success_count=0
    local failed_count=0
    local partial_count=0
    
    echo ""
    print_info "📊 INSTALLATION SUMMARY:"
    echo ""
    
    for result in "${INSTALLATION_RESULTS[@]}"; do
        local status=$(echo "$result" | cut -d: -f1)
        local details=$(echo "$result" | cut -d: -f2-)
        
        # Parse details
        local node=$(echo "$details" | grep -o 'Node:[^|]*' | cut -d: -f2)
        local container_id=$(echo "$details" | grep -o 'ID:[^|]*' | cut -d: -f2)
        local container_ip=$(echo "$details" | grep -o 'IP:[^|]*' | cut -d: -f2)
        local root_pw=$(echo "$details" | grep -o 'RootPW:[^|]*' | cut -d: -f2)
        local web_pw=$(echo "$details" | grep -o 'WebPW:[^|]*' | cut -d: -f2)
        local error=$(echo "$details" | grep -o 'Error:[^|]*' | cut -d: -f2 || echo "")
        
        case $status in
            "SUCCESS")
                print_success "✅ Node: $node"
                echo "    Container ID: $container_id"
                echo "    Container IP: $container_ip"
                echo "    Pi-hole Web: http://$container_ip/admin"
                echo "    Web Password: $web_pw"
                echo "    Root Password: $root_pw"
                echo ""
                ((success_count++))
                ;;
            "PARTIAL")
                print_warning "⚠️  Node: $node (Partial Success)"
                echo "    Container ID: $container_id"
                echo "    Container IP: $container_ip"
                echo "    Issue: $error"
                echo "    Root Password: $root_pw"
                echo ""
                ((partial_count++))
                ;;
            "FAILED")
                print_error "❌ Node: $node (Failed)"
                echo "    Container ID: $container_id (if created)"
                echo "    Error: $error"
                echo ""
                ((failed_count++))
                ;;
        esac
    done
    
    print_info "📈 FINAL STATISTICS:"
    print_success "  Successful installations: $success_count"
    if [[ $partial_count -gt 0 ]]; then
        print_warning "  Partial installations: $partial_count"
    fi
    if [[ $failed_count -gt 0 ]]; then
        print_error "  Failed installations: $failed_count"
    fi
    echo ""
    
    if [[ $success_count -gt 0 ]]; then
        print_info "🔧 NEXT STEPS:"
        print_info "1. Configure your router/devices to use the Pi-hole DNS servers"
        print_info "2. Test DNS resolution from client devices"
        print_info "3. Access web interfaces to customize blocklists"
        print_info "4. Monitor logs: tail -f $LOG_FILE"
        
        if [[ $success_count -gt 1 ]]; then
            print_info "5. Consider setting up DNS load balancing or failover"
        fi
    fi
    
    if [[ $partial_count -gt 0 || $failed_count -gt 0 ]]; then
        print_warning "⚠️  Some installations had issues. Check NETWORK_TROUBLESHOOTING.md"
    fi
}

# Main execution
main() {
    print_header "PI-HOLE + UNBOUND MULTI-NODE LXC SETUP"
    
    check_root
    check_proxmox
    load_config
    select_target_nodes
    get_user_config
    fix_proxmox_firewall
    install_on_multiple_nodes
    display_results
    
    echo "Multi-node installation log saved to: $LOG_FILE"
}

# Run main function
main "$@" 
