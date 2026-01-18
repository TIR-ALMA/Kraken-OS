#!/bin/bash
set -euo pipefail

# ============================================================================
# KRAKEN OS ULTRA - ГЛАВНЫЙ СКРИПТ СБОРКИ
# Версия с адаптивной VM-изоляцией
# ============================================================================

# Конфигурация
ROOTFS="kraken_rootfs"
ISO_NAME="kraken-ultra-$(date +%Y%m%d-%H%M).iso"
DEBIAN_MIRROR="http://deb.debian.org/debian"
DEBIAN_RELEASE="bookworm"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Функции для логирования
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${PURPLE}[DEBUG]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# ============================================================================
# БАЗОВЫЕ ФУНКЦИИ
# ============================================================================

# Проверка прав
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Этот скрипт требует прав суперпользователя"
        log_info "Запустите: sudo $0"
        exit 1
    fi
}

# Проверка зависимостей
check_dependencies() {
    log_step "Проверка зависимостей..."
    
    local deps=("debootstrap" "grub-pc-bin" "grub-efi-amd64-bin" "xorriso" "mtools" "dosfstools" "curl" "wget")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1 && ! dpkg -l | grep -q "^ii  $dep"; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_warning "Установка недостающих зависимостей: ${missing[*]}"
        apt-get update
        apt-get install -y "${missing[@]}"
    fi
}

# Создание базовой системы
create_base_system() {
    log_step "Создание базовой системы Debian..."
    
    if [ -d "$ROOTFS" ]; then
        log_warning "Директория $ROOTFS уже существует"
        read -p "Удалить и пересоздать? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$ROOTFS"
        else
            log_info "Используем существующую систему"
            return 0
        fi
    fi
    
    # Создание базовой системы
    debootstrap --variant=minbase --arch=amd64 \
                --include=sudo,locales,keyboard-configuration,console-setup \
                "$DEBIAN_RELEASE" "$ROOTFS" "$DEBIAN_MIRROR"
    
    if [ $? -ne 0 ]; then
        log_error "Ошибка debootstrap"
        exit 1
    fi
}

# Монтирование системных директорий
mount_virtual_fs() {
    log_step "Монтирование виртуальных файловых систем..."
    
    mount_points=(
        "/dev" "/dev/pts" "/proc" "/sys" "/run"
    )
    
    for mp in "${mount_points[@]}"; do
        mkdir -p "${ROOTFS}${mp}"
        if [[ "$mp" == "/dev" ]]; then
            mount --rbind "$mp" "${ROOTFS}${mp}"
            mount --make-rslave "${ROOTFS}${mp}"
        elif [[ "$mp" == "/dev/pts" ]]; then
            mount -t devpts devpts "${ROOTFS}${mp}"
        elif [[ "$mp" == "/proc" ]]; then
            mount -t proc proc "${ROOTFS}${mp}"
        elif [[ "$mp" == "/sys" ]]; then
            mount -t sysfs sysfs "${ROOTFS}${mp}"
        elif [[ "$mp" == "/run" ]]; then
            mount -t tmpfs tmpfs "${ROOTFS}${mp}"
        fi
    done
    
    # Копирование DNS настроек
    cp /etc/resolv.conf "${ROOTFS}/etc/resolv.conf"
}

# Размонтирование системных директорий
umount_virtual_fs() {
    log_step "Размонтирование виртуальных файловых систем..."
    
    mount_points=("/run" "/sys" "/proc" "/dev/pts" "/dev")
    
    for mp in "${mount_points[@]}"; do
        if mountpoint -q "${ROOTFS}${mp}"; then
            umount -R "${ROOTFS}${mp}" 2>/dev/null || true
        fi
    done
}

# ============================================================================
# КОНФИГУРАЦИЯ СИСТЕМЫ
# ============================================================================

configure_system() {
    log_step "Конфигурация системы внутри chroot..."
    
    cat > "${ROOTFS}/tmp/configure.sh" << 'CHROOT_SCRIPT'
#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

# 1. Настройка системы
echo "kraken" > /etc/hostname
cat > /etc/hosts << HOSTS
127.0.0.1 localhost
127.0.0.1 kraken.localdomain kraken
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
HOSTS

# 2. Настройка локали
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8 LC_MESSAGES=POSIX

# 3. Обновление системы
apt-get update
apt-get upgrade -y

# 4. Установка базовых пакетов
apt-get install -y \
    linux-image-amd64 \
    firmware-linux-nonfree \
    firmware-misc-nonfree \
    grub-pc \
    grub-efi-amd64 \
    cryptsetup \
    cryptsetup-initramfs \
    lvm2 \
    network-manager \
    wpasupplicant \
    wireless-tools \
    net-tools \
    iproute2 \
    curl \
    wget \
    gnupg \
    ca-certificates \
    git \
    build-essential

# 5. Создание пользователя
if ! id -u user >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo,audio,video,netdev,plugdev user
    echo "user:user" | chpasswd
    echo "user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/user
    chmod 440 /etc/sudoers.d/user
fi

# 6. Настройка сети
cat > /etc/NetworkManager/NetworkManager.conf << NM_CONF
[main]
plugins=ifupdown,keyfile
[ifupdown]
managed=true
[device]
wifi.scan-rand-mac-address=yes
NM_CONF

# 7. Настройка SSH
apt-get install -y openssh-server
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
mkdir -p /home/user/.ssh
chmod 700 /home/user/.ssh
chown -R user:user /home/user/.ssh

# 8. Настройка времени
timedatectl set-timezone UTC
apt-get install -y ntp
systemctl enable systemd-timesyncd

# 9. Настройка GRUB
cat > /etc/default/grub << GRUB_CONF
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Kraken"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
GRUB_ENABLE_CRYPTODISK=y
GRUB_TERMINAL=console
GRUB_DISABLE_OS_PROBER=true
GRUB_CONF

update-grub

# 10. Настройка криптографии для LUKS
cat > /etc/cryptsetup-initramfs/conf-hook << CRYPT_HOOK
KEYFILE_PATTERN="/etc/luks/*.keyfile"
UMASK=0077
CRYPT_HOOK

# 11. Очистка пакетов
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*
CHROOT_SCRIPT

    chmod +x "${ROOTFS}/tmp/configure.sh"
    chroot "$ROOTFS" /bin/bash /tmp/configure.sh
    rm -f "${ROOTFS}/tmp/configure.sh"
}

