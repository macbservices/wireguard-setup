#!/bin/bash

# Definições iniciais
WIREGUARD_INTERFACE="wg0"
PRIVATE_IP_RANGE="100.102.90.0/24" # Substitua pelo seu range de IPs privados
FAKE_IP_BASE="100.100.100"        # Substitua pelo range base para IPs fictícios
WG_CONF="/etc/wireguard/$WIREGUARD_INTERFACE.conf"

# Verificar se está sendo executado como root
if [[ $EUID -ne 0 ]]; then
    echo "Este script precisa ser executado como root!"
    exit 1
fi

# Instalar dependências necessárias
echo "Instalando dependências necessárias..."
apt update
apt install -y wireguard-tools iptables nmap ufw curl

# Configurar o WireGuard
if [[ ! -f $WG_CONF ]]; then
    echo "Configurando o WireGuard..."
    umask 077
    wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
    PRIVATE_KEY=$(cat /etc/wireguard/private.key)
    cat > $WG_CONF <<EOL
[Interface]
PrivateKey = $PRIVATE_KEY
Address = $FAKE_IP_BASE.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i $WIREGUARD_INTERFACE -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i $WIREGUARD_INTERFACE -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOL
    systemctl enable wg-quick@$WIREGUARD_INTERFACE
    systemctl start wg-quick@$WIREGUARD_INTERFACE
else
    echo "WireGuard já configurado. Pulando..."
fi

# Monitorar a rede e configurar IPs fictícios
echo "Monitorando IPs na rede privada..."
IP_LIST=$(nmap -sn $PRIVATE_IP_RANGE | grep "Nmap scan report for" | awk '{print $NF}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')

if [ -z "$IP_LIST" ]; then
    echo "Nenhum IP válido encontrado na rede privada."
    exit 1
fi

echo "IPs válidos encontrados: $IP_LIST"
echo

# Configurar cada IP
for PRIVATE_IP in $IP_LIST; do
    echo "Configurando o IP privado: $PRIVATE_IP"

    # Verificar se já existe configuração de IP fictício
    if grep -q "$PRIVATE_IP" $WG_CONF; then
        echo "IP $PRIVATE_IP já possui configuração fictícia. Pulando..."
        continue
    fi

    # Gerar IP fictício único
    LAST_OCTET=$(echo $PRIVATE_IP | awk -F. '{print $4}')
    FAKE_IP="$FAKE_IP_BASE.$LAST_OCTET"

    echo "Adicionando configuração para $PRIVATE_IP -> $FAKE_IP..."

    # Configuração no WireGuard
    sudo bash -c "cat >> $WG_CONF" <<EOL

[Peer]
PublicKey = $(wg genkey | tee /etc/wireguard/$PRIVATE_IP.pub)
AllowedIPs = $FAKE_IP/32
EOL

    # Configurar NAT (SNAT/DNAT)
    sudo iptables -t nat -A PREROUTING -d $FAKE_IP -j DNAT --to-destination $PRIVATE_IP
    sudo iptables -t nat -A POSTROUTING -s $PRIVATE_IP -j SNAT --to-source $FAKE_IP
    sudo iptables -A FORWARD -d $PRIVATE_IP -j ACCEPT

    # Perguntar portas adicionais
    read -p "Deseja liberar portas adicionais para $PRIVATE_IP? (S/N): " LIBERAR_PORTAS
    if [[ "$LIBERAR_PORTAS" =~ ^[Ss]$ ]]; then
        read -p "Digite as portas a liberar (separadas por espaço): " PORTAS
        for PORTA in $PORTAS; do
            echo "Liberando porta $PORTA para $PRIVATE_IP..."
            sudo iptables -A FORWARD -p tcp --dport $PORTA -d $PRIVATE_IP -j ACCEPT
            sudo iptables -A FORWARD -p udp --dport $PORTA -d $PRIVATE_IP -j ACCEPT
            sudo ufw allow $PORTA
        done
    fi

    echo "Configuração para $PRIVATE_IP completa!"
    echo
done

# Salvar regras do iptables para persistência
echo "Salvando regras do iptables..."
iptables-save > /etc/iptables/rules.v4
echo "Regras salvas com sucesso!"

echo "Configuração completa! O WireGuard está pronto para ser usado."
