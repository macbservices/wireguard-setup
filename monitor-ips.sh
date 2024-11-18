#!/bin/bash

# Certifique-se de que o WireGuard está instalado
if ! command -v wg &> /dev/null; then
    echo "WireGuard não está instalado. Instalando..."
    sudo apt update -y
    sudo apt install -y wireguard nmap
fi

# Perguntar ao usuário o range da rede privada
echo "Digite o range de IP da sua rede privada (exemplo: 100.102.90.0/24):"
read NETWORK_RANGE

# Perguntar ao usuário o range de IP fictício
echo "Digite o range de IP fictício para novos dispositivos (exemplo: 100.100.100.1/24):"
read FICTITIOUS_RANGE

# Instalar e configurar o WireGuard
echo "Configurando o WireGuard..."
WG_CONF="/etc/wireguard/wg0.conf"
PRIVATE_KEY=$(wg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

# Criar o arquivo de configuração do WireGuard
echo -e "[Interface]\nAddress = $FICTITIOUS_RANGE\nPrivateKey = $PRIVATE_KEY\nListenPort = 51820" > $WG_CONF

# Reiniciar o WireGuard
wg-quick up wg0

# Função para monitorar novos IPs na rede privada
echo "Monitorando novos IPs na rede privada..."
while true; do
    # Listar IPs ativos na rede privada usando o nmap
    for IP in $(nmap -sn $NETWORK_RANGE | grep "Nmap scan report for" | awk '{print $NF}'); do
        # Verifique se o IP já existe na configuração do WireGuard
        if ! grep -q "$IP" "$WG_CONF"; then
            echo "Novo IP detectado: $IP"
            
            # Perguntar ao usuário se deseja criar um IP fictício para o novo dispositivo
            read -p "Deseja criar um IP fictício para $IP? (s/n): " RESP
            if [[ "$RESP" == "s" ]]; then
                # Gere um par de chaves para o cliente
                NEW_PRIVATE_KEY=$(wg genkey)
                NEW_PUBLIC_KEY=$(echo "$NEW_PRIVATE_KEY" | wg pubkey)
                FICTITIOUS_IP="100.100.$(shuf -i 2-254 -n 1).$(shuf -i 2-254 -n 1)"
                
                # Adicionar a configuração ao arquivo WireGuard
                echo -e "\n[Peer]" >> "$WG_CONF"
                echo "PublicKey = $NEW_PUBLIC_KEY" >> "$WG_CONF"
                echo "AllowedIPs = $FICTITIOUS_IP/32" >> "$WG_CONF"
                
                echo "Configuração adicionada para $IP com IP fictício $FICTITIOUS_IP"
                echo "Chave privada do cliente: $NEW_PRIVATE_KEY"
                
                # Reiniciar o WireGuard para aplicar as mudanças
                wg syncconf wg0 <(wg-quick strip wg0)
            fi
        fi
    done
    # Aguardar 30 segundos antes de checar novamente
    sleep 30
done
