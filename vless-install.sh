bash <(cat << 'EOF'
#!/bin/bash

echo "======================================"
echo "   VLESS + REALITY IP INSTALLER (FIXED)"
echo "   SAFE VERSION - NO BROKEN KEYS"
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
apt install -y curl socat nano ufw jq openssl

# Install Xray (official)
bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)

# Generate UUID
UUID=$(xray uuid)

# Generate REALITY keys (SAFE method)
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | awk '/Private/{print $3}')
PUBLIC_KEY=$(echo "$KEYS" | awk '/Public/{print $3}')

# Validate key generation
if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
  echo "❌ Failed to generate REALITY keys. Aborting."
  exit 1
fi

SHORT_ID=$(openssl rand -hex 2)

# Write CLEAN, VALID config
cat > /usr/local/etc/xray/config.json <<EOF2
{
  "log": {
    "loglevel": "warning"
  },
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
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["$SHORT_ID"]
        }
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

# Validate config BEFORE restarting
echo "✅ Validating config..."
xray run -test -config /usr/local/etc/xray/config.json
if [ $? -ne 0 ]; then
  echo "❌ Config validation failed! Installer stopped."
  exit 1
fi

# Open firewall
ufw allow $XRAY_PORT
ufw --force enable

# Restart Xray safely
systemctl daemon-reload
systemctl restart xray
systemctl enable xray

sleep 2

# Final status check
if ! systemctl is-active --quiet xray; then
  echo "❌ Xray failed to start. Check logs:"
  journalctl -u xray -n 30 --no-pager
  exit 1
fi

# Get server IP
SERVER_IP=$(curl -s https://api.ipify.org)

# Generate VLESS link
VLESS_LINK="vless://$UUID@$SERVER_IP:$XRAY_PORT?encryption=none&flow=xtls-rprx-vision&type=tcp&security=reality&sni=www.cloudflare.com&pbk=$PUBLIC_KEY&sid=$SHORT_ID#IP-ONLY-VLESS"

echo ""
echo "======================================"
echo "✅ INSTALLATION SUCCESSFUL"
echo "======================================"
echo "Server IP  : $SERVER_IP"
echo "Port       : $XRAY_PORT"
echo "UUID       : $UUID"
echo "Public Key : $PUBLIC_KEY"
echo "Short ID   : $SHORT_ID"
echo ""
echo "✅ VLESS SHARE LINK:"
echo "$VLESS_LINK"
echo ""
echo "✅ Import into:"
echo " - v2rayNG (Android)"
echo " - v2rayN (Windows)"
echo " - Shadowrocket (iOS)"
echo "======================================"

EOF
)
