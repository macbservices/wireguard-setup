#!/bin/bash

# Configurações gerais
WIREGUARD_INTERFACE="wg0"
WG_CONF="/etc/wireguard/$WIREGUARD_INTERFACE.conf"
LOG="/var/log/wireguard-scan.log"

# Verificar permissões de root
if [[ $EUID -ne 0 ]]; then
    echo "Este script precisa ser executado como root!"
    exit 1
fi

# Garantir que o script seja executável
chmod +x "$0"

# Dependências necessárias
DEPENDENCIAS=("nmap" "wireguard-tools" "iptables" "tc")

# Função para instalar dependências ausentes
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

# Escanear IPs na rede
escanear_ips() {
    echo "Escaneando IPs na rede privada..."
    IP_LIST=$(nmap -sn 100.102.90.0/24 | grep "Nmap scan report for" | awk '{print $NF}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')

    if [ -z "$IP_LIST" ]; then
        echo "Nenhum dispositivo encontrado na rede."
        return
    fi

    echo "Dispositivos encontrados:"
    echo "$IP_LIST"
    echo

    for PRIVATE_IP in $IP_LIST; do
        echo "Processando o IP $PRIVATE_IP..."

        # Perguntar se deseja atribuir um IP fictício
        read -p "Deseja atribuir um IP fictício para $PRIVATE_IP? (S/N): " ATRIBUIR_IP
        if [[ "$ATRIBUIR_IP" =~ ^[Ss]$ ]]; then
            read -p "Digite o IP fictício (exemplo: 100.100.100.x): " FICTICIO_IP
            if ! grep -q "$PRIVATE_IP" $WG_CONF; then
                echo "Adicionando configuração para $PRIVATE_IP -> $FICTICIO_IP..."
                echo -e "\n[Peer]\nAllowedIPs = $PRIVATE_IP/32\nEndpoint = $FICTICIO_IP:51820" >> $WG_CONF
            else
                echo "O IP $PRIVATE_IP já possui um IP fictício configurado."
            fi
        fi

        # Listar portas já liberadas
        echo "Portas já liberadas para $PRIVATE_IP:"
        iptables -L FORWARD -v -n | grep "$PRIVATE_IP"

        # Perguntar se deseja liberar novas portas
        read -p "Deseja liberar novas portas para $PRIVATE_IP? (S/N): " CONFIG_PORTAS
        if [[ "$CONFIG_PORTAS" =~ ^[Ss]$ ]]; then
            read -p "Digite as portas a liberar (separadas por espaço): " PORTAS
            for PORTA in $PORTAS; do
                echo "Liberando porta $PORTA para $PRIVATE_IP..."
                iptables -A FORWARD -p tcp --dport "$PORTA" -d "$PRIVATE_IP" -j ACCEPT
                iptables -A FORWARD -p udp --dport "$PORTA" -d "$PRIVATE_IP" -j ACCEPT
            done
        fi

        # Configurar limite de velocidade
        read -p "Deseja configurar limite de velocidade para $PRIVATE_IP? (S/N): " CONFIG_LIMITE
        if [[ "$CONFIG_LIMITE" =~ ^[Ss]$ ]]; then
            read -p "Digite a velocidade (em Mbps ou 'full' para ilimitado): " VELOCIDADE
            if [[ "$VELOCIDADE" == "full" ]]; then
                echo "Liberando velocidade ilimitada para $PRIVATE_IP..."
                tc qdisc del dev $WIREGUARD_INTERFACE root >/dev/null 2>&1
            else
                echo "Configurando limite de velocidade para $PRIVATE_IP: $VELOCIDADE Mbps..."
                tc qdisc add dev $WIREGUARD_INTERFACE root handle 1: htb default 11
                tc class add dev $WIREGUARD_INTERFACE parent 1: classid 1:1 htb rate "${VELOCIDADE}mbit"
                tc filter add dev $WIREGUARD_INTERFACE protocol ip parent 1: prio 1 u32 match ip dst "$PRIVATE_IP" flowid 1:1
            fi
        fi
    done
}

# Executar funções principais
instalar_dependencias
escanear_ips
echo "Processo concluído! Verifique as configurações realizadas no WireGuard."
