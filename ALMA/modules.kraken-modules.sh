#!/bin/bash
# Дополнительные модули для Kraken OS

# Модуль 1: Аудит безопасности
install_security_audit() {
    apt-get install -y \
        lynis \
        tiger \
        openscap \
        osquery \
        osqueryd
        
    lynis audit system --quick
}

# Модуль 2: Форензика
install_forensics() {
    apt-get install -y \
        autopsy \
        sleuthkit \
        guymager \
        dc3dd \
        testdisk \
        photorec \
        scalpel \
        foremost \
        binwalk
}

# Модуль 3: Криптовалюты
install_crypto() {
    apt-get install -y \
        bitcoin-qt \
        electrum \
        monero-wallet-gui \
        ledger-live-desktop
        
    echo "export ELECTRUM_TOR_PROXY=socks5://127.0.0.1:9050" >> /etc/profile
}

# Модуль 4: Разработка
install_development() {
    apt-get install -y \
        vscode \
        sublime-text \
        eclipse \
        android-studio \
        qtcreator
        
    apt-get install -y \
        python3 \
        python3-pip \
        nodejs \
        npm \
        golang \
        rustc \
        cargo \
        openjdk-17-jdk
        
    pip3 install django flask numpy pandas
    npm install -g vue react
}

# Модуль 5: ИИ и ML
install_ai() {
    apt-get install -y \
        python3-tensorflow \
        python3-keras \
        python3-scikit-learn \
        python3-opencv \
        jupyter \
        jupyterlab
}

# Меню модулей
show_menu() {
    echo "🐙 KRAKEN OS - Модули установки"
    echo "================================"
    echo "1) Аудит безопасности"
    echo "2) Форензика"
    echo "3) Криптовалюты"
    echo "4) Разработка"
    echo "5) Искусственный интеллект"
    echo "6) Все модули"
    echo "0) Выход"
    read -p "Выберите модуль: " choice
    
    case $choice in
        1) install_security_audit ;;
        2) install_forensics ;;
        3) install_crypto ;;
        4) install_development ;;
        5) install_ai ;;
        6)
            install_security_audit
            install_forensics
            install_crypto
            install_development
            install_ai
            ;;
        0) exit 0 ;;
        *) echo "Неверный выбор" ;;
    esac
}

main() {
    show_menu
    echo "✅ Модули установлены"
}

main "$@"
