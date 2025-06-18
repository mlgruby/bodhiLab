# Proxmox Storage Strategy Guide

## 📋 Overview

This guide provides a comprehensive storage strategy for a 3-node Proxmox cluster using local NVMe ZFS pools and shared NAS storage. The approach maximizes performance while maintaining flexibility and redundancy.

## 🏗️ Architecture Overview

### Hardware Configuration
```
Node 1: Intel N100 + 931GB NVMe (ZFS)
Node 2: Similar specs + 931GB NVMe (ZFS)  
Node 3: Similar specs + 931GB NVMe (ZFS)
    +
Shared NAS: Multi-TB storage (backup & bulk storage)
```

### Storage Tiers
- **Tier 1**: Local NVMe ZFS pools (high performance)
- **Tier 2**: Shared NAS storage (reliability & capacity)

## ⚡ Storage Performance Comparison

### Local ZFS Performance
```
Read Speed:   2,500+ MB/s (direct NVMe)
Write Speed:  1,800+ MB/s (with compression)
Latency:      <1ms (local access)
IOPS:         30,000+ (NVMe capability)
Features:     Compression, snapshots, integrity
```

### NAS Storage Performance
```
Read Speed:   100-500 MB/s (network limited)
Write Speed:  50-200 MB/s (network limited)
Latency:      5-20ms (network delays)
IOPS:         1,000-5,000 (network limited)
Features:     Shared access, large capacity, redundancy
```

## 🎯 VM Storage Placement Strategy

### Tier 1: Local ZFS Storage (High Performance)

**Use for VMs that need:**
- Fast disk I/O (databases, applications)
- Low latency (real-time services)
- High IOPS (busy web servers)
- Quick boot times
- Responsive user experience

**Examples:**
- Database servers (MySQL, PostgreSQL, MongoDB)
- Web application servers
- Container orchestration (Docker, Kubernetes)
- Development environments
- Gaming servers
- Real-time applications
- Frequently accessed VMs

### Tier 2: NAS Storage (Shared/Reliable)

**Use for VMs that need:**
- Shared access between nodes
- Easy backup/restore
- Large storage capacity
- Don't need maximum performance
- Development/testing environments

**Examples:**
- File servers (Samba, NFS)
- Media servers (Plex, Jellyfin)
- Backup servers
- Archive/storage VMs
- Development/testing VMs
- Less frequently used services

## 📊 VM Placement Decision Framework

### Decision Tree
```
"Does this VM need to be FAST?"
├── YES → Local ZFS
└── NO → "Does it need to be SHARED?"
    ├── YES → NAS
    └── NO → "Is storage space more important than speed?"
        ├── YES → NAS
        └── NO → Local ZFS
```

### Performance Requirements Checklist
1. **Does it need <5ms disk latency?** → Local ZFS
2. **Does it handle >1000 IOPS regularly?** → Local ZFS  
3. **Is it a critical production service?** → Local ZFS
4. **Does it need >500GB storage?** → Consider NAS
5. **Is it accessed infrequently?** → NAS

## 🏠 Recommended VM Distribution

### 80/20 Rule
- **Local ZFS**: 80% of VMs, 20% of storage capacity
- **NAS Storage**: 20% of VMs, 80% of storage capacity

### Typical Node Layout

**Node 1 (Local ZFS):**
```
vm-fast-node1/
├── VM-100: Production Database (MySQL)
├── VM-101: Web Application Server  
├── VM-102: Container Host (Docker)
└── VM-103: Development Environment
```

**Node 2 (Local ZFS):**
```
vm-fast-node2/
├── VM-200: Production API Server
├── VM-201: Redis Cache Server
├── VM-202: Monitoring Stack (Grafana)
└── VM-203: CI/CD Pipeline
```

**Node 3 (Local ZFS):**
```
vm-fast-node3/
├── VM-300: Load Balancer (HAProxy)
├── VM-301: Mail Server
├── VM-302: DNS Server
└── VM-303: Backup Controller
```

**NAS Storage (Shared):**
```
nas-storage/
├── VM-400: File Server (Large files)
├── VM-401: Media Server (Plex)
├── VM-402: Backup Archive Server
├── VM-403: Development Test VMs
└── VM-404: Cold Storage Services
```

## 🔧 ZFS Configuration

### Pool Naming Convention
```
# Use unique names per node:
Node 1: vm-fast-node1
Node 2: vm-fast-node2
Node 3: vm-fast-node3

# Benefits:
✅ Clear identification of storage location
✅ No naming conflicts
✅ Easy troubleshooting
✅ Professional setup
```

### ZFS Optimization Settings
```bash
# After creating ZFS pool, optimize for VM workloads:
zfs set compression=lz4 vm-fast-node1
zfs set atime=off vm-fast-node1
zfs set recordsize=16K vm-fast-node1
zfs set primarycache=all vm-fast-node1
zfs set secondarycache=all vm-fast-node1
```

