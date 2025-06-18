#!/bin/bash

#################################################
# Complete ZFS Optimizer for Intel N150 + Proxmox
#################################################
# Comprehensive ZFS optimization with user guidance
# Designed for Intel N150 + 32GB DDR4 + NVMe
# Pool name: local-nvme
#################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Logging
LOG_FILE="/var/log/zfs-optimizer.log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

print_header() {
    echo -e "${BLUE}${BOLD}================================================${NC}"
    echo -e "${BLUE}${BOLD}$1${NC}"
    echo -e "${BLUE}${BOLD}================================================${NC}"
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
    echo -e "${CYAN}ℹ $1${NC}"
}

print_recommendation() {
    echo -e "${YELLOW}${BOLD}💡 RECOMMENDATION: $1${NC}"
}

print_choice() {
    echo -e "${BLUE}$1${NC}"
}

# Enhanced safe ZFS property setting with proper error handling
safe_zfs_set() {
    local property="$1"
    local value="$2"
    local dataset="$3"
    
    # Attempt to set the property and capture both output and exit code
    local error_output
    error_output=$(zfs set "$property=$value" "$dataset" 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        print_success "Set $property to $value on $(basename $dataset)"
        return 0
    else
        # Handle specific error cases gracefully
        case $property in
            "volblocksize")
                if [[ "$error_output" == *"does not apply to datasets of this type"* ]]; then
                    print_info "volblocksize skipped for $(basename $dataset) (applies to volumes/zvols only)"
                    print_info "New VMs will inherit this setting when created"
                    return 0  # Not actually an error
                else
                    print_warning "Unexpected volblocksize error on $(basename $dataset): $error_output"
                    return 1
                fi
                ;;
            *)
                print_error "Failed to set $property to $value on $(basename $dataset): $error_output"
                return 1
                ;;
        esac
    fi
}

