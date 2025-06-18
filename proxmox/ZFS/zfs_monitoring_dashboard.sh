# Create a comprehensive status command:
cat > /usr/local/bin/zfs-dashboard.sh << 'EOF'
#!/bin/bash
clear
echo "=============================="
echo "ZFS SYSTEM DASHBOARD - $(date)"
echo "=============================="
echo ""

# Temperature
if command -v sensors >/dev/null; then
    TEMP=$(sensors 2>/dev/null | grep -E "(Package|Core.*temp)" | head -1 | awk '{print $3}' | sed 's/+//g' | sed 's/°C//g' | cut -d. -f1)
    if [[ -n "$TEMP" ]]; then
        if [[ $TEMP -gt 75 ]]; then
            echo "🌡️  CPU Temp: ${TEMP}°C ⚠️  HIGH"
        else
            echo "🌡️  CPU Temp: ${TEMP}°C ✓"
        fi
    fi
fi

# Pool Status
echo "💾 Pool Status: $(zpool list -H -o health local-nvme)"
echo "📊 Pool Usage: $(zpool list -H -o cap local-nvme) of $(zpool list -H -o size local-nvme)"

# ARC Stats
ARC_SIZE=$(awk '/^size/ {printf "%.1fGB", $3/1024/1024/1024}' /proc/spl/kstat/zfs/arcstats 2>/dev/null || echo "0GB")
ARC_HITS=$(awk '/^hits/ {print $3}' /proc/spl/kstat/zfs/arcstats 2>/dev/null || echo 0)
ARC_MISSES=$(awk '/^misses/ {print $3}' /proc/spl/kstat/zfs/arcstats 2>/dev/null || echo 0)
ARC_TOTAL=$((ARC_HITS + ARC_MISSES))
if [[ $ARC_TOTAL -gt 0 ]]; then
    ARC_RATE=$(echo "scale=1; $ARC_HITS * 100 / $ARC_TOTAL" | bc 2>/dev/null || echo "0")
    echo "🎯 ARC Cache: ${ARC_SIZE} (${ARC_RATE}% hit rate)"
else
    echo "🎯 ARC Cache: ${ARC_SIZE} (no activity yet)"
fi

echo ""
echo "📁 DATASET USAGE:"
printf "%-12s %8s %8s %8s %s\n" "Dataset" "Used" "Avail" "Quota" "Usage%"
echo "----------------------------------------"

for dataset in vms containers templates backups; do
    if zfs list local-nvme/$dataset &>/dev/null; then
        used=$(zfs get -H -o value used local-nvme/$dataset)
        avail=$(zfs get -H -o value avail local-nvme/$dataset)
        quota=$(zfs get -H -o value quota local-nvme/$dataset)
        
        # Calculate percentage if quota is set
        if [[ "$quota" != "-" ]]; then
            used_num=$(echo $used | sed 's/[^0-9.]//g')
            quota_num=$(echo $quota | sed 's/[^0-9.]//g')
            percent=$(echo "scale=1; $used_num * 100 / $quota_num" | bc 2>/dev/null || echo "0")
            printf "%-12s %8s %8s %8s %s%%\n" "$dataset" "$used" "$avail" "$quota" "$percent"
        else
            printf "%-12s %8s %8s %8s %s\n" "$dataset" "$used" "$avail" "$quota" "N/A"
        fi
    fi
done

echo ""
echo "🔄 COMPRESSION RATIOS:"
for dataset in vms containers templates backups; do
    if zfs list local-nvme/$dataset &>/dev/null; then
        ratio=$(zfs get -H -o value compressratio local-nvme/$dataset)
        compression=$(zfs get -H -o value compression local-nvme/$dataset)
        printf "%-12s: %-8s (%s)\n" "$dataset" "$ratio" "$compression"
    fi
done

echo ""
echo "Run 'zfs-dashboard.sh' anytime for this overview"
EOF

chmod +x /usr/local/bin/zfs-dashboard.sh
