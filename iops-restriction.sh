#!/bin/bash

MBPS=50
MBPS_MAX=100
DELAY=2

if [ "$1" != "" ]; then
    VMID="$1"
    CONFIG_FILE="/etc/pve/qemu-server/$VMID.conf"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "VM $VMID not found"
        exit 1
    fi
    
    SET_ARGS=""
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^(virtio|ide|sata|scsi)[0-9]+: ]]; then
            disk_name=$(echo "$line" | cut -d':' -f1)
            disk_spec=$(echo "$line" | cut -d':' -f2- | sed 's/^[[:space:]]*//')
            disk_spec=$(echo "$disk_spec" | sed -E 's/,mbps=[0-9]+//g' | sed -E 's/,mbps_max=[0-9]+//g')
            SET_ARGS="$SET_ARGS --$disk_name \"$disk_spec,mbps=$MBPS,mbps_max=$MBPS_MAX\""
        fi
    done < "$CONFIG_FILE"
    
    if [ -n "$SET_ARGS" ]; then
        eval "qm set $VMID $SET_ARGS"
    fi
else
    echo "Applying limits to all VMs..."
    
    for VMID in $(qm list | awk 'NR>1 {print $1}'); do
        echo "Processing VM $VMID"
        $0 $VMID
        sleep $DELAY
    done
    
    echo "All VMs processed"
fi