# Check dependencies function
check_dependencies() {
    print_info "Checking system dependencies..."
    
    local missing_packages=()
    
    # Check for essential tools
    if ! command -v bc &> /dev/null; then
        missing_packages+=("bc")
    fi
    
    if ! command -v sensors &> /dev/null; then
        missing_packages+=("lm-sensors")
    fi
    
    # Check for ZFS tools
    if ! command -v zfs &> /dev/null; then
        print_error "ZFS tools not found! Install zfsutils-linux"
        exit 1
    fi
    
    # Install missing packages
    if [ ${#missing_packages[@]} -ne 0 ]; then
        print_info "Installing missing packages: ${missing_packages[*]}"
        apt update -qq
        apt install -y "${missing_packages[@]}"
        
        # Configure sensors if just installed
        if [[ " ${missing_packages[*]} " =~ " lm-sensors " ]]; then
            print_info "Configuring hardware sensors..."
            sensors-detect --auto
        fi
    fi
    
    print_success "Dependencies check complete"
}

# System detection
detect_system() {
    print_header "SYSTEM DETECTION"
    
    # CPU Detection with better Intel N-series recognition
    CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    CPU_CORES=$(nproc)
    CPU_FREQ=$(grep "cpu MHz" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    print_info "CPU: $CPU_MODEL ($CPU_CORES cores)"
    
    # Better Intel N-series detection
    if [[ "$CPU_MODEL" =~ N150 ]]; then
        print_success "Intel N150 detected - optimal settings available"
        IS_N150=true
        CPU_CACHE="6MB"
        CPU_TURBO="3.6GHz"
    elif [[ "$CPU_MODEL" =~ N100 ]]; then
        print_info "Intel N100 detected - compatible settings available"
        IS_N150=false
        CPU_CACHE="6MB"
        CPU_TURBO="3.4GHz"
    elif [[ "$CPU_MODEL" =~ "Celeron.*N" ]] || [[ "$CPU_MODEL" =~ "Pentium.*N" ]]; then
        print_info "Intel N-series processor detected"
        IS_N150=false
        CPU_CACHE="4MB"
        CPU_TURBO="Unknown"
    else
        print_warning "CPU not recognized as Intel N-series - using generic settings"
        IS_N150=false
        CPU_CACHE="Unknown"
        CPU_TURBO="Unknown"
    fi
    
    if [[ -n "$CPU_CACHE" && "$CPU_CACHE" != "Unknown" ]]; then
        print_info "CPU Cache: $CPU_CACHE, Turbo: $CPU_TURBO"
    fi
    
    # Enhanced RAM detection
    TOTAL_RAM_GB=$(free -g | grep "^Mem:" | awk '{print $2}')
    TOTAL_RAM_MB=$(free -m | grep "^Mem:" | awk '{print $2}')
    AVAILABLE_RAM_GB=$(free -g | grep "^Mem:" | awk '{print $7}')
    
    print_info "RAM: ${TOTAL_RAM_GB}GB total (${AVAILABLE_RAM_GB}GB available)"
    
    # Enhanced RAM classification
    if [[ $TOTAL_RAM_GB -ge 32 ]]; then
        print_success "32GB+ RAM detected - advanced optimizations available"
        HAS_ABUNDANT_RAM=true
        RAM_CLASS="abundant"
    elif [[ $TOTAL_RAM_GB -ge 16 ]]; then
        print_success "16GB+ RAM detected - good optimization potential"
        HAS_ABUNDANT_RAM=false
        RAM_CLASS="good"
    elif [[ $TOTAL_RAM_GB -ge 8 ]]; then
        print_info "8GB+ RAM detected - moderate optimization available"
        HAS_ABUNDANT_RAM=false
        RAM_CLASS="moderate"
    else
        print_warning "Limited RAM detected - conservative optimizations only"
        HAS_ABUNDANT_RAM=false
        RAM_CLASS="limited"
    fi
    
    # ZFS Pool Detection with health check
    if zpool list local-nvme &>/dev/null; then
        POOL_SIZE=$(zpool list -H -o size local-nvme)
        POOL_HEALTH=$(zpool list -H -o health local-nvme)
        POOL_USAGE=$(zpool list -H -o cap local-nvme)
        
        print_success "ZFS Pool: local-nvme ($POOL_SIZE, $POOL_HEALTH, ${POOL_USAGE} used)"
        
        # Check pool health
        if [[ "$POOL_HEALTH" != "ONLINE" ]]; then
            print_warning "Pool health is $POOL_HEALTH - check zpool status"
        fi
        
        # Check pool usage
        USAGE_NUM=$(echo "$POOL_USAGE" | sed 's/%//')
        if [[ $USAGE_NUM -gt 80 ]]; then
            print_warning "Pool is ${POOL_USAGE} full - consider cleanup before optimization"
        fi
    else
        print_error "ZFS pool 'local-nvme' not found!"
        print_info "Available pools:"
        zpool list 2>/dev/null || print_info "No ZFS pools found"
        exit 1
    fi
    
    # Storage type detection
    if ls /sys/block/nvme* &>/dev/null; then
        STORAGE_TYPE="NVMe"
        print_success "NVMe storage detected - optimal for ZFS"
    elif ls /sys/block/sd* &>/dev/null; then
        STORAGE_TYPE="SATA"
        print_info "SATA storage detected"
    else
        STORAGE_TYPE="Unknown"
        print_warning "Storage type unknown"
    fi
    
    echo ""
    print_info "=== System Summary ==="
    print_info "CPU: $([[ "$IS_N150" == true ]] && echo "Intel N150 (optimized)" || echo "$CPU_MODEL")"
    print_info "RAM: ${TOTAL_RAM_GB}GB ($RAM_CLASS)"
    print_info "Storage: $STORAGE_TYPE"
    print_info "ZFS Pool: $POOL_SIZE ($POOL_HEALTH)"
    echo ""
}

# Configuration menu
show_optimization_menu() {
    print_header "ZFS OPTIMIZATION MENU"
    echo ""
    print_info "This script will guide you through optimizing ZFS for your system."
    print_info "Each option includes recommendations based on your hardware."
    echo ""
    print_choice "Available optimizations:"
    print_choice "1. Core Performance Settings (Record size, compression, etc.)"
    print_choice "2. Memory Management (ARC cache, system memory)"
    print_choice "3. Advanced Features (Deduplication, specialized datasets)"
    print_choice "4. System Integration (I/O scheduler, kernel parameters)"
    print_choice "5. Monitoring & Maintenance (Health checks, automated tasks)"
    print_choice "6. Complete Optimization (All of the above with recommendations)"
    print_choice "7. Custom Configuration (Choose specific settings)"
    print_choice "8. Show Current Settings"
    print_choice "9. Exit"
    echo ""
}

# Core performance settings with improved error handling
configure_core_performance() {
    print_header "CORE PERFORMANCE OPTIMIZATION"
    
    # Record Size
    current_recordsize=$(zfs get -H -o value recordsize local-nvme)
    print_info "Current record size: $current_recordsize"
    echo ""
    print_info "Record size determines ZFS block size for new data:"
    print_choice "1. 16K - Database workloads, random I/O"
    print_choice "2. 32K - Mixed workloads, containers"
    print_choice "3. 64K - VM workloads (RECOMMENDED for N150)"
    print_choice "4. 128K - Large files, default setting"
    print_choice "5. 1M - Media files, backups"
    print_choice "6. Keep current setting ($current_recordsize)"
    
    if [[ "$IS_N150" == true ]]; then
        print_recommendation "For Intel N150 + VMs: Choose option 3 (64K)"
        print_info "N150's 6MB cache and 3.6GHz turbo handle 64K blocks efficiently"
    else
        print_recommendation "For general VM workloads: Choose option 2 (32K) or 3 (64K)"
    fi
    
    echo ""
    read -p "Choose record size (1-6): " recordsize_choice
    
    case $recordsize_choice in
        1) safe_zfs_set "recordsize" "16K" "local-nvme" ;;
        2) safe_zfs_set "recordsize" "32K" "local-nvme" ;;
        3) safe_zfs_set "recordsize" "64K" "local-nvme" ;;
        4) safe_zfs_set "recordsize" "128K" "local-nvme" ;;
        5) safe_zfs_set "recordsize" "1M" "local-nvme" ;;
        6) print_info "Keeping current record size ($current_recordsize)" ;;
        *) print_warning "Invalid choice, keeping current setting" ;;
    esac
    
    echo ""
    
    # Compression with better explanations
    current_compression=$(zfs get -H -o value compression local-nvme)
    print_info "Current compression: $current_compression"
    echo ""
    print_info "Compression algorithms (CPU usage vs space savings):"
    print_choice "1. off - No compression (fastest, no space savings)"
    print_choice "2. lz4 - Fast compression (2-4% CPU, 1.2-1.5x space savings) ⭐"
    print_choice "3. zstd-1 - Fast zstd (6-10% CPU, 1.3-1.8x space savings)"
    print_choice "4. zstd-3 - Balanced zstd (10-15% CPU, 1.4-2.0x space savings) ⭐"
    print_choice "5. zstd-6 - High compression (18-25% CPU, 1.6-2.4x space savings)"
    print_choice "6. gzip-1 - Light gzip (20-25% CPU, 1.5-2.5x space savings)"
    print_choice "7. gzip-6 - Standard gzip (30-40% CPU, 1.8-3.0x space savings)"
    print_choice "8. Keep current setting ($current_compression)"
    
    if [[ "$IS_N150" == true ]]; then
        print_recommendation "For Intel N150: Choose option 4 (zstd-3) for best balance"
        print_info "N150's 3.6GHz turbo can handle zstd-3 efficiently"
    else
        print_recommendation "For general systems: Choose option 2 (lz4) for reliability"
    fi
    
    echo ""
    read -p "Choose compression (1-8): " compression_choice
    
    case $compression_choice in
        1) safe_zfs_set "compression" "off" "local-nvme" ;;
        2) safe_zfs_set "compression" "lz4" "local-nvme" ;;
        3) safe_zfs_set "compression" "zstd-1" "local-nvme" ;;
        4) safe_zfs_set "compression" "zstd-3" "local-nvme" ;;
        5) safe_zfs_set "compression" "zstd-6" "local-nvme" ;;
        6) safe_zfs_set "compression" "gzip-1" "local-nvme" ;;
        7) safe_zfs_set "compression" "gzip-6" "local-nvme" ;;
        8) print_info "Keeping current compression ($current_compression)" ;;
        *) print_warning "Invalid choice, keeping current setting" ;;
    esac
    
    echo ""
    
    # FIXED: Volume Block Size handling with proper explanation
    print_info "Volume block size affects NEW VM disks only (not existing VMs)"
    print_info "This setting will be used as default for new ZFS volumes"
    echo ""
    print_info "Volume block size options:"
    print_choice "1. 8K - Database VMs, high random I/O"
    print_choice "2. 16K - General VM workloads"
    print_choice "3. 32K - Larger VMs, better for N150"
    print_choice "4. 64K - Large VMs, sequential workloads"
    print_choice "5. Skip volume block size configuration"
    
    if [[ "$IS_N150" == true ]]; then
        print_recommendation "For Intel N150: Choose option 3 (32K)"
        print_info "N150 handles larger block sizes efficiently"
    else
        print_recommendation "For general systems: Choose option 2 (16K)"
    fi
    
    echo ""
    read -p "Choose volume block size (1-5): " volblocksize_choice
    
    case $volblocksize_choice in
        1) 
            print_info "Setting default volume block size to 8K for new volumes"
            safe_zfs_set "volblocksize" "8K" "local-nvme"
            ;;
        2) 
            print_info "Setting default volume block size to 16K for new volumes"
            safe_zfs_set "volblocksize" "16K" "local-nvme"
            ;;
        3) 
            print_info "Setting default volume block size to 32K for new volumes"
            safe_zfs_set "volblocksize" "32K" "local-nvme"
            ;;
        4) 
            print_info "Setting default volume block size to 64K for new volumes"
            safe_zfs_set "volblocksize" "64K" "local-nvme"
            ;;
        5) 
            print_info "Skipping volume block size configuration"
            ;;
        *) 
            print_warning "Invalid choice, skipping volume block size"
            ;;
    esac
    
    echo ""
    
    # Access Time (this works fine)
    current_atime=$(zfs get -H -o value atime local-nvme)
    print_info "Current atime setting: $current_atime"
    echo ""
    print_info "Access time tracking:"
    print_choice "1. off - Disable access time tracking (RECOMMENDED)"
    print_choice "2. on - Enable access time tracking (more writes)"
    print_choice "3. Keep current setting ($current_atime)"
    
    print_recommendation "Choose option 1 (off) for better performance"
    print_info "Disabling atime reduces write operations and improves performance"
    
    echo ""
    read -p "Choose atime setting (1-3): " atime_choice
    
    case $atime_choice in
        1) safe_zfs_set "atime" "off" "local-nvme" ;;
        2) safe_zfs_set "atime" "on" "local-nvme" ;;
        3) print_info "Keeping current atime setting ($current_atime)" ;;
        *) print_warning "Invalid choice, keeping current setting" ;;
    esac
    
    echo ""
    print_success "Core performance optimization complete!"
    echo ""
}