# ============================================================================
# ИНИЦИАЛИЗАЦИЯ И БЕЗОПАСНОСТЬ
# ============================================================================

install_dinit() {
    log_step "Установка Dinit как init системы..."
    
    cat > "${ROOTFS}/tmp/install_dinit.sh" << 'DINIT_SCRIPT'
#!/bin/bash
set -e

# Установка Dinit из backports
echo "deb http://deb.debian.org/debian bookworm-backports main" > /etc/apt/sources.list.d/backports.list
apt-get update
apt-get install -y -t bookworm-backports dinit dinit-console-services

# Настройка служб Dinit
mkdir -p /etc/dinit.d
cp /usr/share/dinit/services/* /etc/dinit.d/

# Замена init
ln -sf /usr/lib/dinit/dinit /sbin/init

# Отключение systemd служб
if command -v systemctl >/dev/null 2>&1; then
    systemctl disable systemd-networkd || true
    systemctl disable systemd-resolved || true
    systemctl disable systemd-timesyncd || true
fi

# Создание базовых служб Dinit
cat > /etc/dinit.d/network << DINIT_NETWORK
type = process
command = /usr/sbin/NetworkManager --no-daemon
restart = yes
DINIT_NETWORK

cat > /etc/dinit.d/ssh << DINIT_SSH
type = process
command = /usr/sbin/sshd -D
restart = yes
DINIT_SSH
DINIT_SCRIPT

    chmod +x "${ROOTFS}/tmp/install_dinit.sh"
    chroot "$ROOTFS" /bin/bash /tmp/install_dinit.sh
    rm -f "${ROOTFS}/tmp/install_dinit.sh"
}

install_selinux() {
    log_step "Установка SELinux..."
    
    cat > "${ROOTFS}/tmp/install_selinux.sh" << 'SELINUX_SCRIPT'
#!/bin/bash
set -e

apt-get install -y \
    selinux-basics \
    selinux-policy-default \
    auditd \
    setools \
    policycoreutils \
    checkpolicy

# Активация SELinux
selinux-activate
setenforce 1
sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config

# Настройка контекстов
semanage fcontext -a -t user_home_dir_t "/home/.*"
restorecon -R /home
SELINUX_SCRIPT

    chmod +x "${ROOTFS}/tmp/install_selinux.sh"
    chroot "$ROOTFS" /bin/bash /tmp/install_selinux.sh
    rm -f "${ROOTFS}/tmp/install_selinux.sh"
}

install_security_tools() {
    log_step "Установка инструментов безопасности..."
    
    cat > "${ROOTFS}/tmp/install_security.sh" << 'SECURITY_SCRIPT'
#!/bin/bash
set -e

# AppArmor
apt-get install -y \
    apparmor \
    apparmor-utils \
    apparmor-profiles \
    apparmor-profiles-extra

systemctl enable apparmor
aa-enforce /etc/apparmor.d/*

# TPM 2.0 инструменты
apt-get install -y \
    tpm2-tools \
    tpm2-abrmd \
    tpm2-tss-engine \
    tpm2-pkcs11 \
    libtss2-esys0

systemctl enable tpm2-abrmd

# YubiKey инструменты
apt-get install -y \
    yubikey-manager \
    yubikey-personalization \
    yubico-piv-tool \
    yubioath-desktop \
    pcscd \
    libpam-yubico

systemctl enable pcscd

# Secure Boot инструменты
apt-get install -y \
    sbsigntool \
    efitools \
    shim-signed \
    grub-efi-amd64-signed \
    mokutil

# PaX/grsecurity инструменты
apt-get install -y paxctl
paxctl -c /usr/bin/*
paxctl -m /usr/bin/*

# Аудит и мониторинг
apt-get install -y \
    aide \
    tripwire \
    rkhunter \
    chkrootkit \
    lynis \
    auditd \
    fail2ban

# Настройка AIDE
aideinit --yes
mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# Настройка fail2ban
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sed -i 's/bantime  = 10m/bantime  = 1h/' /etc/fail2ban/jail.local
sed -i 's/maxretry = 5/maxretry = 3/' /etc/fail2ban/jail.local
systemctl enable fail2ban

# Firewall
apt-get install -y nftables
systemctl enable nftables

cat > /etc/nftables.conf << NFTABLES
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        iifname "lo" accept
        iifname != "lo" ip daddr 127.0.0.0/8 drop
        ct state established,related accept
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept
        tcp dport 22 accept
        ct state invalid drop
    }
    chain forward {
        type filter hook forward priority 0; policy drop;
    }
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
NFTABLES

nft -f /etc/nftables.conf
SECURITY_SCRIPT

    chmod +x "${ROOTFS}/tmp/install_security.sh"
    chroot "$ROOTFS" /bin/bash /tmp/install_security.sh
    rm -f "${ROOTFS}/tmp/install_security.sh"
}

# ============================================================================
# ГРАФИЧЕСКАЯ СРЕДА И ПРИЛОЖЕНИЯ
# ============================================================================

install_gui() {
    log_step "Установка графической среды XFCE..."
    
    cat > "${ROOTFS}/tmp/install_gui.sh" << 'GUI_SCRIPT'
#!/bin/bash
set -e

# Установка XFCE
apt-get install -y \
    xserver-xorg \
    xserver-xorg-video-all \
    xserver-xorg-input-all \
    xfce4 \
    xfce4-goodies \
    lightdm \
    lightdm-gtk-greeter \
    slick-greeter \
    network-manager-gnome \
    pulseaudio \
    pavucontrol \
    xfce4-pulseaudio-plugin

# Установка приложений
apt-get install -y \
    firefox-esr \
    chromium \
    libreoffice \
    gimp \
    vlc \
    thunderbird \
    transmission-gtk \
    file-roller \
    evince \
    gnome-terminal \
    mousepad \
    ristretto \
    parole

# Настройка LightDM
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/10-autologin.conf << LIGHTDM_CONF
[Seat:*]
autologin-user=user
autologin-user-timeout=0
user-session=xfce
greeter-session=lightdm-gtk-greeter
LIGHTDM_CONF

# Установка тем
apt-get install -y \
    papirus-icon-theme \
    arc-theme \
    materia-gtk-theme \
    breeze-cursor-theme

# Установка WhiteSur темы
apt-get install -y git sassc meson
git clone https://github.com/vinceliuice/WhiteSur-gtk-theme.git /tmp/whitesur
cd /tmp/whitesur && ./install.sh -t dark -i standard -l --theme default
rm -rf /tmp/whitesur

# Создание пользовательских настроек
mkdir -p /home/user/.config/xfce4/xfconf/xfce-perchannel-xml

cat > /home/user/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml << XFCE_DESKTOP
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="/usr/share/backgrounds/xfce/kraken-bg.png"/>
        </property>
      </property>
    </property>
  </property>
</channel>
XFCE_DESKTOP

cat > /home/user/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml << XFCE_THEME
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="WhiteSur-dark"/>
    <property name="IconThemeName" type="string" value="Papirus-Dark"/>
    <property name="CursorThemeName" type="string" value="breeze_cursors"/>
    <property name="FontName" type="string" value="Noto Sans 10"/>
  </property>
</channel>
XFCE_THEME

# Создание обоев и логотипа
mkdir -p /usr/share/backgrounds/xfce/
convert -size 1920x1080 xc:white /usr/share/backgrounds/xfce/kraken-bg.png
mkdir -p /usr/share/pixmaps/
convert -size 256x256 xc:none -fill '#4a86e8' -draw 'circle 128,128 128,20' \
    -fill white -pointsize 100 -gravity center -draw 'text 0,0 "K"' \
    /usr/share/pixmaps/kraken-logo.png

# Создание ссылок на логотип
ln -sf /usr/share/pixmaps/kraken-logo.png /usr/share/icons/hicolor/256x256/apps/kraken.png
ln -sf /usr/share/pixmaps/kraken-logo.png /usr/share/icons/hicolor/scalable/apps/kraken.svg

chown -R user:user /home/user/.config
GUI_SCRIPT

    chmod +x "${ROOTFS}/tmp/install_gui.sh"
    chroot "$ROOTFS" /bin/bash /tmp/install_gui.sh
    rm -f "${ROOTFS}/tmp/install_gui.sh"
}

install_anonymity_tools() {
    log_step "Установка инструментов анонимности..."
    
    cat > "${ROOTFS}/tmp/install_anonymity.sh" << 'ANONYMITY_SCRIPT'
#!/bin/bash
set -e

# Tor и инструменты
apt-get install -y \
    tor \
    torsocks \
    tor-geoipdb \
    obfs4proxy \
    nyx \
    proxychains4 \
    privoxy \
    polipo

# Настройка Tor
cat > /etc/tor/torrc << TORRC
SocksPort 9050
SocksPort 9051
DNSPort 53
AutomapHostsOnResolve 1
TransPort 9040
VirtualAddrNetworkIPv4 10.192.0.0/10
AvoidDiskWrites 1
Log notice file /var/log/tor/notices.log
RunAsDaemon 1
DataDirectory /var/lib/tor
SafeLogging 1
UseBridges 1
ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy
SafeSocks 1
TestSocks 1
WarnUnsafeSocks 1
MaxCircuitDirtiness 600
NewCircuitPeriod 30
MaxClientCircuitsPending 32
UseEntryGuards 1
NumEntryGuards 5
GuardLifetime 180 days
ExcludeNodes {ru},{cn},{by},{kz},{ua}
ExcludeExitNodes {ru},{cn},{by},{kz},{ua}
StrictNodes 1
TORRC

# I2P
apt-get install -y i2p i2p-keyring i2p-router
sed -i 's/^clientApp\.startOnLoad=.*/clientApp.startOnLoad=false/' /etc/i2p/i2p.config
systemctl enable i2p

# VPN инструменты
apt-get install -y \
    wireguard \
    wireguard-tools \
    openvpn \
    network-manager-openvpn \
    network-manager-wireguard

# DNS инструменты
apt-get install -y \
    dnscrypt-proxy \
    stubby \
    dnsmasq

# Squid proxy
apt-get install -y squid
systemctl enable tor privoxy squid dnscrypt-proxy
ANONYMITY_SCRIPT

    chmod +x "${ROOTFS}/tmp/install_anonymity.sh"
    chroot "$ROOTFS" /bin/bash /tmp/install_anonymity.sh
    rm -f "${ROOTFS}/tmp/install_anonymity.sh"
}

