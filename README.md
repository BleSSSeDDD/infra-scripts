# Proxmox VM Tools

A collection of scripts for managing virtual machines in Proxmox.

## 📦 Scripts

- [`iops-restriction.sh`](#iops-restrictionsh) - apply I/O limits to all VMs
- [`vm-migrate-id.sh`](#vm-migrate-idsh) - clone a VM with a new ID from another server

---

## `iops-restriction.sh`

A script for applying I/O limits (`mbps`) to all virtual machines in Proxmox at once.

### Description

Automatically adds `mbps` and `mbps_max` parameters to all disks of Proxmox virtual machines. Supports all disk types: virtio, ide, sata, scsi.

**Features:**
- Works without VM reboot (zero downtime)
- Preserves all existing disk parameters
- Removes old limits before applying new ones
- Can apply to all VMs or a specific one
- Automatic delay between VMs to reduce server load

### Usage

```bash
# Apply to all VMs
./iops-restriction.sh

# Apply to a specific VM
./iops-restriction.sh <VMID>
```

### Configuration

You can change parameters at the beginning of the script:

```bash
MBPS=50        # average speed in MB/s
MBPS_MAX=100   # maximum speed in MB/s
DELAY=2        # delay between VMs in seconds
```

### Requirements

- Proxmox VE
- root access
- `qm` command must be available

### Example

```bash
./iops-restriction.sh 178
# Output:
# update VM 178: -ide2 none,media=cdrom,mbps=50,mbps_max=100 
# -virtio0 local:178/vm-178-disk-0.qcow2,size=100G,mbps=50,mbps_max=100
```

### Notes

- Before mass applying, it's recommended to backup configs:
  ```bash
  cp -r /etc/pve/qemu-server /root/qemu-server-backup
  ```
- Script processes VMs sequentially with delay to reduce load
- Cloud-init disks are automatically regenerated if needed (normal behavior)

---

## `vm-migrate-id.sh`

A script for cloning a VM from another Proxmox server with a new ID. Copies both disk images and configuration.

### Description

This script connects to a remote Proxmox server via SSH, mounts its disk images and configurations, copies all VM disks to the local server, and creates a new VM with a different ID.

**Features:**
- Copies all disk formats (qcow2, raw, vmdk, vdi, img, vhd, vhdx)
- Automatically converts non-qcow2 formats to qcow2
- Preserves disk contents during conversion
- Updates all disk paths in the new configuration
- Clean unmounting even if script fails

### Requirements

- Passwordless SSH access to source server (or ssh keys)
- `sshfs` installed
- `qemu-utils` installed (for qemu-img)
- Source VM must be shut down
- Enough free space on destination server

### Usage

```bash
./vm-migrate-id.sh --old-id <ID> --new-id <ID> --source <IP>
```

**Parameters:**
- `--old-id` - Source VM ID on remote server
- `--new-id` - New VM ID on local server
- `--source` - IP address of source Proxmox server

### Example

```bash
./vm-migrate-id.sh --old-id 100 --new-id 101 --source 192.168.1.100
```

### What the script does

1. Validates all parameters
2. Mounts remote disk images via SSHFS
3. Mounts remote VM configurations via SSHFS
4. Copies all disk files, converting non-qcow2 formats:
   - `.raw` → direct copy
   - `.qcow2` → direct copy with verification
   - Other formats (vmdk, vdi, img, etc.) → convert to qcow2
5. Copies and updates VM configuration
6. Replaces all old VM ID references with new ID in config
7. Automatically unmounts remote filesystems

### Output

```
mounting disk images from 192.168.1.100...
mounting configurations from 192.168.1.100...
starting disk migration...
disk 1/2: vm-100-disk-0.qcow2 → vm-101-disk-0.qcow2
disk 2/2: vm-100-disk-1.raw → vm-101-disk-1.raw
disks copied and renamed
copying configuration...
VM 100 migrated to 101

copied disks:
total 10G
-rw-r--r-- 1 root root 5G Feb 18 12:00 vm-101-disk-0.qcow2
-rw-r--r-- 1 root root 5G Feb 18 12:00 vm-101-disk-1.raw

configuration:
-rw-r--r-- 1 root root 1.2K Feb 18 12:00 /etc/pve/qemu-server/101.conf

updating disk paths in configuration...

all done. verify the VM works and remove it from source server
```

### Notes

- The script creates a new VM ID, make sure it doesn't already exist
- After migration, you need to manually verify the VM works
- The original VM on the source server remains untouched
- If VM doesn't start, you may need to manually edit the config
- Mount points can be changed at the beginning of the script

### Troubleshooting

**VM doesn't start after migration:**
- Check if all disk paths in config are correct
- Verify disk formats match what config expects
- Check file permissions on new disk images

**SSHFS mount fails:**
- Ensure SSH key authentication is set up
- Verify source IP is reachable
- Check if source server has SSHFS installed

**Conversion errors:**
- Make sure `qemu-img` is installed
- Check if there's enough free space
- Verify source disk images are not corrupted

---