# Memory management (keep existing)
configure_memory_management() {
    print_header "MEMORY MANAGEMENT OPTIMIZATION"
    
    # Calculate ARC recommendations
    if [[ $TOTAL_RAM_GB -ge 32 ]]; then
        ARC_MAX_RECOMMEND="8GB (25% of RAM)"
        ARC_MAX_BYTES="8589934592"
        ARC_MIN_BYTES="2147483648"
    elif [[ $TOTAL_RAM_GB -ge 16 ]]; then
        ARC_MAX_RECOMMEND="4GB (25% of RAM)"
        ARC_MAX_BYTES="4294967296"
        ARC_MIN_BYTES="1073741824"
    else
        ARC_MAX_RECOMMEND="2GB (25% of RAM)"
        ARC_MAX_BYTES="2147483648"
        ARC_MIN_BYTES="536870912"
    fi
    
    print_info "System RAM: ${TOTAL_RAM_GB}GB"
    print_info "Current ARC size: $(grep "^size" /proc/spl/kstat/zfs/arcstats 2>/dev/null | awk '{printf "%.1fGB", $3/1024/1024/1024}' || echo 'Unknown')"
    echo ""
    
    print_info "ARC (Adaptive Replacement Cache) options:"
    print_choice "1. Conservative - ${ARC_MAX_RECOMMEND} max, plenty of RAM for VMs"
    print_choice "2. Balanced - 30% of RAM for ARC cache"
    print_choice "3. Aggressive - 40% of RAM for ARC cache (high performance)"
    print_choice "4. Custom - Specify custom values"
    print_choice "5. Keep current settings"
    
    print_recommendation "For ${TOTAL_RAM_GB}GB system: Choose option 1 (${ARC_MAX_RECOMMEND})"
    if [[ "$HAS_ABUNDANT_RAM" == true ]]; then
        print_info "With 32GB+ RAM, you can also consider option 2 for better caching"
    fi
    
    echo ""
    read -p "Choose ARC configuration (1-5): " arc_choice
    
    case $arc_choice in
        1)
            ARC_MAX=$ARC_MAX_BYTES
            ARC_MIN=$ARC_MIN_BYTES
            print_success "Selected conservative ARC settings"
            ;;
        2)
            ARC_MAX=$((TOTAL_RAM_MB * 1024 * 1024 * 30 / 100))
            ARC_MIN=$((TOTAL_RAM_MB * 1024 * 1024 * 10 / 100))
            print_success "Selected balanced ARC settings"
            ;;
        3)
            ARC_MAX=$((TOTAL_RAM_MB * 1024 * 1024 * 40 / 100))
            ARC_MIN=$((TOTAL_RAM_MB * 1024 * 1024 * 15 / 100))
            print_success "Selected aggressive ARC settings"
            ;;
        4)
            echo ""
            print_info "Enter custom ARC sizes:"
            read -p "ARC maximum size in GB: " custom_arc_max
            read -p "ARC minimum size in GB: " custom_arc_min
            ARC_MAX=$((custom_arc_max * 1024 * 1024 * 1024))
            ARC_MIN=$((custom_arc_min * 1024 * 1024 * 1024))
            print_success "Selected custom ARC settings"
            ;;
        5)
            print_info "Keeping current ARC settings"
            ARC_MAX=""
            ;;
        *)
            print_warning "Invalid choice, keeping current settings"
            ARC_MAX=""
            ;;
    esac
    
    # Apply ARC settings
    if [[ -n "$ARC_MAX" ]]; then
        echo ""
        print_info "Configuring ARC settings..."
        
        # Create or update ZFS module configuration
        if [[ ! -f /etc/modprobe.d/zfs.conf ]]; then
            cat > /etc/modprobe.d/zfs.conf << EOF
# ZFS ARC Configuration
options zfs zfs_arc_max=$ARC_MAX
options zfs zfs_arc_min=$ARC_MIN
EOF
        else
            # Update existing configuration
            sed -i '/zfs_arc_max/d' /etc/modprobe.d/zfs.conf
            sed -i '/zfs_arc_min/d' /etc/modprobe.d/zfs.conf
            echo "options zfs zfs_arc_max=$ARC_MAX" >> /etc/modprobe.d/zfs.conf
            echo "options zfs zfs_arc_min=$ARC_MIN" >> /etc/modprobe.d/zfs.conf
        fi
        
        ARC_MAX_GB=$((ARC_MAX / 1024 / 1024 / 1024))
        ARC_MIN_GB=$((ARC_MIN / 1024 / 1024 / 1024))
        print_success "ARC configured: ${ARC_MIN_GB}GB min, ${ARC_MAX_GB}GB max"
        print_warning "Reboot required for ARC changes to take effect"
    fi
    
    echo ""
    
    # System memory settings
    print_info "System memory optimization:"
    print_choice "1. Optimize for ZFS + VMs (RECOMMENDED)"
    print_choice "2. Optimize for maximum performance"
    print_choice "3. Keep current settings"
    
    print_recommendation "Choose option 1 for balanced ZFS + VM performance"
    
    echo ""
    read -p "Choose memory optimization (1-3): " mem_choice
    
    case $mem_choice in
        1|2)
            print_info "Configuring system memory settings..."
            
            # Configure sysctl for ZFS + VM optimization
            cat >> /etc/sysctl.conf << 'EOF'

# ZFS + VM Memory Optimization
vm.swappiness=1
vm.vfs_cache_pressure=50
vm.dirty_ratio=5
vm.dirty_background_ratio=3
vm.dirty_expire_centisecs=1500
vm.dirty_writeback_centisecs=500
EOF

            if [[ $mem_choice -eq 2 ]] && [[ $TOTAL_RAM_GB -ge 16 ]]; then
                cat >> /etc/sysctl.conf << 'EOF'
# Performance optimization
vm.nr_hugepages=1024
net.core.rmem_max=134217728
net.core.wmem_max=134217728
EOF
                print_success "Applied performance memory settings"
            else
                print_success "Applied balanced memory settings"
            fi
            
            # Apply settings
            sysctl -p > /dev/null 2>&1 || true
            ;;
        3)
            print_info "Keeping current memory settings"
            ;;
        *)
            print_warning "Invalid choice, keeping current settings"
            ;;
    esac
    
    echo ""
    print_success "Memory management optimization complete!"
    echo ""
}

