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

# --- 1. User Input ---
read -p "👉 Enter your desired port (1-65535, e.g. 443, 8443): " XRAY_PORT
if ! [[ "$XRAY_PORT" =~ ^[0-9]+$ ]] || [ "$XRAY_PORT" -lt 1 ] || [ "$XRAY_PORT" -gt 65535 ]; then
  echo "❌ Invalid port number!"
  exit 1
fi
echo "✅ Using port: $XRAY_PORT"

# --- 2. Install Dependencies & Xray ---
echo "⚙️ Installing dependencies and Xray core..."
apt update -y
apt install -y curl unzip socat nano ufw jq
bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)
echo "🕒 Waiting 10 seconds to ensure Xray installation is complete..."
sleep 10

# --- 3. Key Generation and Parsing (CRITICAL FIX) ---
echo "🔑 Generating REALITY keys and extracting private/public pair..."

echo "🔑 Generating REALITY keys and extracting private/public pair..."

# Run xray x25519, capturing both standard output and standard error (2>&1).
# We store the entire output in a variable for inspection.
XRAY_KEY_OUTPUT=$(xray x25519 2>&1)

# Now, use echo and grep to see if the key lines exist in the output
# We pipe the output directly to the while loop for robust line-by-line reading.
while IFS=": " read -r label value; do
    # Trim leading/trailing whitespace using the 'xargs' method
    trimmed_value=$(echo "$value" | xargs)

    if [[ "$label" == "Private key" ]]; then
        REALITY_PRIVATE="$trimmed_value"
    elif [[ "$label" == "Public key" ]]; then
        REALITY_PUBLIC="$trimmed_value"
    fi
done < <(echo "$XRAY_KEY_OUTPUT")

# --- Debugging and Verification ---
if [ -z "$REALITY_PRIVATE" ] || [ -z "$REALITY_PUBLIC" ]; then
  echo "❌ Failed to parse REALITY keys! Dumping Xray output for diagnosis:"
  echo "--- XRAY OUTPUT START ---"
  echo "$XRAY_KEY_OUTPUT"
  echo "--- XRAY OUTPUT END ---"
  echo "The output above should contain 'Private key' and 'Public key' lines."
  exit 1
fi
# --- End Debugging and Verification ---

echo "✅ Keys extracted successfully."

# Generate identifiers
REALITY_SHORTID=$(openssl rand -hex 2)
UUID=$(xray uuid)

# --- 4. Create Configuration File ---
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

# --- 5. Validation and Startup ---
echo "🔍 Validating configuration..."
xray run -test -config /usr/local/etc/xray/config.json
if [ $? -ne 0 ]; then
  echo "❌ Config validation failed! Exiting."
  exit 1
fi
echo "✅ Configuration validated."

# Open firewall
echo "🔥 Configuring firewall (UFW)..."
ufw allow $XRAY_PORT
ufw --force enable
echo "✅ Port $XRAY_PORT allowed in UFW."

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

# --- 6. Output Final Link ---
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