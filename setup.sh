#!/bin/bash

set -e

echo "Configurando o WireGuard e IPs fictícios para VPS..."

# Dependências necessárias
echo "Instalando dependências..."
sudo apt update
sudo apt install -y wireguard iptables-persistent ufw nmap

# Configurações gerais
echo "Habilitando redirecionamento de pacotes..."
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -p

# Perguntar o range de IPs privados
read -p "Digite o range de IPs privados na rede (exemplo: 100.102.90.0/24): " PRIVATE_IP_RANGE
echo "Range de IPs privados configurado como: $PRIVATE_IP_RANGE"

# Perguntar o range de IPs fictícios
read -p "Digite o range de IPs fictícios (exemplo: 100.100.100.0/24): " FAKE_IP_RANGE
FAKE_IP_BASE=$(echo $FAKE_IP_RANGE | cut -d'/' -f1 | awk -F. '{print $1"."$2"."$3}')

echo "Range de IPs fictícios configurado como: $FAKE_IP_RANGE"
echo

# Configurar interface WireGuard
if [ ! -f /etc/wireguard/wg0.conf ]; then
    echo "Gerando configuração inicial do WireGuard..."
    sudo bash -c "cat > /etc/wireguard/wg0.conf" <<EOL
[Interface]
PrivateKey = $(wg genkey)
Address = $FAKE_IP_BASE.1/24
ListenPort = 51820
SaveConfig = true
EOL
    sudo systemctl enable wg-quick@wg0
    sudo systemctl start wg-quick@wg0
else
    echo "WireGuard já configurado. Pulando..."
fi

# Monitorar IPs na rede privada
echo "Monitorando IPs na rede privada..."
IP_LIST=$(nmap -sn $PRIVATE_IP_RANGE | grep "Nmap scan report for" | awk '{print $5}')
if [ -z "$IP_LIST" ]; then
    echo "Nenhum IP encontrado na rede privada."
    exit 1
fi

echo "IPs encontrados: $IP_LIST"
echo

# Processar cada IP
for PRIVATE_IP in $IP_LIST; do
    echo "Configurando o IP privado: $PRIVATE_IP"

    # Verificar se já existe configuração de IP fictício
    if grep -q "$PRIVATE_IP" /etc/wireguard/wg0.conf; then
        echo "IP $PRIVATE_IP já possui configuração fictícia. Pulando..."
        continue
    fi

    # Gerar IP fictício único
    LAST_OCTET=$(echo $PRIVATE_IP | awk -F. '{print $4}')
    FAKE_IP="$FAKE_IP_BASE.$LAST_OCTET"

    echo "Adicionando configuração para $PRIVATE_IP -> $FAKE_IP..."

    # Configuração no WireGuard
    sudo bash -c "cat >> /etc/wireguard/wg0.conf" <<EOL

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

# Salvar configurações do iptables
echo "Salvando regras do iptables..."
sudo netfilter-persistent save

# Reiniciar WireGuard para aplicar mudanças
echo "Reiniciando o WireGuard..."
sudo systemctl restart wg-quick@wg0

echo "Configuração concluída! O acesso externo está configurado."