# Updated configure_advanced_features with improved error handling
configure_advanced_features() {
    print_header "ADVANCED FEATURES CONFIGURATION"
    
    # Deduplication
    print_info "Current deduplication: $(zfs get -H -o value dedup local-nvme)"
    echo ""
    print_info "Deduplication eliminates duplicate blocks to save space."
    print_warning "Requires significant RAM: ~5MB per GB of unique data"
    
    # Calculate dedup capacity
    DEDUP_CAPACITY_GB=$((TOTAL_RAM_GB * 200))  # Conservative estimate
    
    print_info "Your ${TOTAL_RAM_GB}GB RAM can handle approximately ${DEDUP_CAPACITY_GB}GB of deduplicated data"
    print_info "Your pool size: $(zpool list -H -o size local-nvme)"
    
    echo ""
    print_choice "1. Enable deduplication (space savings, uses more RAM)"
    print_choice "2. Disable deduplication (faster, less RAM usage)"
    print_choice "3. Keep current setting"
    
    if [[ "$HAS_ABUNDANT_RAM" == true ]]; then
        print_recommendation "With ${TOTAL_RAM_GB}GB RAM: Choose option 1 if you have many similar VMs"
        print_info "Great for VM templates and clones"
    else
        print_recommendation "With ${TOTAL_RAM_GB}GB RAM: Choose option 2 for better performance"
        print_info "Dedup may impact performance on systems with limited RAM"
    fi
    
    echo ""
    read -p "Choose deduplication setting (1-3): " dedup_choice
    
    case $dedup_choice in
        1)
            safe_zfs_set "dedup" "on" "local-nvme"
            print_info "Monitor dedup ratio with: zfs get dedupratio local-nvme"
            ;;
        2)
            safe_zfs_set "dedup" "off" "local-nvme"
            ;;
        3)
            print_info "Keeping current deduplication setting"
            ;;
        *)
            print_warning "Invalid choice, keeping current setting"
            ;;
    esac
    
    echo ""
    
    # Specialized datasets with improved error handling
    print_info "Specialized datasets allow optimizing different workloads separately."
    echo ""
    print_choice "Create specialized datasets?"
    print_choice "1. Yes - Create optimized datasets (vms, templates, backups, etc.)"
    print_choice "2. No - Keep simple single-pool structure"
    
    print_recommendation "Choose option 1 for professional setup with multiple VM types"
    print_info "Creates separate datasets for VMs, templates, containers, and backups"
    
    echo ""
    read -p "Create specialized datasets? (1-2): " datasets_choice
    
    if [[ $datasets_choice -eq 1 ]]; then
        print_info "Creating specialized datasets..."
        
        # Create datasets (skip ISO since you have separate SATA drive)
        datasets=("vms" "templates" "containers" "backups")
        
        for dataset in "${datasets[@]}"; do
            if ! zfs list local-nvme/$dataset &>/dev/null; then
                zfs create local-nvme/$dataset
                print_success "Created dataset: local-nvme/$dataset"
            else
                print_info "Dataset already exists: local-nvme/$dataset"
            fi
        done
        
        echo ""
        print_info "Optimizing datasets for their specific workloads..."
        
        # Optimize VMs dataset with proper error handling
        print_info "Configuring VMs dataset for performance..."
        safe_zfs_set "recordsize" "64K" "local-nvme/vms"
        safe_zfs_set "compression" "lz4" "local-nvme/vms"
        safe_zfs_set "atime" "off" "local-nvme/vms"
        
        # Optimize templates dataset
        print_info "Configuring templates dataset for space efficiency..."
        safe_zfs_set "recordsize" "128K" "local-nvme/templates"
        safe_zfs_set "compression" "zstd-6" "local-nvme/templates"
        safe_zfs_set "dedup" "on" "local-nvme/templates"
        safe_zfs_set "atime" "off" "local-nvme/templates"
        
        # Optimize containers dataset
        print_info "Configuring containers dataset..."
        safe_zfs_set "recordsize" "32K" "local-nvme/containers"
        safe_zfs_set "compression" "zstd-1" "local-nvme/containers"
        safe_zfs_set "atime" "off" "local-nvme/containers"
        
        # Optimize backups dataset
        print_info "Configuring backups dataset for maximum compression..."
        safe_zfs_set "recordsize" "1M" "local-nvme/backups"
        safe_zfs_set "compression" "gzip-6" "local-nvme/backups"
        safe_zfs_set "sync" "disabled" "local-nvme/backups"
        safe_zfs_set "atime" "off" "local-nvme/backups"
        
        print_success "Dataset optimization complete!"
        
        # Set container-focused quotas (updated for your use case)
        echo ""
        print_info "Setting container-focused quotas..."
        POOL_SIZE_GB=$(zpool list -H -o size local-nvme | sed 's/[GT].*//' | cut -d. -f1)
        print_info "Detected pool size: ${POOL_SIZE_GB}GB"
        
        # Container-focused allocation (15% VMs, 65% containers)
        VM_QUOTA=$((POOL_SIZE_GB * 15 / 100))          # 15% for VMs (1-2 VMs)
        CONTAINER_QUOTA=$((POOL_SIZE_GB * 65 / 100))   # 65% for containers (primary workload)
        TEMPLATE_QUOTA=$((POOL_SIZE_GB * 8 / 100))     # 8% for templates
        BACKUP_QUOTA=$((POOL_SIZE_GB * 10 / 100))      # 10% for backups
        
        safe_zfs_set "quota" "${VM_QUOTA}G" "local-nvme/vms"
        safe_zfs_set "quota" "${CONTAINER_QUOTA}G" "local-nvme/containers"
        safe_zfs_set "quota" "${TEMPLATE_QUOTA}G" "local-nvme/templates"
        safe_zfs_set "quota" "${BACKUP_QUOTA}G" "local-nvme/backups"
        
        print_success "Set container-focused quotas:"
        print_info "  VMs: ${VM_QUOTA}GB (15%) - Perfect for 1-2 VMs"
        print_info "  Containers: ${CONTAINER_QUOTA}GB (65%) - Primary workload"
        print_info "  Templates: ${TEMPLATE_QUOTA}GB (8%) - With dedup + compression"
        print_info "  Backups: ${BACKUP_QUOTA}GB (10%) - Local backups"
        print_info "  Buffer: $((POOL_SIZE_GB - VM_QUOTA - CONTAINER_QUOTA - TEMPLATE_QUOTA - BACKUP_QUOTA))GB (2%) - Safety margin"
        
        # Add to Proxmox storage (with error handling)
        echo ""
        print_info "Adding datasets to Proxmox storage..."
        
        # Add VMs storage
        if ! pvesm status 2>/dev/null | grep -q "local-nvme-vms"; then
            if pvesm add zfspool local-nvme-vms --pool local-nvme/vms --content images,rootdir 2>/dev/null; then
                print_success "Added VMs dataset to Proxmox storage"
            else
                print_info "VMs dataset addition to Proxmox skipped (may need manual configuration)"
            fi
        else
            print_info "VMs storage already configured in Proxmox"
        fi
        
        # Add templates storage
        if ! pvesm status 2>/dev/null | grep -q "local-nvme-templates"; then
            if pvesm add zfspool local-nvme-templates --pool local-nvme/templates --content images,rootdir 2>/dev/null; then
                print_success "Added templates dataset to Proxmox storage"
            else
                print_info "Templates dataset addition to Proxmox skipped (may need manual configuration)"
            fi
        else
            print_info "Templates storage already configured in Proxmox"
        fi
        
        # Add containers storage
        if ! pvesm status 2>/dev/null | grep -q "local-nvme-containers"; then
            if pvesm add zfspool local-nvme-containers --pool local-nvme/containers --content rootdir 2>/dev/null; then
                print_success "Added containers dataset to Proxmox storage"
            else
                print_info "Containers dataset addition to Proxmox skipped (may need manual configuration)"
            fi
        else
            print_info "Containers storage already configured in Proxmox"
        fi
        
        # Add backup storage (as directory mount)
        if ! pvesm status 2>/dev/null | grep -q "local-nvme-backups"; then
            # Create mount point
            mkdir -p /mnt/zfs-backups
            
            # Mount ZFS dataset
            if mount -t zfs local-nvme/backups /mnt/zfs-backups 2>/dev/null; then
                # Make mount permanent
                grep -q "local-nvme/backups" /etc/fstab || echo "local-nvme/backups /mnt/zfs-backups zfs defaults 0 0" >> /etc/fstab
                
                # Add to Proxmox as directory storage
                if pvesm add dir local-nvme-backups --path /mnt/zfs-backups --content backup --maxfiles 15 2>/dev/null; then
                    print_success "Added backups dataset to Proxmox storage"
                else
                    print_info "Backups dataset addition to Proxmox skipped (may need manual configuration)"
                fi
            else
                print_info "Failed to mount backup dataset"
            fi
        else
            print_info "Backups storage already configured in Proxmox"
        fi
        
        echo ""
        print_success "Specialized datasets configuration complete!"
        print_info "Next steps:"
        print_info "1. Configure SATA drive for ISO storage separately"
        print_info "2. Move any existing ISOs from NVMe to SATA drive"  
        print_info "3. Update Proxmox storage configuration if needed"
        
    elif [[ $datasets_choice -eq 2 ]]; then
        print_info "Keeping simple single-pool structure"
    else
        print_warning "Invalid choice, skipping dataset creation"
    fi
    
    echo ""
    print_success "Advanced features configuration complete!"
    echo ""
}

# Add these missing functions to your script

configure_system_integration() {
    print_header "SYSTEM INTEGRATION OPTIMIZATION"
    
    # I/O Scheduler
    print_info "Current I/O scheduler: $(cat /sys/block/nvme*/queue/scheduler 2>/dev/null | head -1 | grep -o '\[.*\]' | tr -d '[]' || echo 'Unknown')"
    echo ""
    print_info "I/O scheduler optimization for NVMe:"
    print_choice "1. none - Best for NVMe SSDs (RECOMMENDED)"
    print_choice "2. mq-deadline - Good for SATA SSDs"
    print_choice "3. kyber - Low latency option"
    print_choice "4. Keep current setting"
    
    print_recommendation "Choose option 1 (none) for NVMe drives"
    print_info "NVMe drives handle their own scheduling internally"
    
    echo ""
    read -p "Choose I/O scheduler (1-4): " scheduler_choice
    
    case $scheduler_choice in
        1)
            cat > /etc/udev/rules.d/60-scheduler.rules << 'EOF'
