cat > /usr/bin/vless-manager << 'EOF'
#!/bin/bash

CONFIG_FILE="/usr/local/etc/xray/config.json"
SERVICE="xray"

function restart_xray() {
  systemctl restart $SERVICE
}

function get_port() {
  grep '"port"' $CONFIG_FILE | head -1 | tr -dc '0-9'
}

function add_user() {
  read -p "Enter username: " USERNAME
  UUID=$(xray uuid)

  jq ".inbounds[0].settings.clients += [{\"id\":\"$UUID\",\"flow\":\"xtls-rprx-vision\",\"email\":\"$USERNAME\"}]" $CONFIG_FILE > /tmp/config.json && mv /tmp/config.json $CONFIG_FILE

  restart_xray

  PORT=$(get_port)
  SERVER_IP=$(curl -s https://api.ipify.org)
  PUBLIC_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' $CONFIG_FILE | xargs -I{} echo "{}" | xray x25519 | grep "Public key" | awk '{print $3}')
  SHORT_ID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' $CONFIG_FILE)

  VLESS_LINK="vless://$UUID@$SERVER_IP:$PORT?encryption=none&flow=xtls-rprx-vision&type=tcp&security=reality&sni=www.cloudflare.com&pbk=$PUBLIC_KEY&sid=$SHORT_ID#$USERNAME"

  echo ""
  echo "✅ USER ADDED SUCCESSFULLY"
  echo "Username : $USERNAME"
  echo "UUID     : $UUID"
  echo "Link     :"
  echo "$VLESS_LINK"
}

function delete_user() {
  read -p "Enter username to delete: " USERNAME

  jq " .inbounds[0].settings.clients |= map(select(.email != \"$USERNAME\")) " $CONFIG_FILE > /tmp/config.json && mv /tmp/config.json $CONFIG_FILE

  restart_xray

  echo "✅ User '$USERNAME' deleted"
}

function list_users() {
  echo ""
  echo "✅ USER LIST:"
  jq -r '.inbounds[0].settings.clients[].email' $CONFIG_FILE
  echo ""
}

function uninstall_xray() {
  read -p "❗ Are you sure you want to completely uninstall Xray/V2Ray? (yes/no): " CONFIRM
  if [ "$CONFIRM" == "yes" ]; then
    systemctl stop xray
    systemctl disable xray
    rm -rf /usr/local/etc/xray
    rm -rf /usr/local/bin/xray
    rm -rf /etc/systemd/system/xray.service
    systemctl daemon-reload
    echo "✅ Xray/V2Ray completely removed"
  else
    echo "❌ Uninstall cancelled"
  fi
}

while true; do
  clear
  echo "======================================"
  echo "   VLESS REALITY MANAGEMENT MENU"
  echo "======================================"
  echo "1️⃣  Add User"
  echo "2️⃣  Delete User"
  echo "3️⃣  List Users"
  echo "4️⃣  Uninstall Xray/V2Ray"
  echo "5️⃣  Exit"
  echo "======================================"
  read -p "Choose an option: " OPTION

  case $OPTION in
    1) add_user ;;
    2) delete_user ;;
    3) list_users ;;
    4) uninstall_xray ;;
    5) exit ;;
    *) echo "❌ Invalid option" ;;
  esac

  read -p "Press Enter to continue..."
done

EOF
chmod +x /usr/bin/vless-manager
