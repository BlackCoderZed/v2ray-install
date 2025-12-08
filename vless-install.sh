bash <(cat << 'EOF'
#!/bin/bash

echo "======================================"
echo "  VLESS + REALITY IP ONLY INSTALLER"
echo "  DYNAMIC PORT + 1 DEVICE PER CONFIG"
echo "======================================"

# Root check
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root"
  exit 1
fi

# Ask for Port
read -p "👉 Enter your desired port (e.g. 443, 8443, 2053, 2087): " XRAY_PORT

if ! [[ "$XRAY_PORT" =~ ^[0-9]+$ ]] || [ "$XRAY_PORT" -lt 1 ] || [ "$XRAY_PORT" -gt 65535 ]; then
  echo "❌ Invalid port number!"
  exit 1
fi

# Install dependencies
apt update -y
apt install -y curl socat nano ufw

# Install Xray
bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)

# Generate UUID
UUID=$(xray uuid)

# Generate Reality Keys
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "Private key" | awk '{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Public key" | awk '{print $3}')

SHORT_ID=$(openssl rand -hex 2)

# Create Xray config
cat > /usr/local/etc/xray/config.json <<EOF2
{
  "inbounds": [
    {
      "port": $XRAY_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision",
            "email": "user1"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.cloudflare.com:443",
          "xver": 0,
          "serverNames": ["www.cloudflare.com"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["$SHORT_ID"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF2

# Open firewall
ufw allow $XRAY_PORT
ufw --force enable

# Restart Xray
systemctl restart xray
systemctl enable xray

# Get Server IP
SERVER_IP=$(curl -s https://api.ipify.org)

# Generate VLESS Link
VLESS_LINK="vless://$UUID@$SERVER_IP:$XRAY_PORT?encryption=none&flow=xtls-rprx-vision&type=tcp&security=reality&sni=www.cloudflare.com&pbk=$PUBLIC_KEY&sid=$SHORT_ID#IP-ONLY-VLESS"

echo ""
echo "======================================"
echo "✅ INSTALLATION COMPLETE"
echo "======================================"
echo "Server IP     : $SERVER_IP"
echo "Port          : $XRAY_PORT"
echo "UUID          : $UUID"
echo "Public Key    : $PUBLIC_KEY"
echo "Short ID      : $SHORT_ID"
echo ""
echo "✅ VLESS SHARE LINK:"
echo "$VLESS_LINK"
echo ""
echo "✅ Import into:"
echo " - v2rayNG (Android)"
echo " - v2rayN (Windows)"
echo " - Shadowrocket (iOS)"
echo ""
echo "✅ Xray Status:"
systemctl status xray --no-pager
EOF
)