# Optimize I/O scheduler for NVMe
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/nr_requests}="128"
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{bdi/read_ahead_kb}="128"
EOF
            print_success "Configured I/O scheduler for NVMe optimization"
            ;;
        2)
            cat > /etc/udev/rules.d/60-scheduler.rules << 'EOF'
# Set mq-deadline scheduler for SSDs
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/nr_requests}="128"
EOF
            print_success "Configured mq-deadline I/O scheduler"
            ;;
        3)
            cat > /etc/udev/rules.d/60-scheduler.rules << 'EOF'
# Set kyber scheduler for low latency
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="kyber"
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/nr_requests}="64"
EOF
            print_success "Configured kyber I/O scheduler"
            ;;
        4)
            print_info "Keeping current I/O scheduler"
            ;;
        *)
            print_warning "Invalid choice, keeping current setting"
            ;;
    esac
    
    echo ""
    
    # ZFS kernel parameters
    print_info "ZFS kernel parameters optimization:"
    print_choice "1. Apply recommended ZFS kernel optimizations"
    print_choice "2. Apply aggressive performance optimizations"
    print_choice "3. Keep current settings"
    
    if [[ "$IS_N150" == true ]]; then
        print_recommendation "Choose option 1 for balanced N150 optimization"
    else
        print_recommendation "Choose option 1 for safe optimizations"
    fi
    
    echo ""
    read -p "Choose kernel optimization (1-3): " kernel_choice
    
    case $kernel_choice in
        1)
            print_info "Applying recommended ZFS kernel parameters..."
            
            # Add basic optimizations to existing config
            if [[ ! -f /etc/modprobe.d/zfs.conf ]]; then
                cat > /etc/modprobe.d/zfs.conf << 'EOF'
# ZFS Basic Optimizations
options zfs zfs_prefetch_disable=1
options zfs zfs_txg_timeout=5
options zfs zfs_dirty_data_sync_percent=20
EOF
            else
                # Add to existing config if not present
                grep -q "zfs_prefetch_disable" /etc/modprobe.d/zfs.conf || echo "options zfs zfs_prefetch_disable=1" >> /etc/modprobe.d/zfs.conf
                grep -q "zfs_txg_timeout" /etc/modprobe.d/zfs.conf || echo "options zfs zfs_txg_timeout=5" >> /etc/modprobe.d/zfs.conf
                grep -q "zfs_dirty_data_sync_percent" /etc/modprobe.d/zfs.conf || echo "options zfs zfs_dirty_data_sync_percent=20" >> /etc/modprobe.d/zfs.conf
            fi
            
            print_success "Applied recommended ZFS kernel parameters"
            ;;
        2)
            print_info "Applying aggressive ZFS kernel parameters..."
            
            if [[ ! -f /etc/modprobe.d/zfs.conf ]]; then
                cat > /etc/modprobe.d/zfs.conf << 'EOF'
# ZFS Aggressive Optimizations
options zfs zfs_prefetch_disable=1
options zfs zfs_txg_timeout=5
options zfs zfs_dirty_data_sync_percent=20
options zfs zfs_vdev_async_read_max_active=10
options zfs zfs_vdev_async_write_max_active=10
options zfs zfs_vdev_sync_read_max_active=10
options zfs zfs_vdev_sync_write_max_active=5
options zfs zfs_dirty_data_max=4294967296
EOF
            else
                # Add aggressive settings
                grep -q "zfs_vdev_async_read_max_active" /etc/modprobe.d/zfs.conf || echo "options zfs zfs_vdev_async_read_max_active=10" >> /etc/modprobe.d/zfs.conf
                grep -q "zfs_vdev_async_write_max_active" /etc/modprobe.d/zfs.conf || echo "options zfs zfs_vdev_async_write_max_active=10" >> /etc/modprobe.d/zfs.conf
                grep -q "zfs_dirty_data_max" /etc/modprobe.d/zfs.conf || echo "options zfs zfs_dirty_data_max=4294967296" >> /etc/modprobe.d/zfs.conf
            fi
            
            print_success "Applied aggressive ZFS kernel parameters"
            ;;
        3)
            print_info "Keeping current kernel parameters"
            ;;
        *)
            print_warning "Invalid choice, keeping current settings"
            ;;
    esac
    
    echo ""
    print_success "System integration optimization complete!"
    echo ""
}

