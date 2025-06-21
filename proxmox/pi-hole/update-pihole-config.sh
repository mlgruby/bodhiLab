#!/bin/bash

# Pi-hole Configuration Update Script
# This script applies configuration changes to a running Pi-hole instance

# Default values
CONTAINER_ID="200"
CONFIG_DIR="$(dirname "$0")/config"
PIHOLE_CONFIG="$CONFIG_DIR/pihole.conf"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_header() {
    echo -e "\n${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

# Function to check if container exists and is running
check_container() {
    if ! pct status $CONTAINER_ID >/dev/null 2>&1; then
        print_error "Container $CONTAINER_ID does not exist"
        exit 1
    fi
    
    if [[ "$(pct status $CONTAINER_ID)" != "status: running" ]]; then
        print_error "Container $CONTAINER_ID is not running"
        print_info "Start it with: pct start $CONTAINER_ID"
        exit 1
    fi
    
    print_success "Container $CONTAINER_ID is running"
}

# Function to backup current Pi-hole config
backup_pihole_config() {
    print_info "Creating backup of current Pi-hole configuration..."
    
    BACKUP_DIR="/tmp/pihole-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Backup important Pi-hole files
    pct exec $CONTAINER_ID -- tar -czf /tmp/pihole-backup.tar.gz \
        /etc/pihole/ \
        /etc/dnsmasq.d/ \
        /opt/pihole/ 2>/dev/null || true
    
    # Copy backup to host
    pct pull $CONTAINER_ID /tmp/pihole-backup.tar.gz "$BACKUP_DIR/pihole-backup.tar.gz"
    
    print_success "Backup created: $BACKUP_DIR/pihole-backup.tar.gz"
}

# Function to apply blocklist changes
update_blocklists() {
    print_info "Updating Pi-hole blocklists..."
    
    if [[ -f "$PIHOLE_CONFIG" ]]; then
        # Source the config to get new blocklists
        source "$PIHOLE_CONFIG"
        
        # Clear existing blocklists and add new ones
        pct exec $CONTAINER_ID -- pihole -b -l /dev/null  # Clear existing
        
        # Add new blocklists
        for blocklist in "${PIHOLE_BLOCKLISTS[@]}"; do
            if [[ -n "$blocklist" ]]; then
                print_info "Adding blocklist: $blocklist"
                pct exec $CONTAINER_ID -- pihole -b "$blocklist"
            fi
        done
        
        # Update gravity
        pct exec $CONTAINER_ID -- pihole -g
        
        print_success "Blocklists updated successfully"
    else
        print_warning "Config file not found: $PIHOLE_CONFIG"
    fi
}

# Function to apply whitelist changes
update_whitelist() {
    print_info "Updating Pi-hole whitelist..."
    
    if [[ -f "$PIHOLE_CONFIG" ]]; then
        source "$PIHOLE_CONFIG"
        
        # Clear existing whitelist
        pct exec $CONTAINER_ID -- sqlite3 /etc/pihole/gravity.db "DELETE FROM domainlist WHERE type = 0;"
        
        # Add new whitelist entries
        for domain in "${PIHOLE_WHITELIST[@]}"; do
            if [[ -n "$domain" && "$domain" != *"#"* ]]; then
                print_info "Whitelisting: $domain"
                pct exec $CONTAINER_ID -- pihole -w "$domain"
            fi
        done
        
        # Add regex whitelist entries
        for pattern in "${PIHOLE_REGEX_WHITELIST[@]}"; do
            if [[ -n "$pattern" && "$pattern" != *"#"* ]]; then
                print_info "Adding regex whitelist: $pattern"
                pct exec $CONTAINER_ID -- pihole --regex-whitelist "$pattern"
            fi
        done
        
        print_success "Whitelist updated successfully"
    fi
}

# Function to apply DNS settings
update_dns_settings() {
    print_info "Updating DNS settings..."
    
    if [[ -f "$PIHOLE_CONFIG" ]]; then
        source "$PIHOLE_CONFIG"
        
        # Update DNS servers
        if [[ -n "$PIHOLE_DNS_1" ]]; then
            pct exec $CONTAINER_ID -- pihole -a -d "$PIHOLE_DNS_1" "$PIHOLE_DNS_2"
        fi
        
        # Update other DNS settings
        if [[ "$PIHOLE_DNSSEC" == "true" ]]; then
            pct exec $CONTAINER_ID -- pihole -a --dnssec enable
        else
            pct exec $CONTAINER_ID -- pihole -a --dnssec disable
        fi
        
        print_success "DNS settings updated successfully"
    fi
}

# Function to apply custom DNS records
update_custom_dns() {
    print_info "Updating custom DNS records..."
    
    if [[ -f "$PIHOLE_CONFIG" ]]; then
        source "$PIHOLE_CONFIG"
        
        # Clear existing custom DNS
        pct exec $CONTAINER_ID -- truncate -s 0 /etc/pihole/custom.list
        
        # Add new custom DNS records
        for record in "${PIHOLE_CUSTOM_DNS[@]}"; do
            if [[ -n "$record" && "$record" != *"#"* ]]; then
                domain=$(echo "$record" | cut -d',' -f1)
                ip=$(echo "$record" | cut -d',' -f2)
                if [[ -n "$domain" && -n "$ip" ]]; then
                    print_info "Adding custom DNS: $domain -> $ip"
                    pct exec $CONTAINER_ID -- bash -c "echo '$ip $domain' >> /etc/pihole/custom.list"
                fi
            fi
        done
        
        print_success "Custom DNS records updated successfully"
    fi
}

# Function to restart services
restart_services() {
    print_info "Restarting Pi-hole services..."
    
    pct exec $CONTAINER_ID -- systemctl restart pihole-FTL
    sleep 2
    pct exec $CONTAINER_ID -- systemctl restart lighttpd
    
    print_success "Services restarted successfully"
}

# Function to verify configuration
verify_config() {
    print_info "Verifying Pi-hole configuration..."
    
    # Check if services are running
    if pct exec $CONTAINER_ID -- systemctl is-active --quiet pihole-FTL; then
        print_success "Pi-hole FTL service is running"
    else
        print_error "Pi-hole FTL service is not running"
    fi
    
    if pct exec $CONTAINER_ID -- systemctl is-active --quiet lighttpd; then
        print_success "Web server is running"
    else
        print_error "Web server is not running"
    fi
    
    # Test DNS resolution
    if pct exec $CONTAINER_ID -- timeout 5 dig @127.0.0.1 google.com +short >/dev/null 2>&1; then
        print_success "DNS resolution is working"
    else
        print_warning "DNS resolution test failed"
    fi
    
    # Show Pi-hole status
    print_info "Pi-hole status:"
    pct exec $CONTAINER_ID -- pihole status
}

# Main function
main() {
    print_header "PI-HOLE CONFIGURATION UPDATE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--container)
                CONTAINER_ID="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  -c, --container ID    Container ID (default: 200)"
                echo "  -h, --help           Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Check prerequisites
    check_container
    
    # Create backup
    backup_pihole_config
    
    # Apply configuration changes
    update_blocklists
    update_whitelist
    update_dns_settings
    update_custom_dns
    
    # Restart services
    restart_services
    
    # Verify configuration
    verify_config
    
    print_header "CONFIGURATION UPDATE COMPLETED"
    print_success "Pi-hole configuration has been updated successfully"
    print_info "Web interface: http://$(pct exec $CONTAINER_ID -- hostname -I | awk '{print $1}')/admin"
    print_info "Check the web interface to verify all settings are correct"
}

# Run main function
main "$@"
