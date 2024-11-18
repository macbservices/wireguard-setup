#!/bin/bash

# Configurações gerais
WIREGUARD_INTERFACE="wg0"
PRIVATE_IP_RANGE="100.102.90.0/24"
FAKE_IP_BASE="100.100.100"
WG_CONF="/etc/wireguard/$WIREGUARD_INTERFACE.conf"
DEPENDENCIAS=("nmap" "wireguard-tools" "iptables")
LOG="/var/log/wireguard-setup.log"

# Função para verificar se o script está sendo executado como root
verificar_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Este script precisa ser executado como root!"
        exit 1
    fi
}

# Função para instalar dependências
instalar_dependencias() {
    echo "Verificando dependências necessárias..."
    for PACOTE in "${DEPENDENCIAS[@]}"; do
        if ! command -v "$PACOTE" >/dev/null 2>&1; then
            echo "Instalando $PACOTE..."
            apt-get update && apt-get install -y "$PACOTE"
        else
            echo "$PACOTE já está instalado."
        fi
    done
}

# Função para configurar o WireGuard
configurar_wireguard() {
    if [[ ! -f $WG_CONF ]]; then
        echo "Configurando WireGuard..."
        apt-get install -y wireguard
        umask 077
        wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey
        cat >$WG_CONF <<EOL
[Interface]
PrivateKey = $(cat /etc/wireguard/privatekey)
Address = $FAKE_IP_BASE.1/24
ListenPort = 51820
EOL
        systemctl enable wg-quick@$WIREGUARD_INTERFACE
        systemctl start wg-quick@$WIREGUARD_INTERFACE
    else
        echo "WireGuard já está configurado."
    fi
}

# Função para identificar dispositivo pelo IP
identificar_dispositivo() {
    local ip="$1"
    local tipo=$(nmap -O "$ip" 2>/dev/null | grep "Running:" | awk -F: '{print $2}' | xargs)
    echo "${tipo:-Desconhecido}"
}

# Função para processar cada IP encontrado
processar_ip() {
    local PRIVATE_IP="$1"
    echo "Processando o IP: $PRIVATE_IP"

    # Verificar se já existe configuração para o IP
    if grep -q "$PRIVATE_IP" $WG_CONF; then
        echo "O IP $PRIVATE_IP já possui configuração fictícia."
        return
    fi

    # Gerar IP fictício único
    LAST_OCTET=$(echo $PRIVATE_IP | awk -F. '{print $4}')
    FAKE_IP="$FAKE_IP_BASE.$LAST_OCTET"
    echo "Adicionando configuração para $PRIVATE_IP -> $FAKE_IP..."

    # Adicionar configuração ao WireGuard
    sudo bash -c "cat >> $WG_CONF" <<EOL

[Peer]
PublicKey = $(wg genkey | tee /etc/wireguard/$PRIVATE_IP.pub)
AllowedIPs = $FAKE_IP/32
EOL

    # Configurar NAT (SNAT/DNAT)
    sudo iptables -t nat -A PREROUTING -d $FAKE_IP -j DNAT --to-destination $PRIVATE_IP
    sudo iptables -t nat -A POSTROUTING -s $PRIVATE_IP -j SNAT --to-source $FAKE_IP
    sudo iptables -A FORWARD -d $PRIVATE_IP -j ACCEPT
    echo "Configuração adicionada para $PRIVATE_IP."
}

# Função principal para escanear IPs
escanear_ips() {
    echo "Reescanando a rede para encontrar dispositivos..."
    IP_LIST=$(nmap -sn $PRIVATE_IP_RANGE | grep "Nmap scan report for" | awk '{print $NF}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')

    if [ -z "$IP_LIST" ]; then
        echo "Nenhum dispositivo encontrado na rede privada."
        return
    fi

    echo "Dispositivos encontrados:"
    echo "$IP_LIST"
    echo

    # Processar cada IP encontrado
    for PRIVATE_IP in $IP_LIST; do
        processar_ip "$PRIVATE_IP"
        configurar_portas "$PRIVATE_IP"
    done
}

# Função para configurar portas adicionais
configurar_portas() {
    local PRIVATE_IP="$1"
    read -p "Deseja adicionar portas para $PRIVATE_IP? (S/N): " ADICIONAR_PORTAS
    if [[ "$ADICIONAR_PORTAS" =~ ^[Ss]$ ]]; then
        read -p "Digite as portas a liberar (separadas por espaço): " PORTAS
        for PORTA in $PORTAS; do
            echo "Liberando porta $PORTA para $PRIVATE_IP..."
            sudo iptables -A FORWARD -p tcp --dport $PORTA -d $PRIVATE_IP -j ACCEPT
            sudo iptables -A FORWARD -p udp --dport $PORTA -d $PRIVATE_IP -j ACCEPT
        done
    fi
}

# Função para configurar limite de velocidade
configurar_velocidade() {
    local PRIVATE_IP="$1"
    read -p "Deseja configurar a velocidade para $PRIVATE_IP? (S/N): " CONFIGURAR_VELOCIDADE
    if [[ "$CONFIGURAR_VELOCIDADE" =~ ^[Ss]$ ]]; then
        read -p "Digite a velocidade em Mbps (ou 'full' para liberar ilimitado): " VELOCIDADE
        if [[ "$VELOCIDADE" == "full" ]]; then
            echo "Configurando velocidade ilimitada para $PRIVATE_IP..."
            tc qdisc del dev $WIREGUARD_INTERFACE root >/dev/null 2>&1
        else
            echo "Configurando velocidade de $VELOCIDADE Mbps para $PRIVATE_IP..."
            tc qdisc add dev $WIREGUARD_INTERFACE root handle 1: htb default 11
            tc class add dev $WIREGUARD_INTERFACE parent 1: classid 1:1 htb rate "$VELOCIDADE"mbit
            tc filter add dev $WIREGUARD_INTERFACE protocol ip parent 1: prio 1 u32 match ip dst $PRIVATE_IP flowid 1:1
        fi
    fi
}

# Executar o script
verificar_root
instalar_dependencias
configurar_wireguard
escanear_ips

echo "Processo concluído! O WireGuard está pronto para uso."
