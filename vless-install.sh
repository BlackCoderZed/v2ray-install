#!/bin/bash
set -e

PORT=443
DEST="www.microsoft.com:443"
SNI="www.microsoft.com"
FP="chrome"
XRAY_CONFIG="/usr/local/etc/xray/config.json"

echo "🚀 Installing dependencies..."
apt update -y
apt install -y curl jq ufw iptables-persistent netfilter-persistent

echo "🚀 Installing Xray..."
bash -c "$(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh)"

sleep 2

echo "🔐 Generating REALITY keys..."
KEYS=$(xray x25519)

PRIVATE_KEY=$(echo "$KEYS" | grep "PrivateKey" | awk '{print $3}')
PASSWORD=$(echo "$KEYS" | grep "Password" | awk '{print $2}')
SHORT_ID=$(openssl rand -hex 4)
UUID=$(cat /proc/sys/kernel/random/uuid)

if [[ -z "$PRIVATE_KEY" || -z "$PASSWORD" ]]; then
    echo "❌ REALITY key generation FAILED"
    exit 1
fi

echo "✅ Keys generated"
echo "UUID: $UUID"
echo "PrivateKey: $PRIVATE_KEY"
echo "Password(pbk): $PASSWORD"
echo "ShortID: $SHORT_ID"

echo "📝 Writing Xray config..."
mkdir -p /usr/local/etc/xray

cat > $XRAY_CONFIG <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $PORT,
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
          "dest": "$DEST",
          "xver": 0,
          "serverNames": ["$SNI"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["$SHORT_ID"]
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom" }
  ]
}
EOF

echo "🔥 Firewall setup..."
ufw allow $PORT
ufw --force enable

echo "🔒 Enforcing ONE DEVICE ONLY (iptables connlimit)..."
iptables -I INPUT -p tcp --dport $PORT -m connlimit --connlimit-above 1 -j DROP
netfilter-persistent save

echo "🚀 Restarting Xray..."
systemctl daemon-reload
systemctl restart xray
systemctl enable xray

SERVER_IP=$(curl -s ifconfig.me)

echo
echo "✅ ✅ ✅ INSTALLATION COMPLETE ✅ ✅ ✅"
echo "======================================"
echo "IP        : $SERVER_IP"
echo "Port      : $PORT"
echo "UUID      : $UUID"
echo "SNI       : $SNI"
echo "pbk       : $PASSWORD"
echo "Short ID  : $SHORT_ID"
echo "======================================"
echo
echo "✅ ✅ ✅ VLESS LINK (ONE DEVICE ONLY):"
echo
echo "vless://$UUID@$SERVER_IP:$PORT?type=tcp&security=reality&flow=xtls-rprx-vision&sni=$SNI&pbk=$PASSWORD&sid=$SHORT_ID&fp=$FP#ONE-DEVICE"
echo
echo "✅ Import into v2rayN / v2rayNG / Shadowrocket"
