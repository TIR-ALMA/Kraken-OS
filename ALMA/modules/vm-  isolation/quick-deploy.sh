#!/bin/bash
# Быстрое развертывание VM окружений

deploy_whonix_like() {
    echo "🔄 Развертывание Whonix-like окружения..."
    
    # Gateway VM
    virt-install \
        --name anon-gateway \
        --memory 1024 \
        --vcpu 1 \
        --disk size=5 \
        --import \
        --noautoconsole \
        --network network=default \
        --network network=kraken-tor
    
    # Workstation VM
    virt-install \
        --name anon-workstation \
        --memory 2048 \
        --vcpu 2 \
        --disk size=10 \
        --import \
        --noautoconsole \
        --network network=kraken-tor
    
    echo "✅ Whonix-like окружение развернуто"
}

deploy_split_browser() {
    echo "🔄 Развертывание split-browser..."
    
    # Браузер для просмотра
    virt-install \
        --name browser-view \
        --memory 2048 \
        --vcpu 2 \
        --disk size=8 \
        --import \
        --noautoconsole \
        --network network=kraken-tor
    
    # Браузер для логинов
    virt-install \
        --name browser-auth \
        --memory 2048 \
        --vcpu 2 \
        --disk size=8 \
        --import \
        --noautoconsole \
        --network network=kraken-isolated
    
    echo "✅ Split-browser окружение развернуто"
}

main() {
    echo "🐙 Быстрое развертывание VM окружений"
    echo "===================================="
    echo "1) Whonix-like (анонимность)"
    echo "2) Split-browser (разделение)"
    echo "3) Forensics lab"
    read -p "Выбор: " choice
    
    case $choice in
        1) deploy_whonix_like ;;
        2) deploy_split_browser ;;
        3) echo "В разработке..." ;;
        *) echo "Неверный выбор" ;;
    esac
}

main "$@"
