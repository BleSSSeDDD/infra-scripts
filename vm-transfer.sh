#!/bin/bash

usage() {
    echo "Использование: $0 --old-id ID --new-id ID --source IP"
    echo "Пример: $0 --old-id 100 --new-id 101 --source 192.168.1.100"
    echo ""
    echo "Требования перед запуском:"
    echo "1. Исходная ВМ должна быть выключена"
    echo "2. Достаточно свободного места"
    echo "3. Есть пароли от рута или ssh-ключи добавлены"
    echo "4. Пути для монтирования можно поменять в самом скрипте"
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
        *) echo "ОШИБКА: неизвестный параметр '$1'" >&2; usage ;;
    esac
done

#проверяем, что все аргументы на месте
if [ -z "${old_vm_id:-}" ] || [ -z "${new_vm_id:-}" ] || [ -z "${source_ip:-}" ]; then
    echo "ОШИБКА: не указаны обязательные параметры"
    usage
fi

#в конце скрипта в не зависимости от того, как он завершился, диски размонтируются
cleanup() {
    echo ""
    echo "размонтируем диски..."

    if mountpoint -q "$IMAGES_MOUNT" 2>/dev/null; then
        fusermount -uz "$IMAGES_MOUNT"
    fi
    
    if mountpoint -q "$QEMU_MOUNT" 2>/dev/null; then
        fusermount -uz "$QEMU_MOUNT"
    fi
}

trap cleanup EXIT INT TERM

if ! [[ "$source_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ОШИБКА: source должен быть IP адресом"
    exit 1
fi

if ! [[ "$old_vm_id" =~ ^[0-9]+$ ]]; then
    echo "ОШИБКА: old-id должен быть числом"
    exit 1
fi

if ! [[ "$new_vm_id" =~ ^[0-9]+$ ]]; then
    echo "ОШИБКА: new-id должен быть числом"
    exit 1
fi

#пути для монтирования
IMAGES_MOUNT="/mount/path/to/images"
QEMU_MOUNT="/mount/path/to/qemu"

#локальные пути
LOCAL_IMAGES_DIR="/var/lib/vz/images/${new_vm_id}"
LOCAL_CONF_DIR="/etc/pve/qemu-server"
LOCAL_CONF_FILE="${LOCAL_CONF_DIR}/${new_vm_id}.conf"

if [[ -f "$LOCAL_CONF_FILE" ]]; then
    echo "ОШИБКА: ВМ с айди $new_vm_id уже существует"
    exit 1
fi

mkdir -p "$IMAGES_MOUNT" "$QEMU_MOUNT"

echo "монтируем образы дисков с $source_ip..."
if ! sshfs "root@$source_ip:/var/lib/vz/images/$old_vm_id/" "$IMAGES_MOUNT" -o uid=1000,gid=1000; then
    echo "ОШИБКА: не удалось смонтировать образы дисков" >&2
    exit 1
fi

echo "монтируем конфигурации с $source_ip..."
if ! sshfs "root@$source_ip:/etc/pve/qemu-server/" "$QEMU_MOUNT" -o uid=1000,gid=1000; then
    echo "ОШИБКА: не удалось смонтировать конфигурации" >&2
    fusermount -u "$IMAGES_MOUNT" 2>/dev/null || true
    exit 1
fi

echo "начинаем перенос дисков..."

mkdir -p "$LOCAL_IMAGES_DIR"

#ищем все диски
disk_files=()
while IFS= read -r -d $'\0' file; do
    disk_files+=("$file")
done < <(find "$IMAGES_MOUNT" -type f \( \
    -name "*.qcow2" -o \
    -name "*.qcow" -o \
    -name "*.raw" -o \
    -name "*.img" -o \
    -name "*.vmdk" -o \
    -name "*.vdi" -o \
    -name "*.vhd" -o \
    -name "*.vhdx" \
\) -print0)

if [[ ${#disk_files[@]} -eq 0 ]]; then
    echo "не найдено ни одного диска (.qcow2 или .raw)" >&2
    exit 1
fi

disk_files_count=${#disk_files[@]}

for i in "${!disk_files[@]}"; do
    disk_path="${disk_files[$i]}"
    disk_name=$(basename "$disk_path")

    new_disk_name="${disk_name//vm-$old_vm_id/vm-$new_vm_id}"
    
    echo "диск $((i+1))/$disk_files_count: $disk_name → $new_disk_name"
    
    if [[ "$disk_name" == *.raw ]]; then
        if ! cp "$disk_path" "$LOCAL_IMAGES_DIR/$new_disk_name"; then
            echo "не удалось скопировать $disk_name"
            exit 1
        fi
        
    elif [[ "$disk_name" == *.qcow2 ]]; then
        if ! qemu-img convert -p "$disk_path" -O qcow2 "$LOCAL_IMAGES_DIR/$new_disk_name"; then
            echo "qemu-img не смог конвертировать $disk_name"
            exit 1
        fi
        
    else
        #ВСЕ остальные форматы (vmdk, vdi, img, qcow и т.д.) конвертируем в .qcow2
        new_name_with_qcow2="${new_disk_name%.*}.qcow2"
        
        if ! qemu-img convert -p "$disk_path" -O qcow2 "$LOCAL_IMAGES_DIR/$new_name_with_qcow2"; then
            echo "не удалось конвертировать $disk_name в qcow2"
            exit 1
        fi
    fi
done

echo "диски перенесены и переименованы"

echo "копируем конфигурацию..."

if [[ ! -f "$QEMU_MOUNT/$old_vm_id.conf" ]]; then
    echo "ОШИБКА: конфигурация $old_vm_id.conf не найдена" >&2
    exit 1
fi

if ! cp "$QEMU_MOUNT/$old_vm_id.conf" "$LOCAL_CONF_FILE"; then
    echo "ОШИБКА: не удалось скопировать конфигурацию" >&2
    exit 1
fi

echo "ВМ $old_vm_id перенесена в $new_vm_id"

echo "скопированные диски:"
ls -lh "$LOCAL_IMAGES_DIR/"

echo ""
echo "конфигурация:"
ls -lh "$LOCAL_CONF_FILE"

echo ""

echo "обновляем пути к дискам в конфигурации..."

#заменяем старые ID дисков на новые
sed -i "s/vm-$old_vm_id-disk-/vm-$new_vm_id-disk-/g" "$LOCAL_CONF_FILE"
sed -i "s/vm-$old_vm_id-state-/vm-$new_vm_id-state-/g" "$LOCAL_CONF_FILE"
sed -i "s/:$old_vm_id\//:$new_vm_id\//g" "$LOCAL_CONF_FILE"

echo ""

echo "всё готово, теперь надо убедиться, что ВМ работает и удалить её со старого сервера"
echo "если вм не поднимается, скорее всего, надо вручную поправить конфиг"
