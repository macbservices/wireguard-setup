#!/bin/bash

# Função para verificar e instalar pacotes necessários
install_dependencies() {
    echo "Verificando e instalando dependências necessárias..."

    # Atualiza o sistema
    sudo apt update -y

    # Instala pacotes essenciais
    sudo apt install -y \
        nmap \
        wireguard \
        wireguard-tools \
        curl \
        iptables \
        dnsutils \
        iproute2 \
        ufw

    echo "Dependências instaladas com sucesso!"
}

# Função principal do script
setup_wireguard() {
    # Verificar se o WireGuard já está instalado
    if ! command -v wg &> /dev/null; then
        echo "WireGuard não encontrado. Instalando..."
        install_dependencies
    else
        echo "WireGuard já está instalado!"
    fi

    # Perguntar pelo range IP da rede privada
    read -p "Digite o range IP da sua rede privada (exemplo: 100.102.90.0/24): " PRIVATE_RANGE
    echo "Range IP da rede privada configurado como $PRIVATE_RANGE"

    # Perguntar pelo range IP fictício
    read -p "Digite o range IP para os IPs fictícios (exemplo: 100.100.100.0/24): " FICTITIOUS_RANGE
    echo "Range IP fictício configurado como $FICTITIOUS_RANGE"

    # Perguntar qual porta será usada pelo WireGuard
    read -p "Digite a porta para o WireGuard (exemplo: 51820): " WG_PORT
    echo "Porta do WireGuard configurada como $WG_PORT"

    # Criar o arquivo de configuração do WireGuard
    WG_CONF="/etc/wireguard/wg0.conf"

    # Gerar chaves privadas e públicas
    PRIVATE_KEY=$(wg genkey)
    PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)
    echo "Chaves geradas com sucesso!"

    # Criar configuração do WireGuard
    echo "[Interface]" > $WG_CONF
    echo "PrivateKey = $PRIVATE_KEY" >> $WG_CONF
    echo "Address = $FICTITIOUS_RANGE" >> $WG_CONF
    echo "ListenPort = $WG_PORT" >> $WG_CONF
    echo "SaveConfig = true" >> $WG_CONF
    echo "" >> $WG_CONF
    echo "[Peer]" >> $WG_CONF
    echo "PublicKey = $PUBLIC_KEY" >> $WG_CONF
    echo "AllowedIPs = $PRIVATE_RANGE" >> $WG_CONF

    # Reiniciar o WireGuard para aplicar a configuração
    sudo systemctl restart wg-quick@wg0
    sudo systemctl enable wg-quick@wg0
    echo "WireGuard configurado e iniciado com sucesso!"
}

# Iniciar o processo
setup_wireguard