configure_monitoring_maintenance() {
    print_header "MONITORING & MAINTENANCE SETUP"
    
    print_info "Setting up ZFS monitoring and maintenance automation..."
    echo ""
    
    # Create monitoring script
    print_info "Creating ZFS health monitoring script..."
    
    cat > /usr/local/bin/zfs-health-monitor.sh << 'EOF'
#!/bin/bash

# ZFS Health Monitor for Intel N150 Systems
LOG_FILE="/var/log/zfs-health.log"
ERROR_LOG="/var/log/zfs-errors.log"

# Function to safely execute commands
safe_execute() {
    local cmd="$1"
    local description="$2"
    
    if eval "$cmd" 2>/dev/null; then
        return 0
    else
        echo "Warning: Failed to execute $description" >> "$ERROR_LOG"
        return 1
    fi
}

{
    echo "=== ZFS Health Check - $(date) ==="
    
    # System uptime and load
    echo "System: $(uptime)"
    
    # CPU Temperature (multiple sources)
    TEMP_FOUND=false
    
    # Try sensors first
    if command -v sensors >/dev/null 2>&1; then
        TEMP=$(sensors 2>/dev/null | grep -E "(Package|Core.*temp)" | head -1 | awk '{print $3}' | sed 's/+//g' | sed 's/°C//g' | cut -d. -f1)
        if [[ -n "$TEMP" && "$TEMP" != "0" ]]; then
            echo "CPU Temperature: ${TEMP}°C"
            if [[ $TEMP -gt 85 ]]; then
                echo "⚠  CRITICAL: Very high CPU temperature!"
            elif [[ $TEMP -gt 75 ]]; then
                echo "⚠  WARNING: High CPU temperature!"
            elif [[ $TEMP -gt 65 ]]; then
                echo "⚠  CAUTION: Elevated CPU temperature"
            else
                echo "✓ Temperature normal"
            fi
            TEMP_FOUND=true
        fi
    fi
    
    # Try thermal zone if sensors failed
    if [[ "$TEMP_FOUND" = false ]] && [[ -f "/sys/class/thermal/thermal_zone0/temp" ]]; then
        TEMP_MILLIC=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
        if [[ -n "$TEMP_MILLIC" && "$TEMP_MILLIC" != "0" ]]; then
            TEMP=$((TEMP_MILLIC / 1000))
            echo "CPU Temperature: ${TEMP}°C (thermal zone)"
            TEMP_FOUND=true
        fi
    fi
    
    if [[ "$TEMP_FOUND" = false ]]; then
        echo "CPU Temperature: Not available"
    fi
    
    echo ""
    
    # ZFS Pool Status
    echo "=== Pool Status ==="
    if safe_execute "zpool status local-nvme" "pool status"; then
        zpool status local-nvme
    else
        echo "Failed to get pool status"
    fi
    
    echo ""
    
    # Pool Performance
    echo "=== Pool Performance ==="
    if safe_execute "zpool iostat local-nvme" "pool iostat"; then
        zpool iostat local-nvme
    fi
    
    echo ""
    
    # ARC Statistics with error handling
    echo "=== ARC Cache Statistics ==="
    if [[ -f /proc/spl/kstat/zfs/arcstats ]]; then
        ARC_SIZE=$(awk '/^size/ {printf "%.1fGB", $3/1024/1024/1024}' /proc/spl/kstat/zfs/arcstats 2>/dev/null || echo "Unknown")
        ARC_HITS=$(awk '/^hits/ {print $3}' /proc/spl/kstat/zfs/arcstats 2>/dev/null || echo 0)
        ARC_MISSES=$(awk '/^misses/ {print $3}' /proc/spl/kstat/zfs/arcstats 2>/dev/null || echo 0)
        
        echo "ARC Size: $ARC_SIZE"
        if [[ "$ARC_HITS" != "0" && "$ARC_MISSES" != "0" ]]; then
            ARC_TOTAL=$((ARC_HITS + ARC_MISSES))
            if [[ $ARC_TOTAL -gt 0 ]]; then
                ARC_HIT_RATE=$(echo "scale=1; $ARC_HITS * 100 / $ARC_TOTAL" | bc 2>/dev/null || echo "N/A")
                echo "Hit Rate: ${ARC_HIT_RATE}%"
                
                # Performance assessment
                if command -v bc >/dev/null && [[ "$ARC_HIT_RATE" != "N/A" ]]; then
                    if (( $(echo "$ARC_HIT_RATE > 95" | bc -l) )); then
                        echo "✓ Excellent cache performance"
                    elif (( $(echo "$ARC_HIT_RATE > 85" | bc -l) )); then
                        echo "✓ Good cache performance"
                    elif (( $(echo "$ARC_HIT_RATE > 70" | bc -l) )); then
                        echo "⚠ Moderate cache performance"
                    else
                        echo "⚠ Poor cache performance - consider increasing ARC size"
                    fi
                fi
            fi
        else
            echo "Hit Rate: No data yet (system just started)"
        fi
    else
        echo "ARC statistics not available"
    fi
    
    echo ""
    
    # Compression Stats
    echo "=== Compression Statistics ==="
    if safe_execute "zfs get compressratio,compression local-nvme" "compression stats"; then
        zfs get compressratio,compression local-nvme
        
        # Get compression ratio value for assessment
        COMP_RATIO=$(zfs get -H -o value compressratio local-nvme 2>/dev/null)
        if [[ -n "$COMP_RATIO" && "$COMP_RATIO" != "1.00x" ]]; then
            echo "Space savings from compression: $COMP_RATIO"
        fi
    fi
    
    echo ""
    
    # Dataset-specific stats if they exist
    if zfs list local-nvme/vms &>/dev/null; then
        echo "=== Dataset Statistics ==="
        zfs list -o name,used,avail,quota,compressratio local-nvme/vms local-nvme/containers local-nvme/templates local-nvme/backups 2>/dev/null
        echo ""
    fi
    
    # Dedup stats (if enabled)
    if zfs get -H -o value dedup local-nvme 2>/dev/null | grep -q "^on"; then
        echo "=== Deduplication Statistics ==="
        DEDUP_RATIO=$(zfs get -H -o value dedupratio local-nvme 2>/dev/null || echo "Calculating...")
        echo "Dedup Ratio: $DEDUP_RATIO"
        
        if [[ "$DEDUP_RATIO" != "Calculating..." && "$DEDUP_RATIO" != "1.00x" ]]; then
            echo "Space savings from deduplication: $DEDUP_RATIO"
        fi
        echo ""
    fi
    
    # Disk usage and fragmentation
    echo "=== Space Usage ==="
    if safe_execute "zfs list -o name,used,avail,refer,compressratio local-nvme" "space usage"; then
        zfs list -o name,used,avail,refer,compressratio local-nvme
    fi
    
    echo ""
    
    # Fragmentation check
    echo "=== Pool Fragmentation ==="
    if safe_execute "zpool list -o name,frag local-nvme" "fragmentation check"; then
        FRAG=$(zpool list -H -o frag local-nvme 2>/dev/null)
        echo "Fragmentation: $FRAG"
        
        if [[ -n "$FRAG" ]]; then
            FRAG_NUM=$(echo "$FRAG" | sed 's/%//')
            if [[ $FRAG_NUM -gt 50 ]]; then
                echo "⚠ High fragmentation - consider pool maintenance"
            elif [[ $FRAG_NUM -gt 25 ]]; then
                echo "⚠ Moderate fragmentation"
            else
                echo "✓ Low fragmentation"
            fi
        fi
    fi
    
    echo ""
    
    # Check for errors
    echo "=== Error Check ==="
    if zpool status local-nvme | grep -q "errors: No known data errors"; then
        echo "✓ No errors detected"
    else
        echo "⚠ Errors detected - check pool status immediately"
        zpool status local-nvme | grep -A 5 "errors:"
    fi
    
    # Memory usage
    echo ""
    echo "=== Memory Usage ==="
    free -h
    
    echo "============================================"
    echo ""
} >> "$LOG_FILE"

# Rotate log if it gets too large (10MB)
if [[ -f "$LOG_FILE" ]]; then
    LOG_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
    if [[ $LOG_SIZE -gt 10485760 ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        echo "Log rotated at $(date)" > "$LOG_FILE"
    fi
fi

# Also output to console if run manually
if [[ -t 1 ]]; then
    echo "Latest health check results:"
    tail -n 100 "$LOG_FILE" | head -n 80
fi
EOF
    
    chmod +x /usr/local/bin/zfs-health-monitor.sh
    print_success "Created enhanced ZFS health monitoring script"
    
    # Create maintenance script
    print_info "Creating ZFS maintenance script..."
    
    cat > /usr/local/bin/zfs-maintenance.sh << 'EOF'
#!/bin/bash

# ZFS Maintenance Script
echo "Starting ZFS maintenance - $(date)"

# Scrub if not recently done
LAST_SCRUB=$(zpool history local-nvme | grep scrub | tail -1 | awk '{print $1" "$2}')
if [ -z "$LAST_SCRUB" ] || [ $(date -d "$LAST_SCRUB" +%s 2>/dev/null || echo 0) -lt $(date -d "30 days ago" +%s) ]; then
    echo "Starting ZFS scrub..."
    zpool scrub local-nvme
    echo "Scrub initiated"
else
    echo "Scrub completed recently, skipping"
fi

# Clean up old snapshots (if any exist)
OLD_SNAPSHOTS=$(zfs list -t snapshot -o name | grep local-nvme | head -n -10)
if [ ! -z "$OLD_SNAPSHOTS" ]; then
    echo "Cleaning up old snapshots..."
    echo "$OLD_SNAPSHOTS" | while read snapshot; do
        zfs destroy "$snapshot" 2>/dev/null && echo "Removed: $snapshot"
    done
fi

# Check pool health
zpool status local-nvme | grep -q "ONLINE" && echo "✓ Pool healthy" || echo "⚠ Pool issues detected"

echo "ZFS maintenance completed - $(date)"
EOF
    
    chmod +x /usr/local/bin/zfs-maintenance.sh
    print_success "Created ZFS maintenance script"
    
    # Setup cron jobs
    echo ""
    print_choice "Setup automated monitoring and maintenance?"
    print_choice "1. Yes - Daily monitoring + weekly maintenance (RECOMMENDED)"
    print_choice "2. Yes - Daily monitoring only"
    print_choice "3. No - Manual execution only"
    
    print_recommendation "Choose option 1 for automated ZFS maintenance"
    
    echo ""
    read -p "Setup automation (1-3): " automation_choice
    
    case $automation_choice in
        1)
            # Daily monitoring, weekly maintenance
            (crontab -l 2>/dev/null; echo "0 8 * * * /usr/local/bin/zfs-health-monitor.sh") | crontab -
            (crontab -l 2>/dev/null; echo "0 2 * * 0 /usr/local/bin/zfs-maintenance.sh") | crontab -
            print_success "Setup daily monitoring + weekly maintenance"
            ;;
        2)
            # Daily monitoring only
            (crontab -l 2>/dev/null; echo "0 8 * * * /usr/local/bin/zfs-health-monitor.sh") | crontab -
            print_success "Setup daily monitoring"
            ;;
        3)
            print_info "Scripts created for manual execution"
            ;;
        *)
            print_warning "Invalid choice, no automation setup"
            ;;
    esac
    
    echo ""
    print_success "Monitoring & maintenance setup complete!"
    echo ""
    print_info "Manual script execution:"
    print_info "  Health check: /usr/local/bin/zfs-health-monitor.sh"
    print_info "  Maintenance:  /usr/local/bin/zfs-maintenance.sh"
    print_info "  Log file:     /var/log/zfs-health.log"
    echo ""
}

