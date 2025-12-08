#!/bin/bash

echo "======================================"
echo "    Xray 25.12.8 VLESS + REALITY Installer"
echo "      SINGLE USER PER CONFIG"
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
echo "⚙️ Installing Xray core..."
bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)

# Generate REALITY keys using xray and capture them reliably
echo "🔑 Generating REALITY keys and extracting private/public pair..."

# Use process substitution with 'read' to reliably parse multi-line key output.
# IFS is set to split on ': '
while IFS=": " read -r label value; do
    if [[ "$label" == "Private key" ]]; then
        REALITY_PRIVATE="$value"
    elif [[ "$label" == "Public key" ]]; then
        REALITY_PUBLIC="$value"
    fi
done < <(xray x25519)

# Verification check for extracted keys
if [ -z "$REALITY_PRIVATE" ] || [ -z "$REALITY_PUBLIC" ]; then
  echo "❌ Failed to parse REALITY keys from xray output! Exiting."
  exit 1
fi

echo "✅ Keys extracted successfully."

# Generate a short ID for this user
REALITY_SHORTID=$(openssl rand -hex 2)

# Generate UUID for single user
UUID=$(xray uuid)

# Create config
echo "📝 Creating Xray configuration file..."
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
echo "🔍 Validating configuration..."
xray run -test -config /usr/local/etc/xray/config.json
if [ $? -ne 0 ]; then
  echo "❌ Config validation failed! Exiting."
  exit 1
fi
echo "✅ Configuration validated."

# Open firewall (uncommented UFW commands)
#echo "🔥 Configuring firewall (UFW)..."
#ufw allow $XRAY_PORT
#ufw --force enable
#echo "✅ Port $XRAY_PORT allowed in UFW."

# Restart Xray
echo "🚀 Starting Xray service..."
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
echo "✅ Xray service is running."

# Generate VLESS link
SERVER_IP=$(curl -s https://api.ipify.org)
VLESS_LINK="vless://$UUID@$SERVER_IP:$XRAY_PORT?encryption=none&flow=xtls-rprx-vision&type=tcp&security=reality&sni=www.cloudflare.com&pbk=$REALITY_PUBLIC&sid=$REALITY_SHORTID#IP-ONLY-VLESS"

echo ""
echo "======================================"
echo "✅ INSTALLATION SUCCESSFUL"
echo "Server IP       : $SERVER_IP"
echo "Port            : $XRAY_PORT"
echo "UUID            : $UUID"
echo "REALITY PubKey  : $REALITY_PUBLIC"
echo ""
echo "✅ VLESS LINK (ONE USER ONLY - Copy/Paste this into your client):"
echo "$VLESS_LINK"
echo "======================================"