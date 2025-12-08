#!/bin/bash

echo "======================================"
echo "   Xray 25.12.8 VLESS + REALITY Installer"
echo "       SINGLE USER PER CONFIG"
echo "======================================"

# Root check
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root"
  exit 1
fi

# Ask for port
read -p "👉 Enter your desired port (1-65535, e.g. 443, 8443): " XRAY_PORT
if ! [[ "$XRAY_PORT" =~ ^[0-9]+$ ]] || [ "$XRAY_PORT" -lt 1 ] || [ "$XRAY_PORT" -gt 65535 ]; then
  echo "❌ Invalid port number!"
  exit 1
fi
echo "✅ Using port: $XRAY_PORT"

# Install dependencies
apt update -y
apt install -y curl unzip socat nano ufw jq

# Install Xray
bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)

# Generate REALITY keys using xray
echo "🔑 Generating REALITY keys..."
REALITY_KEYS=$(xray x25519)
if [ $? -ne 0 ]; then
  echo "❌ Failed to generate REALITY keys! Make sure Xray 25.12.8 is installed."
  exit 1
fi

# Extract private and public key
# Extract private and public key by piping the keys variable
# We use 'grep' to find the line and 'awk' to split it on the colon (':') and get the second field ($2)
# The use of 'tr' is often safer to ensure no weird whitespace is left behind.
REALITY_PRIVATE=$(echo "$REALITY_KEYS" | grep -i "Private key" | awk -F': ' '{print $2}' | tr -d '\n\r')
REALITY_PUBLIC=$(echo "$REALITY_KEYS" | grep -i "Public key" | awk -F': ' '{print $2}' | tr -d '\n\r')

# Generate a short ID for this user
REALITY_SHORTID=$(openssl rand -hex 2)

# Generate UUID for single user
UUID=$(xray uuid)

# Create config
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
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
          "privateKey": "$REALITY_PRIVATE",
          "shortIds": ["$REALITY_SHORTID"]
        }
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

# Validate config
xray run -test -config /usr/local/etc/xray/config.json
if [ $? -ne 0 ]; then
  echo "❌ Config validation failed! Exiting."
  exit 1
fi

# Open firewall
#ufw allow $XRAY_PORT
#ufw --force enable

# Restart Xray
systemctl daemon-reload
systemctl enable xray
systemctl restart xray

sleep 2

# Check status
if ! systemctl is-active --quiet xray; then
  echo "❌ Xray failed to start. Check logs:"
  journalctl -u xray -n 30 --no-pager
  exit 1
fi

# Generate VLESS link
SERVER_IP=$(curl -s https://api.ipify.org)
VLESS_LINK="vless://$UUID@$SERVER_IP:$XRAY_PORT?encryption=none&flow=xtls-rprx-vision&type=tcp&security=reality&sni=www.cloudflare.com&pbk=$REALITY_PUBLIC&sid=$REALITY_SHORTID#IP-ONLY-VLESS"

echo ""
echo "======================================"
echo "✅ INSTALLATION SUCCESSFUL"
echo "Server IP      : $SERVER_IP"
echo "Port           : $XRAY_PORT"
echo "UUID           : $UUID"
echo "REALITY PubKey : $REALITY_PUBLIC"
echo ""
echo "✅ VLESS LINK (ONE USER ONLY):"
echo "$VLESS_LINK"
echo "======================================"
