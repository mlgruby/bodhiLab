# Update package list first:
apt update

# Install hardware monitoring:
apt install -y lm-sensors
sensors-detect --auto    # Auto-detect sensors

# Install ZFS monitoring tools:
apt install -y zfs-zed          # ZFS Event Daemon
apt install -y sanoid           # ZFS snapshot management (optional)

# Install performance testing:
apt install -y fio              # Storage benchmarking
apt install -y sysbench         # System benchmarking
apt install -y iotop            # I/O monitoring
apt install -y htop             # Process monitoring

# Install system utilities:
apt install -y bc               # Calculator for scripts
apt install -y sysstat          # System statistics (iostat, etc.)
apt install -y smartmontools    # Drive health monitoring
