#!/bin/bash

# Kiểm tra quyền root
if [ "$(id -u)" -ne 0 ]; then
  echo "⚠️  Bạn cần chạy script với quyền root (sudo)."
  exit 1
fi

echo "🧩 Đang cấu hình repo cho CentOS Stream 9..."

# Bật EPEL và CRB
dnf install epel-release -y
dnf config-manager --set-enabled crb

# Thêm repo COPR cho WireGuard
dnf install -y dnf-plugins-core
dnf copr enable jdoss/wireguard -y

# Cài WireGuard & công cụ cần thiết
dnf install wireguard-tools qrencode iproute iptables firewalld -y

# Bật firewalld
systemctl enable firewalld --now

# Tạo thư mục
mkdir -p /etc/wireguard
cd /etc/wireguard

echo "🔐 Tạo khóa cho server..."
wg genkey | tee server_private.key | wg pubkey > server_public.key

SERVER_PRIV_KEY=$(cat server_private.key)
SERVER_PUB_KEY=$(cat server_public.key)
SERVER_IP="10.0.0.1/24"
LISTEN_PORT=51820
INTERFACE="wg0"

cat > /etc/wireguard/$INTERFACE.conf <<EOF
[Interface]
Address = $SERVER_IP
ListenPort = $LISTEN_PORT
PrivateKey = $SERVER_PRIV_KEY
SaveConfig = true
EOF

echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

NIC=$(ip -o -4 route show to default | awk '{print $5}')
iptables -t nat -A POSTROUTING -o $NIC -j MASQUERADE
iptables-save > /etc/iptables.rules

firewall-cmd --permanent --add-port=${LISTEN_PORT}/udp
firewall-cmd --permanent --add-masquerade
firewall-cmd --reload

wg-quick up $INTERFACE
systemctl enable wg-quick@$INTERFACE

CLIENT_NAME="client1"
CLIENT_IP="10.0.0.2/24"

wg genkey | tee ${CLIENT_NAME}_private.key | wg pubkey > ${CLIENT_NAME}_public.key
CLIENT_PRIV_KEY=$(cat ${CLIENT_NAME}_private.key)
CLIENT_PUB_KEY=$(cat ${CLIENT_NAME}_public.key)

wg set $INTERFACE peer $CLIENT_PUB_KEY allowed-ips 10.0.0.2/32

SERVER_PUBLIC_IP=$(curl -s ifconfig.me)

cat > ${CLIENT_NAME}.conf <<EOF
[Interface]
PrivateKey = $CLIENT_PRIV_KEY
Address = $CLIENT_IP
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB_KEY
Endpoint = $SERVER_PUBLIC_IP:$LISTEN_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

echo "✅ WireGuard server đã sẵn sàng!"
echo "🌐 IP Server: $SERVER_PUBLIC_IP"
echo "🔑 Public Key: $SERVER_PUB_KEY"
echo "📄 File cấu hình client: $(pwd)/${CLIENT_NAME}.conf"
# echo "📱 Quét mã QR để kết nối:"
qrencode -t ansiutf8 < ${CLIENT_NAME}.conf
cat ${CLIENT_NAME}.conf
