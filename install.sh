#!/bin/bash

# Atualizando o sistema
echo "Atualizando o sistema..."
sudo apt update -y && sudo apt upgrade -y

# Instalando dependências
echo "Instalando dependências necessárias..."
sudo apt install -y wireguard wireguard-tools ufw nmap git python3 python3-venv

# Instalando o Cowrie (Honeypot)
echo "Instalando o Cowrie Honeypot..."
git clone https://github.com/cowrie/cowrie.git /opt/cowrie
cd /opt/cowrie
python3 -m venv cowrie-env
source cowrie-env/bin/activate
pip install -r requirements.txt

# Gerando chaves para WireGuard
echo "Gerando chaves para o WireGuard..."
umask 077
wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey

PRIVATE_KEY=$(cat /etc/wireguard/privatekey)
PUBLIC_KEY=$(cat /etc/wireguard/publickey)

echo "Chaves geradas:"

echo "Chave privada: $PRIVATE_KEY"
echo "Chave pública: $PUBLIC_KEY"

# Configurando o WireGuard
echo "Configurando o WireGuard..."
WG_CONF="/etc/wireguard/wg0.conf"
NETWORK_RANGE="100.102.90.0/24"
LISTEN_PORT=51820

echo "[Interface]
Address = 100.100.100.1/24
PrivateKey = $PRIVATE_KEY
ListenPort = $LISTEN_PORT
SaveConfig = true
PostUp = ufw allow $LISTEN_PORT/udp
PostDown = ufw delete allow $LISTEN_PORT/udp
" > $WG_CONF

# Configurando o firewall (UFW)
echo "Configurando o firewall (UFW)..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 51820/udp
sudo ufw enable

# Ativando o WireGuard
echo "Ativando o WireGuard..."
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

# Executando o script de monitoramento de IPs
echo "Executando o monitoramento de IPs e criação de IP fictício..."
sudo tee /usr/local/bin/monitor_wg.sh > /dev/null <<EOF
#!/bin/bash

WG_CONF="/etc/wireguard/wg0.conf"
NETWORK_RANGE="100.102.90.0/24"

echo "Monitorando novos IPs na rede privada..."

while true; do
    for IP in \$(nmap -sn \$NETWORK_RANGE | grep "Nmap scan report for" | awk '{print \$NF}'); do
        if ! grep -q "\$IP" "\$WG_CONF"; then
            echo "Novo IP detectado: \$IP"
            read -p "Deseja criar um IP fictício para \$IP? (s/n): " RESP
            if [[ "\$RESP" == "s" ]]; then
                PRIVATE_KEY=\$(wg genkey)
                PUBLIC_KEY=\$(echo "\$PRIVATE_KEY" | wg pubkey)
                FICTITIOUS_IP="100.100.\$(shuf -i 2-254 -n 1).\$(shuf -i 2-254 -n 1)"

                echo -e "\n[Peer]" >> "\$WG_CONF"
                echo "PublicKey = \$PUBLIC_KEY" >> "\$WG_CONF"
                echo "AllowedIPs = \$FICTITIOUS_IP/32" >> "\$WG_CONF"

                echo "Configuração adicionada para \$IP com IP fictício \$FICTITIOUS_IP"
                echo "Chave privada do cliente: \$PRIVATE_KEY"

                wg syncconf wg0 <(wg-quick strip wg0)
            fi
        fi
    done
    sleep 30
done
EOF

# Tornando o script executável
sudo chmod +x /usr/local/bin/monitor_wg.sh

# Finalizando a instalação
echo "Instalação concluída! Você pode agora rodar o script de monitoramento de IPs com o comando:"
echo "sudo /usr/local/bin/monitor_wg.sh"
