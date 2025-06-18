#!/bin/bash

#################################################
# Proxmox Automated Setup Installer
#################################################
# This script downloads and runs the Proxmox
# post-installation and advanced configuration scripts
#################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Script URLs
POST_INSTALL_URL="https://raw.githubusercontent.com/mlgruby/bodhiLab/refs/heads/main/proxmox/proxmox-post-install.sh"
ADVANCED_CONFIG_URL="https://raw.githubusercontent.com/mlgruby/bodhiLab/refs/heads/main/proxmox/proxmox-advanced-config.sh"

# Script filenames
POST_INSTALL_SCRIPT="proxmox-post-install.sh"
ADVANCED_CONFIG_SCRIPT="proxmox-advanced-config.sh"

print_header "PROXMOX AUTOMATED SETUP INSTALLER"
echo "This script will download and run:"
echo "1. Post-installation script (essential)"
echo "2. Advanced configuration script (optional)"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    exit 1
fi

# Check internet connectivity
print_info "Checking internet connectivity..."
if ! ping -c 1 google.com &> /dev/null; then
    print_error "No internet connection. Please check your network."
    exit 1
fi
print_success "Internet connection OK"

# Download post-installation script
print_header "DOWNLOADING POST-INSTALLATION SCRIPT"
print_info "Downloading from: $POST_INSTALL_URL"

if wget -q "$POST_INSTALL_URL" -O "$POST_INSTALL_SCRIPT"; then
    print_success "Post-installation script downloaded"
else
    print_error "Failed to download post-installation script"
    exit 1
fi

# Make executable
chmod +x "$POST_INSTALL_SCRIPT"
print_success "Post-installation script made executable"

# Download advanced configuration script
print_header "DOWNLOADING ADVANCED CONFIGURATION SCRIPT"
print_info "Downloading from: $ADVANCED_CONFIG_URL"

if wget -q "$ADVANCED_CONFIG_URL" -O "$ADVANCED_CONFIG_SCRIPT"; then
    print_success "Advanced configuration script downloaded"
else
    print_error "Failed to download advanced configuration script"
    exit 1
fi

# Make executable
chmod +x "$ADVANCED_CONFIG_SCRIPT"
print_success "Advanced configuration script made executable"

# Show what was downloaded
print_header "DOWNLOADED SCRIPTS"
echo "Scripts downloaded to: $(pwd)"
echo ""
ls -la *.sh
echo ""

# Ask user what to run
print_header "EXECUTION OPTIONS"
echo "Choose what to run:"
echo "1. Run post-installation script only (recommended first)"
echo "2. Run both scripts sequentially"
echo "3. Don't run anything now (just download)"
echo ""

read -p "Select option (1-3): " choice

case $choice in
    1)
        print_header "RUNNING POST-INSTALLATION SCRIPT"
        echo "Starting post-installation configuration..."
        echo ""
        
        if ./"$POST_INSTALL_SCRIPT"; then
            print_success "Post-installation script completed successfully!"
            echo ""
            print_info "NEXT STEPS:"
            echo "1. Reboot your system: reboot"
            echo "2. After reboot, run advanced config: ./$ADVANCED_CONFIG_SCRIPT"
            echo "3. Or run this installer again and choose option 2"
        else
            print_error "Post-installation script failed"
            exit 1
        fi
        ;;
        
    2)
        print_header "RUNNING POST-INSTALLATION SCRIPT"
        echo "Starting post-installation configuration..."
        echo ""
        
        if ./"$POST_INSTALL_SCRIPT"; then
            print_success "Post-installation script completed!"
            echo ""
            
            print_info "Post-installation complete. Continue with advanced configuration?"
            read -p "Continue with advanced configuration? (y/N): " continue_choice
            
            if [[ $continue_choice =~ ^[Yy]$ ]]; then
                print_header "RUNNING ADVANCED CONFIGURATION SCRIPT"
                echo "Starting advanced configuration..."
                echo ""
                
                if ./"$ADVANCED_CONFIG_SCRIPT"; then
                    print_success "Advanced configuration completed successfully!"
                    echo ""
                    print_info "SETUP COMPLETE!"
                    echo "Consider rebooting your system: reboot"
                else
                    print_error "Advanced configuration script failed"
                    exit 1
                fi
            else
                print_info "Advanced configuration skipped"
                echo "You can run it later with: ./$ADVANCED_CONFIG_SCRIPT"
            fi
        else
            print_error "Post-installation script failed"
            exit 1
        fi
        ;;
        
    3)
        print_info "Scripts downloaded but not executed"
        echo ""
        echo "To run later:"
        echo "  Post-installation: ./$POST_INSTALL_SCRIPT"
        echo "  Advanced config:   ./$ADVANCED_CONFIG_SCRIPT"
        ;;
        
    *)
        print_error "Invalid option selected"
        exit 1
        ;;
esac

print_header "INSTALLER COMPLETE"
print_success "All operations completed successfully!"
echo ""
echo "Scripts are available in current directory:"
echo "  - $POST_INSTALL_SCRIPT"
echo "  - $ADVANCED_CONFIG_SCRIPT"
echo ""
echo "You can re-run them anytime or run this installer again."
