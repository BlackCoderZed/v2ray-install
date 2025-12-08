bash <(cat <<'EOF'
#!/bin/bash

echo "======================================"
echo "   VLESS + REALITY IP INSTALLER (FIXED)"
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

# Generate REALITY keys via OpenSSL (WORKS ON ANY VPS)
PRIVATE_KEY=$(openssl genpkey -algorithm X25519 -out /tmp/privkey.pem -pkeyopt ec_paramgen_curve:X25519 -outform PEM)
PRIVATE_KEY=$(openssl pkey -in /tmp/privkey.pem -outform DER | tail -c 32 | xxd -p -c 32)
PUBLIC_KEY=$(python3 - <<END
from cryptography.hazmat.primitives.asymmetric import x25519
import binascii
priv_bytes = bytes.fromhex('$PRIVATE_KEY')
pub = x25519.X25519PrivateKey.from_private_bytes(priv_bytes).public_key()
print(binascii.hexlify(pub.public_bytes()).decode())
END
)
SHORT_ID=$(openssl rand -hex 2)

# Write Xray config
cat > /usr/local/etc/xray/config.json <<EOF2
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $XRAY_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "$UUID", "flow": "xtls-rprx-vision", "email": "user1" }
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
  "outbounds": [{ "protocol": "freedom" }]
}
EOF2

# Validate config
xray run -test -config /usr/local/etc/xray/config.json
if [ $? -ne 0 ]; then
  echo "❌ Config validation failed! Exiting."
  exit 1
fi

# Firewall
#ufw allow $XRAY_PORT
#ufw --force enable

# Restart Xray
systemctl daemon-reload
systemctl restart xray
systemctl enable xray

sleep 2

if ! systemctl is-active --quiet xray; then
  echo "❌ Xray failed to start. Check logs with: journalctl -u xray -n 30 --no-pager"
  exit 1
fi

# Get server IP
SERVER_IP=$(curl -s https://api.ipify.org)

# Generate VLESS link
VLESS_LINK="vless://$UUID@$SERVER_IP:$XRAY_PORT?encryption=none&flow=xtls-rprx-vision&type=tcp&security=reality&sni=www.cloudflare.com&pbk=$PUBLIC_KEY&sid=$SHORT_ID#IP-ONLY-VLESS"

echo ""
echo "======================================"
echo "✅ INSTALLATION SUCCESSFUL"
echo "Server IP  : $SERVER_IP"
echo "Port       : $XRAY_PORT"
echo "UUID       : $UUID"
echo "Public Key : $PUBLIC_KEY"
echo "Short ID   : $SHORT_ID"
echo ""
echo "✅ VLESS LINK:"
echo "$VLESS_LINK"
echo "======================================"

EOF
)
