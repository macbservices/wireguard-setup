#!/bin/bash

# Função para instalar dependências
install_dependencies() {
  echo "Instalando dependências..."
  sudo apt update
  sudo apt install -y wireguard nmap iptables curl
}

# Função para criar as chaves do servidor WireGuard
generate_server_keys() {
  echo "Gerando as chaves para o servidor WireGuard..."
  wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey
}

# Função para configurar o servidor WireGuard
configure_wireguard_server() {
  echo "Configurando o WireGuard no servidor..."

  # Perguntar o range de IPs privados
  echo "Digite o range de IPs privados (exemplo: 100.102.90.0/24):"
  read private_range
  echo "Digite o range de IPs fictícios (exemplo: 100.100.100.0/24):"
  read fictitious_range

  # Configuração do servidor WireGuard
  cat > /etc/wireguard/wg0.conf <<EOL
[Interface]
PrivateKey = $(cat /etc/wireguard/privatekey)
Address = $fictitious_range
ListenPort = 51820

[Peer]
PublicKey = $(cat /etc/wireguard/publickey)
AllowedIPs = 0.0.0.0/0
EOL
}

# Função para configurar as VPS com IP fictício
configure_vps_wireguard() {
  echo "Digite o IP fictício para cada VPS (exemplo: 100.100.100.11):"
  read vps_ip

  # Criar arquivo de configuração para a VPS
  cat > /etc/wireguard/wg0.conf <<EOL
[Interface]
PrivateKey = $(cat /etc/wireguard/privatekey)
Address = $vps_ip/32

[Peer]
PublicKey = $(cat /etc/wireguard/publickey)
Endpoint = $server_ip:51820
AllowedIPs = 0.0.0.0/0
EOL
}

# Função para monitorar a rede e verificar IPs
monitor_ips() {
  echo "Monitorando IPs na rede privada..."
  nmap -sP $private_range | grep -oP 'Nmap scan report for \K[0-9.]+'
}

# Função para liberar portas
open_ports() {
  echo "Deseja liberar alguma porta? (exemplo: 22 para SSH, 80 para HTTP)"
  read port
  sudo ufw allow $port
}

# Instalar dependências
install_dependencies

# Gerar chaves para o servidor
generate_server_keys

# Configurar o servidor WireGuard
configure_wireguard_server

# Perguntar se deseja configurar as VPS
echo "Você deseja configurar as VPS com IP fictício? (S/N)"
read configure_vps
if [[ "$configure_vps" == "S" || "$configure_vps" == "s" ]]; then
  configure_vps_wireguard
fi

# Monitorar os IPs
monitor_ips

# Perguntar se deseja liberar portas
echo "Deseja liberar portas adicionais? (S/N)"
read open_ports_response
if [[ "$open_ports_response" == "S" || "$open_ports_response" == "s" ]]; then
  open_ports
fi

echo "Configuração completa! O WireGuard está pronto para ser usado."
