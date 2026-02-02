#!/bin/bash

usage() {
    echo "Использование: $0 --old-id ID --new-id ID --source IP"
    echo "Пример: $0 --old-id 100 --new-id 101 --source 192.168.1.100"
    exit 1
}

declare old_vm_id new_vm_id source_ip

#пока количество аргументов не равно 0 читаем по два аргумента за итерацию, 
#имеется ввиду, что:  
#[--old-id, 100, --new-id, 101, --source, 192.168.1.100]
#    $1      $2     $3      $4     $5         $6
while [[ $# -gt 0 ]]; do
    case "$1" in
        --old-id) old_vm_id="$2"; shift 2 ;;
        --new-id) new_vm_id="$2"; shift 2 ;;
        --source) source_ip="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Ошибка: Неизвестный параметр '$1'" >&2; usage ;;
    esac
done

#проверяем, что все аргументы на месте
if [ -z "${old_vm_id:-}" ] || [ -z "${new_vm_id:-}" ] || [ -z "${source_ip:-}" ]; then
    echo "Ошибка: Не указаны обязательные параметры"
    usage
fi


#mkdir -p /media/pers2/images/
#mkdir -p /media/pers2/qemu/

mkdir -p /var/lib/vz/images/$new_vm_id/

echo "sshfs в /var/lib/vz/images..."
if ! sshfs root@$source_ip:/var/lib/vz/images/$old_vm_id/ /media/pers2/images/ -o uid=1000,gid=1000; then
    echo "sshfs не сработал (перый вызов)"
    exit 1
fi

disk_files=($(find /media/pers2/images/ -maxdepth 1 -type f \( -name "*.qcow2" -o -name "*.raw" \) | sort)) #если в имени будет пробел, то сломается
disk_files_count=${#disk_files[@]}

echo "конвертация дисков вм"
for ((i=0; i<disk_files_count; i++)); do
    disk_file=$(basename "${disk_files[$i]}")
    new_disk_name="vm-${new_vm_id}-disk-${i}.qcow2"
    
    echo "конвертируется диск $((i+1))/$disk_files_count: $disk_file -> $new_disk_name"
    
    if ! qemu-img convert "${disk_files[$i]}" -O qcow2 "/var/lib/vz/images/$new_vm_id/$new_disk_name"; then 
        echo "qemu жмыхнуло: $disk_file"
        fusermount -u /media/pers2/images/
        exit 1
    fi
done

#if ! qemu-img convert /media/pers2/images/vm-$old_vm_id-disk-0.qcow2 -O qcow2 /var/lib/vz/images/$new_vm_id/vm-$new_vm_id-disk-0.qcow2; then 
#    echo "qemu жмыхнуло"
#    exit 1
#fi

echo "sshfs в /etc/pve/qemu-server..."
if ! sshfs root@$source_ip:/etc/pve/qemu-server/ /media/pers2/qemu -o uid=1000,gid=1000;then
    echo "sshfs не сработал (второй вызов)"
    exit 1
fi

cp /media/pers2/qemu/$old_vm_id.conf /etc/pve/qemu-server/$new_vm_id.conf
# cp /etc/pve/qemu-server/$new_vm_id.conf /etc/pve/qemu-server/$new_vm_id.conf.backup

###########КОНФИГУ ЛУЧШЕ САМОМУ ПРАВИТЬ##############################

# for ((i=0; i<disk_files_count; i++)); do
#     old_disk_pattern="$old_vm_id/vm-$old_vm_id-disk-$i"
#     new_disk_pattern="$new_vm_id/vm-$new_vm_id-disk-$i"
    
#     sed -i "s|$old_disk_pattern|$new_disk_pattern|g" /etc/pve/qemu-server/$new_vm_id.conf
#     echo "в конфиге заменено: $old_disk_pattern -> $new_disk_pattern"
# done

# sed -i "s/vm-$old_vm_id-disk/vm-$new_vm_id-disk/g" /etc/pve/qemu-server/$new_vm_id.conf
# sed -i "s/ide$old_vm_id/ide$new_vm_id/g" /etc/pve/qemu-server/$new_vm_id.conf
# sed -i "s/scsi$old_vm_id/scsi$new_vm_id/g" /etc/pve/qemu-server/$new_vm_id.conf
# sed -i "s/sata$old_vm_id/sata$new_vm_id/g" /etc/pve/qemu-server/$new_vm_id.conf
# sed -i "s/virtio$old_vm_id/virtio$new_vm_id/g" /etc/pve/qemu-server/$new_vm_id.conf

# echo "конфиг /etc/pve/qemu-server/новый_id/новый_id.conf отредактирован"

ls -la /var/lib/vz/images/$new_vm_id/
ls -la /etc/pve/qemu-server/$new_vm_id.conf

cleanup() {
    fusermount -u /media/pers2/images/ 2>/dev/null || true
    fusermount -u /media/pers2/qemu/ 2>/dev/null || true
    echo "папки отмонтированы"
}

trap cleanup EXIT INT TERM