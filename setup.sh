#!/bin/bash

# Verificando se o script está sendo executado como root
if [ "$(id -u)" -ne "0" ]; then
    echo "Este script precisa ser executado como root!" 
    exit 1
fi

# Atualizando o sistema
echo "Atualizando o sistema..."
apt update && apt upgrade -y

# Instalando dependências
echo "Instalando dependências..."
apt install -y wireguard curl ufw

# Configuração do WireGuard
WG_CONF="/etc/wireguard/wg0.conf"
NETWORK_RANGE="100.102.90.0/24"
LISTEN_PORT=51820

# Gerando as chaves privadas e públicas
echo "Gerando as chaves do WireGuard..."
wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey

PRIVATE_KEY=$(cat /etc/wireguard/privatekey)
PUBLIC_KEY=$(cat /etc/wireguard/publickey)

# Criando o arquivo de configuração do WireGuard
echo "Configurando o WireGuard..."
echo "[Interface]
Address = 100.100.100.1/24
PrivateKey = $PRIVATE_KEY
ListenPort = $LISTEN_PORT
SaveConfig = true
PostUp = ufw allow $LISTEN_PORT/udp
PostDown = ufw delete allow $LISTEN_PORT/udp
" > $WG_CONF

# Configurando o UFW (Firewall)
echo "Configurando o firewall (UFW)..."
ufw allow OpenSSH
ufw allow $LISTEN_PORT/udp
ufw enable

# Iniciando o WireGuard
echo "Iniciando o WireGuard..."
wg-quick up wg0

# Ativando o WireGuard no boot
systemctl enable wg-quick@wg0

echo "WireGuard foi configurado com sucesso!"