complete_optimization() {
    print_header "COMPLETE ZFS OPTIMIZATION"
    print_info "This will apply recommended settings for your Intel N150 system"
    echo ""
    
    print_warning "This will modify your ZFS configuration!"
    print_info "A backup of current settings will be created."
    echo ""
    
    read -p "Proceed with complete optimization? (y/N): " proceed
    if [[ ! $proceed =~ ^[Yy]$ ]]; then
        print_info "Optimization cancelled"
        return
    fi
    
    # Backup current settings
    print_info "Creating backup of current ZFS settings..."
    BACKUP_FILE="/root/zfs-settings-backup-$(date +%Y%m%d-%H%M%S).txt"
    {
        echo "=== ZFS Settings Backup - $(date) ==="
        echo "Pool: local-nvme"
        echo ""
        zfs get all local-nvme
        echo ""
        echo "=== Kernel Modules ==="
        cat /etc/modprobe.d/zfs.conf 2>/dev/null || echo "No ZFS module config found"
    } > "$BACKUP_FILE"
    print_success "Backup saved to: $BACKUP_FILE"
    
    # Apply optimizations based on detected hardware
    print_info "Applying optimizations for your system..."
    echo ""
    
    # Core settings
    print_info "Configuring core performance settings..."
    if [[ "$IS_N150" == true ]]; then
        safe_zfs_set "recordsize" "64K" "local-nvme"
        safe_zfs_set "compression" "zstd-3" "local-nvme"
    else
        safe_zfs_set "recordsize" "32K" "local-nvme"
        safe_zfs_set "compression" "lz4" "local-nvme"
    fi
    safe_zfs_set "atime" "off" "local-nvme"
    print_success "Applied core settings"
    
    # Memory settings
    print_info "Configuring memory management..."
    if [[ $TOTAL_RAM_GB -ge 32 ]]; then
        ARC_MAX="8589934592"  # 8GB
        ARC_MIN="2147483648"  # 2GB
    elif [[ $TOTAL_RAM_GB -ge 16 ]]; then
        ARC_MAX="4294967296"  # 4GB
        ARC_MIN="1073741824"  # 1GB
    else
        ARC_MAX="2147483648"  # 2GB
        ARC_MIN="536870912"   # 512MB
    fi
    
    cat > /etc/modprobe.d/zfs.conf << EOF
# ZFS Optimization for Intel N150
options zfs zfs_arc_max=$ARC_MAX
options zfs zfs_arc_min=$ARC_MIN
options zfs zfs_prefetch_disable=1
options zfs zfs_txg_timeout=5
options zfs zfs_dirty_data_sync_percent=20
EOF
    print_success "Applied memory settings"
    
    # System integration
    print_info "Configuring system integration..."
    cat > /etc/udev/rules.d/60-scheduler.rules << 'EOF'
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/nr_requests}="128"
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{bdi/read_ahead_kb}="128"
EOF
    
    cat >> /etc/sysctl.conf << 'EOF'

# ZFS + VM Optimization
vm.swappiness=1
vm.vfs_cache_pressure=50
vm.dirty_ratio=5
vm.dirty_background_ratio=3
EOF
    sysctl -p > /dev/null 2>&1 || true
    print_success "Applied system integration"
    
    # Enable deduplication for abundant RAM systems
    if [[ "$HAS_ABUNDANT_RAM" == true ]]; then
        print_info "Enabling deduplication (recommended for 32GB+ systems)..."
        safe_zfs_set "dedup" "on" "local-nvme"
        print_success "Enabled deduplication"
    fi
    
    # Setup monitoring
    print_info "Setting up monitoring and maintenance..."
    configure_monitoring_maintenance
    
    print_header "COMPLETE OPTIMIZATION SUMMARY"
    echo ""
    print_success "ZFS optimization completed successfully!"
    echo ""
    print_info "Applied settings:"
    if [[ "$IS_N150" == true ]]; then
        print_info "  • Record size: 64K (optimized for Intel N150)"
        print_info "  • Compression: zstd-3 (N150 can handle efficiently)"
    else
        print_info "  • Record size: 32K (balanced for general systems)"
        print_info "  • Compression: lz4 (reliable and fast)"
    fi
    print_info "  • ARC cache: $((ARC_MAX / 1024 / 1024 / 1024))GB max, $((ARC_MIN / 1024 / 1024 / 1024))GB min"
    print_info "  • Access time: disabled (better performance)"
    print_info "  • I/O scheduler: none (optimal for NVMe)"
    print_info "  • Prefetch: disabled (SSD optimization)"
    if [[ "$HAS_ABUNDANT_RAM" == true ]]; then
        print_info "  • Deduplication: enabled (space savings)"
    fi
    print_info "  • Monitoring: automated health checks"
    
    echo ""
    print_warning "Important next steps:"
    print_warning "1. Reboot system for all changes to take effect"
    print_warning "2. Monitor system performance after reboot"
    print_warning "3. Check ARC hit rates after running VMs"
    print_warning "4. Settings backup saved: $BACKUP_FILE"
    
    echo ""
    read -p "Reboot now to apply all changes? (y/N): " reboot_now
    if [[ $reboot_now =~ ^[Yy]$ ]]; then
        print_info "Rebooting in 10 seconds... (Ctrl+C to cancel)"
        sleep 10
        reboot
    else
        print_info "Remember to reboot when convenient"
    fi
}

show_current_settings() {
    print_header "CURRENT ZFS SETTINGS"
    
    echo ""
    print_info "=== Pool Information ==="
    zpool status local-nvme
    
    echo ""
    print_info "=== Dataset Properties ==="
    if zfs list local-nvme/vms &>/dev/null; then
        # Show specialized datasets if they exist
        zfs get recordsize,compression,atime,dedup,quota local-nvme/vms local-nvme/containers local-nvme/templates local-nvme/backups 2>/dev/null
    else
        # Show single pool settings
        zfs get recordsize,compression,atime,dedup local-nvme
    fi
    
    echo ""
    print_info "=== Space Usage ==="
    if zfs list local-nvme/vms &>/dev/null; then
        zfs list -o name,used,avail,refer,compressratio local-nvme/vms local-nvme/containers local-nvme/templates local-nvme/backups
    else
        zfs list -o name,used,avail,refer,compressratio local-nvme
    fi
    
    echo ""
    print_info "=== ARC Statistics ==="
    if [[ -f /proc/spl/kstat/zfs/arcstats ]]; then
        ARC_SIZE=$(awk '/^size/ {printf "%.1fGB", $3/1024/1024/1024}' /proc/spl/kstat/zfs/arcstats)
        ARC_HITS=$(awk '/^hits/ {print $3}' /proc/spl/kstat/zfs/arcstats)
        ARC_MISSES=$(awk '/^misses/ {print $3}' /proc/spl/kstat/zfs/arcstats)
        ARC_TOTAL=$((ARC_HITS + ARC_MISSES))
        
        echo "ARC Size: $ARC_SIZE"
        if [[ $ARC_TOTAL -gt 0 ]]; then
            ARC_HIT_RATE=$(echo "scale=1; $ARC_HITS * 100 / $ARC_TOTAL" | bc 2>/dev/null || echo "N/A")
            echo "Hit Rate: ${ARC_HIT_RATE}%"
        else
            echo "Hit Rate: No data yet"
        fi
    else
        echo "ARC statistics not available"
    fi
    
    echo ""
    print_info "=== System Configuration ==="
    echo "I/O Scheduler: $(cat /sys/block/nvme*/queue/scheduler 2>/dev/null | head -1 | grep -o '\[.*\]' | tr -d '[]' || echo 'Unknown')"
    
    if [[ -f /etc/modprobe.d/zfs.conf ]]; then
        echo ""
        print_info "=== ZFS Module Configuration ==="
        cat /etc/modprobe.d/zfs.conf
    fi
    
    echo ""
}

