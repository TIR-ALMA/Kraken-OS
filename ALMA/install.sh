#!/bin/bash
# Установщик Kraken OS для пользователей

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

error() { echo -e "${RED}❌ $1${NC}"; exit 1; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

if [ "$EUID" -ne 0 ]; then
    error "Запустите с sudo: sudo $0"
fi

echo "🐙 KRAKEN OS ULTRA - Установщик"
echo "================================"
echo "1) Установить в VirtualBox"
echo "2) Записать на USB"
echo "3) Запустить в QEMU"
echo "4) Установить на жесткий диск"
echo "5) Выход"
read -p "Выбор: " option

case $option in
    1)
        warning "Установка в VirtualBox..."
        apt-get install -y virtualbox virtualbox-ext-pack
        VBoxManage createvm --name "KrakenOS" --ostype "Debian_64" --register
        VBoxManage modifyvm "KrakenOS" --memory 4096 --cpus 2
        VBoxManage storagectl "KrakenOS" --name "SATA" --add sata
        VBoxManage storageattach "KrakenOS" --storagectl "SATA" --port 0 --type dvddrive --medium kraken-ultra.iso
        VBoxManage createhd --filename "KrakenOS.vdi" --size 20480
        VBoxManage storageattach "KrakenOS" --storagectl "SATA" --port 1 --device 0 --type hdd --medium "KrakenOS.vdi"
        VBoxManage startvm "KrakenOS"
        success "VirtualBox VM создана"
        ;;
    2)
        warning "Запись на USB..."
        lsblk
        read -p "Введите USB устройство (например: sdb): " usb
        if [ -b "/dev/$usb" ]; then
            dd if=kraken-ultra.iso of="/dev/$usb" bs=4M status=progress
            sync
            success "ISO записан на USB"
        else
            error "Устройство не найдено"
        fi
        ;;
    3)
        warning "Запуск в QEMU..."
        apt-get install -y qemu-kvm
        qemu-img create -f qcow2 kraken.qcow2 20G
        qemu-system-x86_64 \
            -cdrom kraken-ultra.iso \
            -drive file=kraken.qcow2,format=qcow2 \
            -m 4G -smp 2 \
            -net nic -net user \
            -vga virtio
        ;;
    4)
        warning "Установка на жесткий диск..."
        ./kraken-autoinstall
        ;;
    5)
        exit 0
        ;;
    *)
        error "Неверный выбор"
        ;;
esac
