#!/bin/bash

usage() {
    echo "Использование: $0 --old-id ID --new-id ID --source IP"
    echo "Пример: $0 --old-id 100 --new-id 101 --source 192.168.1.100"
    echo ""
    echo "Требования перед запуском:"
    echo "1. Исходная VM должна быть выключена"
    echo "2. Новая VM не должна существовать"
    echo "3. Достаочно свободного места"
    echo "4. Есть пароли от рута или ssh-ключи добавлены"
    echo "5. Пути для монтирования можно поменять в самом скрипте"
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

#в конце скрипта в не зависимости от того, как он завершился, диски размонтируются
cleanup() {
    echo "Размонтируем диски..."

    if mountpoint -q "$IMAGES_MOUNT" 2>/dev/null; then
        fusermount -uz "$IMAGES_MOUNT"
    fi
    
    if mountpoint -q "$QEMU_MOUNT" 2>/dev/null; then
        fusermount -uz "$QEMU_MOUNT"
    fi
}

trap cleanup EXIT INT TERM

# Пути для монтирования
IMAGES_MOUNT="/media/pers2/images"
QEMU_MOUNT="/media/pers2/qemu"

# Локальные пути
LOCAL_IMAGES_DIR="/var/lib/vz/images/${new_vm_id}"
LOCAL_CONF_DIR="/etc/pve/qemu-server"
LOCAL_CONF_FILE="${LOCAL_CONF_DIR}/${new_vm_id}.conf"

mkdir -p "$IMAGES_MOUNT" "$QEMU_MOUNT"

echo "Монтируем образы дисков с $source_ip..."
if ! sshfs "root@$source_ip:/var/lib/vz/images/$old_vm_id/" "$IMAGES_MOUNT" -o uid=1000,gid=1000; then
    echo "Ошибка: Не удалось смонтировать образы дисков" >&2
    exit 1
fi

echo "Монтируем конфигурации с $source_ip..."
if ! sshfs "root@$source_ip:/etc/pve/qemu-server/" "$QEMU_MOUNT" -o uid=1000,gid=1000; then
    echo "Ошибка: Не удалось смонтировать конфигурации" >&2
    fusermount -u "$IMAGES_MOUNT" 2>/dev/null || true
    exit 1
fi

echo "Начинаем перенос дисков..."

mkdir -p "$LOCAL_IMAGES_DIR"

# Ищем все файлы дисков (qcow2 и raw)
echo "Ищем файлы дисков..."
disk_files=()
while IFS= read -r -d $'\0' file; do
    disk_files+=("$file")
done < <(find "$IMAGES_MOUNT" -type f \( -name "*.qcow2" -o -name "*.raw" \) -print0)

if [[ ${#disk_files[@]} -eq 0 ]]; then
    echo "Ошибка: Не найдено ни одного диска (.qcow2 или .raw)" >&2
    exit 1
fi

echo "Найдено дисков: ${#disk_files[@]}"
for i in "${!disk_files[@]}"; do
    disk_name=$(basename "${disk_files[$i]}")
    echo "  $((i+1)). $disk_name"
done