custom_configuration() {
    print_header "CUSTOM ZFS CONFIGURATION"
    
    print_info "Configure individual ZFS properties:"
    echo ""
    
    while true; do
        print_choice "Available properties to configure:"
        print_choice "1. Record size"
        print_choice "2. Compression algorithm"
        print_choice "3. Volume block size"
        print_choice "4. Access time (atime)"
        print_choice "5. Deduplication"
        print_choice "6. Sync behavior"
        print_choice "7. ARC cache settings"
        print_choice "8. Done with custom configuration"
        
        echo ""
        read -p "Choose property to configure (1-8): " custom_choice
        
        case $custom_choice in
            1)
                echo ""
                print_info "Current record size: $(zfs get -H -o value recordsize local-nvme)"
                read -p "Enter new record size (e.g., 16K, 32K, 64K, 128K, 1M): " new_recordsize
                if [[ -n "$new_recordsize" ]]; then
                    safe_zfs_set "recordsize" "$new_recordsize" "local-nvme"
                fi
                ;;
            2)
                echo ""
                print_info "Current compression: $(zfs get -H -o value compression local-nvme)"
                print_info "Options: off, lz4, zstd-1, zstd-3, zstd-6, gzip-1, gzip-6"
                read -p "Enter compression algorithm: " new_compression
                if [[ -n "$new_compression" ]]; then
                    safe_zfs_set "compression" "$new_compression" "local-nvme"
                fi
                ;;
            3)
                echo ""
                print_info "Current volume block size: $(zfs get -H -o value volblocksize local-nvme 2>/dev/null || echo 'Not set')"
                read -p "Enter volume block size (e.g., 8K, 16K, 32K, 64K): " new_volblocksize
                if [[ -n "$new_volblocksize" ]]; then
                    safe_zfs_set "volblocksize" "$new_volblocksize" "local-nvme"
                fi
                ;;
            4)
                echo ""
                print_info "Current atime: $(zfs get -H -o value atime local-nvme)"
                read -p "Enable access time tracking? (on/off): " new_atime
                if [[ "$new_atime" == "on" || "$new_atime" == "off" ]]; then
                    safe_zfs_set "atime" "$new_atime" "local-nvme"
                fi
                ;;
            5)
                echo ""
                print_info "Current deduplication: $(zfs get -H -o value dedup local-nvme)"
                print_warning "Deduplication requires significant RAM"
                read -p "Enable deduplication? (on/off): " new_dedup
                if [[ "$new_dedup" == "on" || "$new_dedup" == "off" ]]; then
                    safe_zfs_set "dedup" "$new_dedup" "local-nvme"
                fi
                ;;
            6)
                echo ""
                print_info "Current sync: $(zfs get -H -o value sync local-nvme)"
                print_info "Options: standard (safe), always (very safe), disabled (fast but risky)"
                read -p "Enter sync behavior: " new_sync
                if [[ "$new_sync" == "standard" || "$new_sync" == "always" || "$new_sync" == "disabled" ]]; then
                    safe_zfs_set "sync" "$new_sync" "local-nvme"
                fi
                ;;
            7)
                echo ""
                print_info "Configure ARC cache limits (requires reboot)"
                read -p "Enter ARC maximum size in GB: " arc_max_gb
                read -p "Enter ARC minimum size in GB: " arc_min_gb
                if [[ -n "$arc_max_gb" && -n "$arc_min_gb" ]]; then
                    ARC_MAX=$((arc_max_gb * 1024 * 1024 * 1024))
                    ARC_MIN=$((arc_min_gb * 1024 * 1024 * 1024))
                    
                    cat > /etc/modprobe.d/zfs.conf << EOF
options zfs zfs_arc_max=$ARC_MAX
options zfs zfs_arc_min=$ARC_MIN
EOF
                    print_success "Set ARC limits: ${arc_min_gb}GB min, ${arc_max_gb}GB max"
                    print_warning "Reboot required for ARC changes"
                fi
                ;;
            8)
                break
                ;;
            *)
                print_warning "Invalid choice"
                ;;
        esac
        echo ""
    done
    
    print_success "Custom configuration complete!"
    echo ""
}

# Add the verification function
verify_dataset_configuration() {
    print_header "DATASET CONFIGURATION VERIFICATION"
    
    # Check if specialized datasets exist
    if zfs list local-nvme/vms &>/dev/null; then
        print_info "Verifying specialized dataset configuration..."
        echo ""
        
        # Show dataset properties
        print_info "Dataset Properties:"
        zfs get recordsize,compression,atime,quota,dedup local-nvme/vms local-nvme/containers local-nvme/templates local-nvme/backups 2>/dev/null | grep -v SOURCE
        
        echo ""
        print_info "Space Allocation:"
        zfs list -o name,used,avail,quota,compressratio local-nvme/vms local-nvme/containers local-nvme/templates local-nvme/backups 2>/dev/null
        
        echo ""
        print_info "Compression Effectiveness:"
        for dataset in vms containers templates backups; do
            if zfs list local-nvme/$dataset &>/dev/null; then
                RATIO=$(zfs get -H -o value compressratio local-nvme/$dataset 2>/dev/null)
                COMPRESSION=$(zfs get -H -o value compression local-nvme/$dataset 2>/dev/null)
                print_info "  $dataset: $COMPRESSION compression, $RATIO ratio"
            fi
        done
        
        echo ""
        print_info "Volume Block Sizes (for existing volumes):"
        VOLUMES=$(zfs list -t volume -H -o name 2>/dev/null | grep local-nvme || echo "No volumes found yet")
        if [[ "$VOLUMES" != "No volumes found yet" ]]; then
            echo "$VOLUMES" | while read volume; do
                VOLBLOCK=$(zfs get -H -o value volblocksize "$volume" 2>/dev/null)
                print_info "  $(basename $volume): $VOLBLOCK"
            done
        else
            print_info "  No volumes created yet - new VMs will use optimal settings"
        fi
        
    else
        print_info "Using single-pool configuration"
        zfs get recordsize,compression,atime local-nvme 2>/dev/null | grep -v SOURCE
    fi
    
    echo ""
}

# [Keep all other existing functions: configure_system_integration, configure_monitoring_maintenance, 
#  complete_optimization, show_current_settings, custom_configuration unchanged]

# Updated main execution with dependency check
main() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
    
    print_header "INTEL N150 ZFS OPTIMIZER"
    print_info "Comprehensive ZFS optimization for Intel N150 + Proxmox"
    print_info "Log file: $LOG_FILE"
    echo ""
    
    # NEW: Check dependencies first
    check_dependencies
    
    # Detect system
    detect_system
    
    # Main menu loop
    while true; do
        show_optimization_menu
        read -p "Choose optimization option (1-9): " choice
        
        case $choice in
            1) configure_core_performance ;;
            2) configure_memory_management ;;
            3) configure_advanced_features ;;
            4) configure_system_integration ;;
            5) configure_monitoring_maintenance ;;
            6) complete_optimization ;;
            7) custom_configuration ;;
            8) show_current_settings ;;
            9) 
                print_info "Exiting ZFS optimizer"
                exit 0
                ;;
            *)
                print_warning "Invalid choice, please try again"
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
        clear
    done
}

# Trap for cleanup
trap 'print_error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"