### Expected Space Efficiency
```
Raw NVMe Space:      931GB
ZFS Usable Space:    ~850GB (metadata overhead)
Effective Space:     ~1000-1200GB (with compression)
Net Result:          20-40% more usable space
```

## 🔄 High Availability Strategy

### Without Cross-Node RAID
```
✅ Local ZFS pools provide maximum performance
✅ VM migration for planned maintenance
✅ Backup/restore for disaster recovery
✅ Independent node operation
✅ No network dependencies for storage
```

### VM Migration Process
```
1. Node failure detected
2. VMs migrate to other nodes
3. VM storage restored from backups
4. Service continues on different node
```

### Backup Strategy
```
# Daily automated backups:
Node 1 VMs → NAS backup storage
Node 2 VMs → NAS backup storage  
Node 3 VMs → NAS backup storage

# Optional ZFS replication for critical VMs:
zfs send vm-fast-node1/vm-100@snapshot | 
ssh node2 zfs receive vm-fast-node2/vm-100-replica
```

## 📈 Performance Examples

### Database VM Comparison
```
Local ZFS:
- Query Response: 2-5ms average
- Backup Time: 15 minutes (1GB DB)
- Boot Time: 30 seconds

NAS Storage:
- Query Response: 10-50ms average  
- Backup Time: 45 minutes (1GB DB)
- Boot Time: 2-3 minutes

Verdict: Local ZFS is 3-10x better for databases
```

### File Server VM Comparison
```
Local ZFS:
- File Access: Very fast, single-node only
- Storage: Limited to 931GB
- Sharing: Complex multi-node setup

NAS Storage:
- File Access: Good, multi-node access
- Storage: Multi-TB capacity
- Sharing: Built-in sharing features

Verdict: NAS is better for file sharing
```

## 🛠️ Implementation Phases

### Phase 1: Local ZFS Setup
```bash
# Per node configuration:
1. Create ZFS pool on NVMe drive
2. Optimize ZFS settings for VMs
3. Create critical production VMs
4. Establish backup routines
```

### Phase 2: NAS Integration
```bash
# When NAS is available:
1. Add NAS as Proxmox storage
2. Create shared/bulk storage VMs
3. Move appropriate VMs to NAS
4. Configure automated backups
```

### Phase 3: Optimization
```bash
# Ongoing tuning:
1. Monitor VM performance
2. Adjust VM placement as needed
3. Optimize based on usage patterns
4. Scale storage as required
```

## 🚨 What NOT to Do

### Avoid Cross-Node RAID
```
❌ Network latency kills performance
❌ Single point of failure (network)
❌ Complex management overhead
❌ Not designed for distributed storage
❌ Eliminates benefits of local NVMe speed
```

### Don't Use Same ZFS Pool Names
```
❌ Creates confusion during VM migration
❌ Complicates troubleshooting
❌ Professional setup uses unique names
❌ Can cause storage conflicts
```

## 📋 Storage Monitoring

### ZFS Health Checks
```bash
# Regular monitoring commands:
zpool status                    # Pool health
zfs list                       # Space usage
zpool iostat 1                 # I/O statistics
zfs get compressratio vm-fast-node1  # Compression efficiency
```

### Performance Monitoring
```bash
# VM performance monitoring:
iotop          # Disk I/O per process
iostat 1       # System I/O statistics
zpool iostat 1 # ZFS pool I/O
```

## 🎯 Quick Reference

### VM Creation Checklist
- [ ] Determine VM performance requirements
- [ ] Choose appropriate storage tier (ZFS vs NAS)
- [ ] Use consistent naming convention
- [ ] Configure appropriate backup schedule
- [ ] Monitor performance after deployment

### Storage Capacity Planning
```
Per Node Allocation:
- Local ZFS: 4-6 high-performance VMs (~700GB)
- NAS: 2-3 large/shared VMs (~200GB per node)

Total Cluster:
- Local ZFS: 12-18 performance VMs
- NAS: 6-9 shared/storage VMs
```

## 🏆 Best Practices

1. **Start with local ZFS** for critical VMs
2. **Use NAS for shared services** and bulk storage
3. **Monitor performance** and adjust placement
4. **Maintain regular backups** to NAS
5. **Keep unique naming** across nodes
6. **Optimize ZFS settings** for VM workloads
7. **Plan capacity** based on VM requirements
8. **Test VM migration** procedures regularly

## 📚 Additional Resources

- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [ZFS Best Practices](https://wiki.proxmox.com/wiki/ZFS_on_Linux)
- [VM Backup Strategies](https://pve.proxmox.com/wiki/Backup_and_Restore)
- [Storage Configuration](https://pve.proxmox.com/wiki/Storage)

---

**Remember**: The key to successful storage strategy is matching storage performance to VM requirements. Use local ZFS for speed, NAS for capacity and sharing!