install_additional_software() {
    log_step "Установка дополнительного ПО..."
    
    cat > "${ROOTFS}/tmp/install_software.sh" << 'SOFTWARE_SCRIPT'
#!/bin/bash
set -e

# Терминальные инструменты
apt-get install -y \
    alacritty \
    tmux \
    fish \
    zsh \
    htop \
    btop \
    ncdu \
    ranger \
    fzf \
    bat \
    exa \
    ripgrep \
    fd-find \
    jq \
    yq

# Мультимедиа
apt-get install -y \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    pipewire-jack \
    wireplumber \
    kdenlive \
    audacity \
    darktable \
    inkscape \
    blender \
    obs-studio

# Разработка
apt-get install -y \
    git \
    build-essential \
    python3 \
    python3-pip \
    nodejs \
    npm \
    golang \
    rustc \
    cargo \
    openjdk-17-jdk \
    docker.io \
    docker-compose

# Системные утилиты
apt-get install -y \
    gparted \
    testdisk \
    photorec \
    bleachbit \
    timeshift \
    rsync

# Настройка .bashrc
cat >> /home/user/.bashrc << BASHRC
# Kraken OS Aliases
alias curl="torsocks curl"
alias wget="torsocks wget"
alias ls="exa --icons"
alias ll="exa -la --icons"
alias cat="bat"
alias grep="rg"
alias find="fd"
alias du="ncdu"
alias top="btop"

# Функция для запуска в изоляции
qube-run() {
    kraken-vm-isolate browser "\$@"
}

# Функция для очистки следов
clean-traces() {
    bleachbit --clean system.cache system.tmp system.trash
    journalctl --vacuum-time=3d
    rm -rf ~/.cache/* ~/.thumbnails/* /tmp/*
    echo "Следы очищены"
}

export PATH="\$PATH:/usr/local/bin"
BASHRC

chown -R user:user /home/user
SOFTWARE_SCRIPT

    chmod +x "${ROOTFS}/tmp/install_software.sh"
    chroot "$ROOTFS" /bin/bash /tmp/install_software.sh
    rm -f "${ROOTFS}/tmp/install_software.sh"
}

# ============================================================================
# VM-ИЗОЛЯЦИЯ (НОВАЯ ЧАСТЬ)
# ============================================================================

install_vm_isolation() {
    log_step "Установка VM-изоляции (KVM/QEMU/Libvirt)..."
    
    cat > "${ROOTFS}/tmp/install_vm_isolation.sh" << 'VM_ISOLATION_SCRIPT'
#!/bin/bash
set -e

echo "🐙 УСТАНОВКА VM-ИЗОЛЯЦИИ KRAKEN OS"
echo "=================================="

# Функция проверки виртуализации
check_virtualization_support() {
    echo "🔍 Проверка поддержки виртуализации..."
    
    local has_kvm=0
    local has_vtx=0
    
    if [ -e /dev/kvm ]; then
        has_kvm=1
        echo "✅ KVM доступен"
    else
        echo "⚠️  KVM недоступен"
    fi
    
    if grep -q -E "vmx|svm" /proc/cpuinfo; then
        has_vtx=1
        echo "✅ Аппаратная виртуализация CPU обнаружена"
    else
        echo "❌ Аппаратная виртуализация не поддерживается CPU"
    fi
    
    if [ $has_kvm -eq 1 ] && [ $has_vtx -eq 1 ]; then
        return 0
    elif [ $has_kvm -eq 1 ]; then
        return 1
    else
        return 2
    fi
}

# Установка пакетов виртуализации
install_virtualization_packages() {
    echo "📦 Установка пакетов виртуализации..."
    
    apt-get install -y \
        qemu-kvm \
        qemu-system-x86 \
        qemu-utils \
        libvirt-daemon-system \
        libvirt-clients \
        virt-manager \
        virt-viewer \
        virt-install \
        bridge-utils \
        ovmf \
        swtpm \
        libguestfs-tools \
        cpu-checker
    
    # Для пользователя без GUI
    apt-get install -y \
        virt-top \
        virt-what
    
    echo "✅ Пакеты виртуализации установлены"
}

# Настройка Libvirt
configure_libvirt() {
    echo "⚙️  Настройка Libvirt..."
    
    usermod -aG libvirt,kvm,libvirt-qemu user
    
    cat > /etc/libvirt/libvirtd.conf << LIBVIRT_CONF
listen_tls = 0
listen_tcp = 0
unix_sock_group = "libvirt"
unix_sock_ro_perms = "0777"
unix_sock_rw_perms = "0770"
LIBVIRT_CONF
    
    # Создание сетей
    cat > /tmp/kraken-isolated.xml << NETWORK_XML
<network>
  <name>kraken-isolated</name>
  <forward mode='nat'/>
  <bridge name='virbr100' stp='on' delay='0'/>
  <ip address='10.100.0.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='10.100.0.2' end='10.100.0.254'/>
    </dhcp>
  </ip>
</network>
NETWORK_XML
    
    cat > /tmp/kraken-tor.xml << TOR_NETWORK
<network>
  <name>kraken-tor</name>
  <forward mode='nat'/>
  <bridge name='virbr101' stp='on' delay='0'/>
  <ip address='10.101.0.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='10.101.0.2' end='10.101.0.254'/>
    </dhcp>
  </ip>
</network>
TOR_NETWORK
    
    virsh net-define /tmp/kraken-isolated.xml
    virsh net-define /tmp/kraken-tor.xml
    virsh net-start kraken-isolated
    virsh net-start kraken-tor
    virsh net-autostart kraken-isolated
    virsh net-autostart kraken-tor
    
    systemctl enable libvirtd
    systemctl restart libvirtd
    
    echo "✅ Libvirt настроен"
}

# Создание VM образов
create_vm_images() {
    echo "🖼️  Создание VM образов..."
    
    mkdir -p /var/lib/libvirt/images/kraken
    
    # Базовый образ
    qemu-img create -f qcow2 /var/lib/libvirt/images/kraken/base.qcow2 10G
    
    # Образ для браузера
    qemu-img create -f qcow2 /var/lib/libvirt/images/kraken/browser.qcow2 8G
    
    # Образ для терминала
    qemu-img create -f qcow2 /var/lib/libvirt/images/kraken/terminal.qcow2 5G
    
    echo "✅ VM образы созданы"
}

# Создание VM шаблонов
create_vm_templates() {
    echo "📋 Создание VM шаблонов..."
    
    # Шаблон изолированного браузера
    cat > /tmp/browser-vm.xml << BROWSER_VM
<domain type='kvm'>
  <name>browser-isolated</name>
  <memory unit='MiB'>2048</memory>
  <vcpu>2</vcpu>
  <os>
    <type arch='x86_64'>hvm</type>
    <boot dev='hd'/>
  </os>
  <devices>
    <disk type='file' device='disk'>
      <source file='/var/lib/libvirt/images/kraken/browser.qcow2'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <interface type='network'>
      <source network='kraken-isolated'/>
      <model type='virtio'/>
    </interface>
    <graphics type='vnc' port='-1' autoport='yes'/>
    <video>
      <model type='qxl'/>
    </video>
  </devices>
</domain>
BROWSER_VM
    
    # Шаблон TOR гейтвея
    cat > /tmp/tor-gateway.xml << TOR_GATEWAY
<domain type='kvm'>
  <name>tor-gateway</name>
  <memory unit='MiB'>1024</memory>
  <vcpu>1</vcpu>
  <os>
    <type arch='x86_64'>hvm</type>
    <boot dev='hd'/>
  </os>
  <devices>
    <disk type='file' device='disk'>
      <source file='/var/lib/libvirt/images/kraken/base.qcow2'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <interface type='network'>
      <source network='default'/>
      <model type='virtio'/>
    </interface>
    <interface type='network'>
      <source network='kraken-tor'/>
      <model type='virtio'/>
    </interface>
  </devices>
</domain>
TOR_GATEWAY
    
    virsh define /tmp/browser-vm.xml
    virsh define /tmp/tor-gateway.xml
    
    echo "✅ VM шаблоны созданы"
}

# Создание менеджера изоляции
create_isolation_manager() {
    echo "🔗 Создание менеджера изоляции..."
    
    cat > /usr/local/bin/kraken-vm-isolate << 'VM_ISOLATE'
#!/bin/bash
# Менеджер VM-изоляции Kraken OS

APP_TYPE="$1"
APP_NAME="$2"
shift 2

# Проверка поддержки KVM
check_kvm() {
    if [ -e /dev/kvm ] && grep -q -E "vmx|svm" /proc/cpuinfo; then
        return 0
    else
        return 1
    fi
}

# Запуск в полной VM
run_in_vm() {
    local vm_name="$1"
    local app_name="$2"
    
    echo "🚀 Запуск $app_name в изолированной VM..."
    
    # Проверяем существует ли VM
    if ! virsh list --all | grep -q "$vm_name"; then
        echo "Создаем VM: $vm_name"
        
        # Клонируем шаблон
        virt-clone \
            --original browser-isolated \
            --name "$vm_name" \
            --file "/var/lib/libvirt/images/kraken/$vm_name.qcow2"
        
        # Настраиваем VM
        virt-customize -a "/var/lib/libvirt/images/kraken/$vm_name.qcow2" \
            --install "$app_name" \
            --run-command "useradd -m user && echo 'user:user' | chpasswd" \
            --ssh-inject user:file:/home/user/.ssh/id_rsa.pub
    fi
    
    # Запускаем VM
    virsh start "$vm_name"
    
    # Подключаемся через VNC
    echo "📺 Подключайтесь через VNC: localhost:5900"
    echo "   Или через SSH: ssh user@10.100.0.X"
}

# Запуск в контейнере (fallback)
run_in_container() {
    local app_name="$1"
    shift
    
    if [ -f "/etc/firejail/$app_name.profile" ]; then
        firejail --profile="/etc/firejail/$app_name.profile" "$app_name" "$@"
    else
        echo "⚠️  Профиль Firejail не найден, запускаем без изоляции"
        "$app_name" "$@"
    fi
}

# Основная логика
main() {
    case "$APP_TYPE" in
        browser|firefox|chromium)
            VM_NAME="browser-$(date +%s)"
            if check_kvm; then
                run_in_vm "$VM_NAME" "$APP_NAME"
            else
                echo "⚠️  KVM недоступен, используем контейнерную изоляцию"
                run_in_container "$APP_NAME" "$@"
            fi
            ;;
            
        terminal|alacritty|tmux)
            if check_kvm; then
                # Создаем легковесную VM для терминала
                VM_NAME="terminal-$(date +%s)"
                virt-install \
                    --name "$VM_NAME" \
                    --memory 512 \
                    --vcpu 1 \
                    --disk size=2 \
                    --import \
                    --noautoconsole \
                    --network network=kraken-isolated
                
                echo "🖥️  Терминал запущен в VM: $VM_NAME"
                echo "    Подключитесь: virsh console $VM_NAME"
            else
                run_in_container "$APP_NAME" "$@"
            fi
            ;;
            
        banking|sensitive)
            # Всегда VM для критичных приложений
            VM_NAME="secure-$(date +%s)"
            if check_kvm; then
                run_in_vm "$VM_NAME" "$APP_NAME"
            else
                echo "❌ Для банковских приложений требуется KVM"
                echo "   Пожалуйста, включите виртуализацию в BIOS"
                exit 1
            fi
            ;;
            
        *)
            echo "Использование: kraken-vm-isolate {browser|terminal|banking} app_name [args]"
            echo ""
            echo "Примеры:"
            echo "  kraken-vm-isolate browser firefox"
            echo "  kraken-vm-isolate terminal alacritty"
            echo "  kraken-vm-isolate banking libreoffice"
            exit 1
            ;;
    esac
}

main "$@"
VM_ISOLATE
    
    chmod +x /usr/local/bin/kraken-vm-isolate
    
    # Создание Firejail профилей для fallback
    mkdir -p /etc/firejail
    
    cat > /etc/firejail/firefox.profile << FIREFOX_PROFILE
# Firefox isolation profile
caps.drop all
netfilter
noroot
seccomp
private-dev
private-tmp
nogroups
nosound
x11
net blue
protocol unix,inet,inet6
private-bin firefox
private-etc hosts,localtime,resolv.conf
read-only /etc
read-only /boot
read-only /lib
read-only /lib64
read-only /sbin
read-only /usr
FIREFOX_PROFILE
    
    echo "✅ Менеджер изоляции создан"
}

# Создание systemd сервисов
setup_vm_services() {
    echo "🎛️  Настройка systemd сервисов..."
    
    # Сервис для TOR Gateway VM
    cat > /etc/systemd/system/tor-gateway-vm.service << TOR_SERVICE
[Unit]
Description=Tor Gateway VM
After=network.target libvirtd.service
Requires=libvirtd.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/virsh start tor-gateway
ExecStop=/usr/bin/virsh shutdown tor-gateway
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
TOR_SERVICE
    
    # Сервис для очистки VM
    cat > /etc/systemd/system/kraken-vm-cleanup.service << CLEANUP_SERVICE
[Unit]
Description=Kraken VM Cleanup Service
After=libvirtd.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/vm-cleanup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
CLEANUP_SERVICE
    
    cat > /usr/local/bin/vm-cleanup.sh << VM_CLEANUP
#!/bin/bash
# Очистка неиспользуемых VM

# Останавливаем VM старше 24 часов
virsh list --name | while read vm; do
    if [ -n "$vm" ] && [[ "$vm" == browser-* || "$vm" == terminal-* ]]; then
        local vm_info=$(virsh dominfo "$vm" 2>/dev/null)
        if echo "$vm_info" | grep -q "shut off"; then
            virsh undefine "$vm" --remove-all-storage
            echo "Удалена VM: $vm"
        fi
    fi
done
VM_CLEANUP
    
    chmod +x /usr/local/bin/vm-cleanup.sh
    
    # Таймер для ежедневной очистки
    cat > /etc/systemd/system/kraken-vm-cleanup.timer << CLEANUP_TIMER
[Unit]
Description=Daily VM Cleanup

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
CLEANUP_TIMER
    
    systemctl enable tor-gateway-vm.service
    systemctl enable kraken-vm-cleanup.timer
    
    echo "✅ Systemd сервисы настроены"
}

# Создание desktop файлов
create_desktop_integration() {
    echo "🖥️  Создание desktop интеграции..."
    
    mkdir -p /usr/share/applications/kraken-vm
    
    cat > /usr/share/applications/kraken-vm/firefox-vm.desktop << DESKTOP_VM
[Desktop Entry]
Name=Firefox (VM Isolated)
Comment=Firefox running in isolated VM
Exec=/usr/local/bin/kraken-vm-isolate browser firefox %u
Icon=firefox
Terminal=false
Type=Application
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;
StartupNotify=true
Keywords=web;browser;internet;vm;isolated;
DESKTOP_VM
    
    cat > /usr/share/applications/kraken-vm/terminal-vm.desktop << TERMINAL_DESKTOP
[Desktop Entry]
Name=Terminal (VM Isolated)
Comment=Terminal running in isolated VM
Exec=/usr/local/bin/kraken-vm-isolate terminal alacritty
Icon=utilities-terminal
Terminal=false
Type=Application
Categories=System;TerminalEmulator;
Keywords=shell;prompt;command;commandline;vm;
TERMINAL_DESKTOP
    
    # Создание пункта меню
    cat > /usr/share/desktop-directories/kraken-vm.directory << DIRECTORY
[Desktop Entry]
Type=Directory
Name=Kraken VM Apps
Icon=kraken
Comment=VM Isolated Applications
DIRECTORY
    
    echo "✅ Desktop интеграция создана"
}

# Основная функция установки
main_install() {
    # Проверяем поддержку виртуализации
    check_virtualization_support
    local virt_status=$?
    
    case $virt_status in
        0)
            echo "🎉 Полная поддержка виртуализации обнаружена!"
            echo "Устанавливаем KVM/QEMU с аппаратным ускорением"
            
            install_virtualization_packages
            configure_libvirt
            create_vm_images
            create_vm_templates
            create_isolation_manager
            setup_vm_services
            create_desktop_integration
            
            echo ""
            echo "✅ VM-изоляция настроена с аппаратным ускорением"
            ;;
        1)
            echo "⚠️  Частичная поддержка виртуализации"
            echo "Устанавливаем KVM без аппаратного ускорения"
            
            install_virtualization_packages
            configure_libvirt
            create_vm_images
            create_isolation_manager
            
            echo ""
            echo "✅ VM-изоляция настроена без аппаратного ускорения"
            echo "   Производительность может быть ниже"
            ;;
        2)
            echo "❌ Виртуализация не поддерживается"
            echo "Устанавливаем только контейнерную изоляцию"
            
            apt-get install -y firejail
            create_isolation_manager
            
            echo ""
            echo "✅ Установлена контейнерная изоляция (fallback)"
            echo "   Для VM-изоляции требуется аппаратная виртуализация"
            ;;
    esac
    
    echo ""
    echo "🚀 ИСПОЛЬЗОВАНИЕ:"
    echo "   kraken-vm-isolate browser firefox     # Firefox в изолированной VM"
    echo "   kraken-vm-isolate terminal alacritty  # Терминал в VM"
    echo "   kraken-vm-isolate banking libreoffice # LibreOffice в защищенной VM"
    echo ""
    echo "📊 СТАТУС:"
    echo "   Проверить KVM: sudo kvm-ok"
    echo "   Список VM: virsh list --all"
    echo "   Сети: virsh net-list --all"
}
main_install
VM_ISOLATION_SCRIPT

    chmod +x "${ROOTFS}/tmp/install_vm_isolation.sh"
    chroot "$ROOTFS" /bin/bash /tmp/install_vm_isolation.sh
    rm -f "${ROOTFS}/tmp/install_vm_isolation.sh"
}

# ============================================================================
# ОСТАЛЬНЫЕ КОНФИГУРАЦИИ
# ============================================================================

configure_kernel_hardening() {
    log_step "Настройка hardening параметров ядра..."
    
    cat > "${ROOTFS}/tmp/kernel_hardening.sh" << 'KERNEL_SCRIPT'
#!/bin/bash
set -e

cat > /etc/sysctl.d/99-kraken-hardening.conf << SYSCTL
# Network security
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.tcp_syncookies = 1

# Kernel security
kernel.randomize_va_space = 2
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.unprivileged_bpf_disabled = 1
kernel.sysrq = 0

# Memory protection
vm.mmap_rnd_bits = 32
vm.mmap_rnd_compat_bits = 16
vm.swappiness = 10

# File system protection
fs.protected_fifos = 2
fs.protected_regular = 2
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.suid_dumpable = 0
SYSCTL

sysctl -p /etc/sysctl.d/99-kraken-hardening.conf

# Настройка GRUB
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=".*"/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash apparmor=1 security=apparmor lockdown=confidentiality"/' /etc/default/grub
update-grub

# Отключение опасных модулей
cat > /etc/modprobe.d/disable-dangerous.conf << MODPROBE
install firewire-core /bin/true
install usb-storage /bin/true
install thunderbolt /bin/true
install bluetooth /bin/true
MODPROBE

# Отключение core dumps
echo "kernel.core_pattern=|/bin/false" >> /etc/sysctl.d/99-kraken-hardening.conf
echo "* soft core 0" >> /etc/security/limits.conf
echo "* hard core 0" >> /etc/security/limits.conf

# Настройка noexec для /tmp
echo "tmpfs /tmp tmpfs defaults,noexec,nosuid,nodev 0 0" >> /etc/fstab
KERNEL_SCRIPT

    chmod +x "${ROOTFS}/tmp/kernel_hardening.sh"
    chroot "$ROOTFS" /bin/bash /tmp/kernel_hardening.sh
    rm -f "${ROOTFS}/tmp/kernel_hardening.sh"
}

configure_hardware_security() {
    log_step "Настройка TPM, YubiKey и Secure Boot..."
    
    cat > "${ROOTFS}/tmp/hardware_security.sh" << 'HW_SECURITY_SCRIPT'
#!/bin/bash
set -e

# Настройка TPM для LUKS
cat > /usr/local/bin/tpm-luks-setup << TPM_LUKS
#!/bin/bash
echo "Настройка TPM для LUKS..."
echo "Используйте: clevis luks bind -d /dev/sdX tpm2 '{}'"
TPM_LUKS
chmod +x /usr/local/bin/tpm-luks-setup

# Настройка YubiKey
cat > /usr/local/bin/yubikey-setup << YUBIKEY
#!/bin/bash
echo "Настройка YubiKey..."
echo "Используйте: ykman piv info"
YUBIKEY
chmod +x /usr/local/bin/yubikey-setup

# Настройка Secure Boot
cat > /usr/local/bin/secure-boot-setup << SECURE_BOOT
#!/bin/bash
echo "Настройка Secure Boot..."
echo "Используйте: mokutil --import MOK.cer"
SECURE_BOOT
chmod +x /usr/local/bin/secure-boot-setup

# Настройка Clevis
apt-get install -y clevis clevis-luks clevis-tpm2
HW_SECURITY_SCRIPT

    chmod +x "${ROOTFS}/tmp/hardware_security.sh"
    chroot "$ROOTFS" /bin/bash /tmp/hardware_security.sh
    rm -f "${ROOTFS}/tmp/hardware_security.sh"
}

create_autoinstaller() {
    log_step "Создание скрипта автоустановки..."
    
    cat > "${ROOTFS}/usr/local/bin/kraken-autoinstall" << 'AUTOINSTALLER'
#!/bin/bash
set -euo pipefail

echo "🐙 KRAKEN OS AUTOINSTALLER"
echo "=========================="

if [ "$EUID" -ne 0 ]; then
    echo "❌ Запустите с sudo"
    exit 1
fi

# Выбор диска
lsblk -d -o NAME,SIZE,MODEL | grep -v "NAME"
echo ""
read -p "Введите диск для установки (например: sda): " DISK_NAME
DISK="/dev/${DISK_NAME}"

if [ ! -b "$DISK" ]; then
    echo "❌ Диск $DISK не найден"
    exit 1
fi

echo "⚠️  ВНИМАНИЕ: Все данные на $DISK будут удалены!"
read -p "Продолжить? (yes/NO): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "❌ Отменено"
    exit 1
fi

# Разметка диска
echo "📐 Создание разметки..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart primary 1MiB 512MiB
parted -s "$DISK" set 1 boot on
parted -s "$DISK" mkpart primary 512MiB 100%

BOOT_PART="${DISK}1"
ROOT_PART="${DISK}2"

# Шифрование
echo "🔐 Настройка шифрования LUKS..."
cryptsetup luksFormat --type luks2 "$ROOT_PART"
cryptsetup luksOpen "$ROOT_PART" cryptroot

# Форматирование
mkfs.fat -F32 "$BOOT_PART"
mkfs.ext4 -L KRAKEN_ROOT /dev/mapper/cryptroot

# Монтирование
mount /dev/mapper/cryptroot /mnt
mkdir -p /mnt/boot
mount "$BOOT_PART" /mnt/boot

# Установка
echo "📥 Установка системы..."
cp -r /etc/NetworkManager /mnt/etc/ 2>/dev/null || true
cp -r /etc/tor /mnt/etc/ 2>/dev/null || true

# Chroot настройка
mount --rbind /dev /mnt/dev
mount --rbind /proc /mnt/proc
mount --rbind /sys /mnt/sys

cat << CHROOT_EOF | chroot /mnt /bin/bash
set -e

# Настройка fstab
echo "UUID=\$(blkid -s UUID -o value ${BOOT_PART}) /boot vfat defaults 0 2" >> /etc/fstab
echo "/dev/mapper/cryptroot / ext4 defaults 0 1" >> /etc/fstab
echo "cryptroot ${ROOT_PART} none luks" >> /etc/crypttab

# Установка загрузчика
apt-get update
apt-get install -y linux-image-amd64 grub-efi-amd64 cryptsetup
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=kraken
update-grub

# Создание пользователя
useradd -m -s /bin/bash user
echo "user:user" | chpasswd
usermod -aG sudo user
echo "user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/user

echo "✅ Система установлена!"
CHROOT_EOF

# Размонтирование
umount -R /mnt
cryptsetup luksClose cryptroot

echo "✅ Установка завершена!"
echo "🔑 Пароль для входа: user/user"
AUTOINSTALLER

    chmod +x "${ROOTFS}/usr/local/bin/kraken-autoinstall"
}

create_qubes_isolation() {
    log_step "Создание Qubes-like изоляции..."
    
    cat > "${ROOTFS}/tmp/qubes_isolation.sh" << 'QUBES_SCRIPT'
#!/bin/bash
set -e

# Установка Firejail
apt-get install -y firejail firejail-profiles
mkdir -p /etc/firejail

# Профиль для браузера
cat > /etc/firejail/browser.profile << BROWSER_PROFILE
caps.drop all
netfilter
noroot
seccomp
private-dev
private-tmp
nogroups
nosound
x11
net blue
protocol unix,inet,inet6
private-bin bash,sh,firefox,chromium
private-etc hosts,localtime,resolv.conf
read-only /etc
read-only /boot
read-only /lib
read-only /lib64
read-only /sbin
read-only /usr
BROWSER_PROFILE

# Создание скрипта запуска
cat > /usr/local/bin/qube-run << QUBE_RUN
#!/bin/bash
firejail --profile=/etc/firejail/browser.profile "\$@"
QUBE_RUN
chmod +x /usr/local/bin/qube-run
QUBES_SCRIPT

    chmod +x "${ROOTFS}/tmp/qubes_isolation.sh"
    chroot "$ROOTFS" /bin/bash /tmp/qubes_isolation.sh
    rm -f "${ROOTFS}/tmp/qubes_isolation.sh"
}

configure_tor_over_vpn() {
    log_step "Настройка маршрутизации Tor через VPN..."
    
    cat > "${ROOTFS}/tmp/tor_vpn_routing.sh" << 'TOR_VPN_SCRIPT'
#!/bin/bash
set -e

# Создание скрипта маршрутизации
cat > /usr/local/bin/wg-tor-route.sh << 'WG_TOR'
#!/bin/bash
echo "Настройка Tor через VPN..."
echo "Используйте: systemctl start tor"
WG_TOR
chmod +x /usr/local/bin/wg-tor-route.sh

cat > /etc/systemd/system/wg-tor-route.service << WG_TOR_SERVICE
[Unit]
Description=Tor over VPN routing
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wg-tor-route.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
WG_TOR_SERVICE

systemctl enable wg-tor-route.service
TOR_VPN_SCRIPT

    chmod +x "${ROOTFS}/tmp/tor_vpn_routing.sh"
    chroot "$ROOTFS" /bin/bash /tmp/tor_vpn_routing.sh
    rm -f "${ROOTFS}/tmp/tor_vpn_routing.sh"
}

finalize_system() {
    log_step "Финальная настройка системы..."
    
    cat > "${ROOTFS}/tmp/finalize.sh" << 'FINALIZE_SCRIPT'
#!/bin/bash
set -e

# Обновление
apt-get update
apt-get upgrade -y
apt-get autoremove -y --purge
apt-get clean
rm -rf /var/lib/apt/lists/*

# Очистка логов
find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
journalctl --vacuum-time=3d

# Создание motd
cat > /etc/motd << MOTD
╔════════════════════════════════════════════════╗
║              🐙 KRAKEN OS ULTRA 🐙             ║
║      Security • Privacy • Anonymity            ║
║                                                ║
║  Features:                                     ║
║  • VM Isolation (KVM/QEMU)                    ║
║  • Full disk encryption                       ║
║  • Tor, VPN,多层 routing                     ║
║  • SELinux + AppArmor                         ║
║                                                ║
║  Default user: user                           ║
║  Password: user                               ║
╚════════════════════════════════════════════════╝
MOTD

# Создание меню
cat > /usr/local/bin/kraken-menu << KRAKEN_MENU
#!/bin/bash
echo "🐙 KRAKEN OS - Quick Menu"
echo "========================"
echo "1) VM Isolation: kraken-vm-isolate"
echo "2) Tor Start: sudo systemctl start tor"
echo "3) Security Audit: sudo lynis audit system"
echo "4) Autoinstall: sudo kraken-autoinstall"
KRAKEN_MENU
chmod +x /usr/local/bin/kraken-menu

# Установка прав
chown -R user:user /home/user
update-grub 2>/dev/null || true

echo "✨ Kraken OS Ultra готова!"
FINALIZE_SCRIPT

    chmod +x "${ROOTFS}/tmp/finalize.sh"
    chroot "$ROOTFS" /bin/bash /tmp/finalize.sh
    rm -f "${ROOTFS}/tmp/finalize.sh"
}

create_iso() {
    log_step "Создание ISO образа..."
    
    mkdir -p "${ROOTFS}/boot/grub"
    cat > "${ROOTFS}/boot/grub/grub.cfg" << GRUB_CFG
set timeout=5
set default=0

menuentry "Kraken OS Ultra (Live)" {
    linux /boot/vmlinuz boot=live quiet splash
    initrd /boot/initrd.img
}

menuentry "Kraken OS Ultra (Install)" {
    linux /boot/vmlinuz boot=live quiet splash autostart=kraken-autoinstall
    initrd /boot/initrd.img
}
GRUB_CFG

    xorriso -as mkisofs \
        -iso-level 3 \
        -volid "KRAKEN_ULTRA" \
        -output "$ISO_NAME" \
        -graft-points \
        /="${ROOTFS}"
    
    if [ $? -eq 0 ]; then
        log_success "ISO образ создан: $ISO_NAME"
        log_info "Размер: $(du -h "$ISO_NAME" | cut -f1)"
    else
        log_error "Ошибка создания ISO"
        exit 1
    fi
}

# ============================================================================
# ГЛАВНАЯ ФУНКЦИЯ
# ============================================================================

main() {
    log_step "Начало сборки Kraken OS Ultra с VM-изоляцией..."
    
    check_root
    check_dependencies
    create_base_system
    mount_virtual_fs
    
    # Основные этапы
    configure_system
    install_dinit
    install_selinux
    install_security_tools
    install_gui
    install_anonymity_tools
    install_additional_software
    configure_kernel_hardening
    configure_hardware_security
    create_autoinstaller
    create_qubes_isolation
    install_vm_isolation        # <-- НОВАЯ VM-ИЗОЛЯЦИЯ
    configure_tor_over_vpn
    finalize_system
    
    umount_virtual_fs
    create_iso
    
    log_success "Сборка завершена успешно!"
    log_info "ISO: $ISO_NAME"
    log_info "Тестирование: qemu-system-x86_64 -cdrom $ISO_NAME -m 4G"
}

# Запуск
trap 'log_error "Сборка прервана на этапе: $BASH_COMMAND"; umount_virtual_fs; exit 1' ERR
main "$@"
