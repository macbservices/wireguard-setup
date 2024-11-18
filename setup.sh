#!/bin/bash

# Solicitar o range de IPs da rede privada
echo "Exemplo de range IP da rede privada: 100.102.90.0/24"
read -p "Digite o range de IPs da rede privada (exemplo: 100.102.90.0/24): " NETWORK_RANGE

# Solicitar o range de IPs fictícios
echo "Exemplo de range IP fictício: 100.100.100.0/24"
read -p "Digite o range de IPs fictícios (exemplo: 100.100.100.0/24): " FICTITIOUS_RANGE

# Instalar WireGuard e dependências
echo "Instalando o WireGuard e dependências..."
sudo apt update
sudo apt install -y wireguard iptables iproute2

# Configurar WireGuard
WG_CONF="/etc/wireguard/wg0.conf"

echo "Configurando o WireGuard..."

# Gerar as chaves para o servidor WireGuard
PRIVATE_KEY=$(wg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

# Configuração inicial do WireGuard
cat <<EOL > $WG_CONF
[Interface]
Address = $NETWORK_RANGE
PrivateKey = $PRIVATE_KEY
ListenPort = 51820

SaveConfig = true

EOL

# Adicionar configuração de firewall para permitir tráfego do WireGuard
echo "Configurando regras de firewall..."
sudo ufw allow 51820/udp
sudo ufw enable

# Exemplo de script que vai monitorar e adicionar novos IPs fictícios
echo "Monitorando novos dispositivos e configurando IPs fictícios..."

while true; do
    # Liste os IPs ativos na rede privada
    for IP in $(nmap -sn $NETWORK_RANGE | grep "Nmap scan report for" | awk '{print $NF}'); do
        # Verifique se o IP já existe na configuração do WireGuard
        if ! grep -q "$IP" "$WG_CONF"; then
            echo "Novo IP detectado: $IP"
            
            # Pergunte ao usuário se deseja criar um IP fictício para o novo dispositivo
            read -p "Deseja criar um IP fictício para $IP? (s/n): " RESP
            if [[ "$RESP" == "s" ]]; then
                # Gere um par de chaves para o cliente
                PRIVATE_KEY_CLIENT=$(wg genkey)
                PUBLIC_KEY_CLIENT=$(echo "$PRIVATE_KEY_CLIENT" | wg pubkey)

                # Gere um IP fictício dentro do range fornecido
                FICTITIOUS_IP="100.100.$(shuf -i 2-254 -n 1).$(shuf -i 2-254 -n 1)"

                # Adicione a configuração ao arquivo WireGuard
                echo -e "\n[Peer]" >> "$WG_CONF"
                echo "PublicKey = $PUBLIC_KEY_CLIENT" >> "$WG_CONF"
                echo "AllowedIPs = $FICTITIOUS_IP/32" >> "$WG_CONF"
                
                echo "Configuração adicionada para $IP com IP fictício $FICTITIOUS_IP"
                echo "Chave privada do cliente: $PRIVATE_KEY_CLIENT"
                
                # Reinicie o WireGuard para aplicar as mudanças
                wg syncconf wg0 <(wg-quick strip wg0)
            fi
        fi
    done

    # Aguarde 30 segundos antes de checar novamente
    sleep 30
done
