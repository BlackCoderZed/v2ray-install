#!/usr/bin/env python3
import subprocess, json, uuid, os, re, sys, time

XRAY_CONFIG = "/usr/local/etc/xray/config.json"
XRAY_BIN = "/usr/local/bin/xray"
PORT = 8443
DEST = "www.microsoft.com:443"
SNI = "www.microsoft.com"
FP = "chrome"

def run(cmd):
    return subprocess.check_output(cmd, shell=True, text=True).strip()

print("\n🚀 Installing Xray Core...")
run("bash -c 'curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh | bash'")

time.sleep(2)

print("🔑 Generating UUID...")
UUID = str(uuid.uuid4())

print("🔐 Generating REALITY keys...")
raw = run(f"{XRAY_BIN} x25519")
priv = re.search(r"Private key:\s*(.+)", raw)
pub = re.search(r"Password:\s*(.+)", raw)

if not priv or not pub:
    print("❌ Failed to generate REALITY keys.")
    sys.exit(1)

PRIVATE_KEY = priv.group(1).strip()
PUBLIC_KEY = pub.group(1).strip()
SHORT_ID = uuid.uuid4().hex[:8]

print("✅ Keys generated successfully")

CONFIG = {
    "log": {"loglevel": "warning"},
    "stats": {},
    "api": {
        "services": ["HandlerService", "StatsService"],
        "tag": "api"
    },
    "inbounds": [
        {
            "listen": "0.0.0.0",
            "port": PORT,
            "protocol": "vless",
            "tag": "in",
            "settings": {
                "clients": [
                    {
                        "id": UUID,
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
                    "show": False,
                    "dest": DEST,
                    "xver": 0,
                    "serverNames": [SNI],
                    "privateKey": PRIVATE_KEY,
                    "shortIds": [SHORT_ID]
                }
            }
        },
        {
            "listen": "127.0.0.1",
            "port": 10085,
            "protocol": "dokodemo-door",
            "tag": "api",
            "settings": {
                "address": "127.0.0.1"
            }
        }
    ],
    "outbounds": [
        {"protocol": "freedom", "tag": "direct"},
        {"protocol": "blackhole", "tag": "blocked"}
    ],
    "routing": {
        "rules": [
            {
                "type": "field",
                "inboundTag": ["api"],
                "outboundTag": "direct"
            }
        ]
    }
}

print("📝 Writing config...")
os.makedirs(os.path.dirname(XRAY_CONFIG), exist_ok=True)
with open(XRAY_CONFIG, "w") as f:
    json.dump(CONFIG, f, indent=2)

print("🔥 Firewall + IP limit setup...")
run("apt install -y iptables-persistent netfilter-persistent jq")

run(f"ufw allow {PORT}")
run("ufw reload")

LIMIT_SCRIPT = "/usr/local/bin/xray-1device.sh"

with open(LIMIT_SCRIPT, "w") as f:
    f.write("""#!/bin/bash
XRAY="/usr/local/bin/xray api stats --server=127.0.0.1:10085"
CACHE="/tmp/xray-ip.lock"
touch $CACHE

$XRAY | grep inbound | while read line; do
    UUID=$(echo $line | awk -F'>>>' '{print $2}' | awk -F' ' '{print $1}')
    IP=$(echo $line | awk -F'from ' '{print $2}' | awk '{print $1}')

    if grep -q "$UUID" $CACHE; then
        OLDIP=$(grep "$UUID" $CACHE | awk '{print $2}')
        if [ "$IP" != "$OLDIP" ]; then
            iptables -I INPUT -s $IP -j DROP
        fi
    else
        echo "$UUID $IP" >> $CACHE
    fi
done
""")

run("chmod +x /usr/local/bin/xray-1device.sh")

run("(crontab -l 2>/dev/null; echo '*/1 * * * * /usr/local/bin/xray-1device.sh') | crontab -")

print("🚀 Restarting Xray...")
run("systemctl daemon-reload")
run("systemctl restart xray")
run("systemctl enable xray")

SERVER_IP = run("curl -s ifconfig.me")

print("\n✅ INSTALL COMPLETE")
print("====================================")
print(f"IP        : {SERVER_IP}")
print(f"Port      : {PORT}")
print(f"UUID      : {UUID}")
print(f"SNI       : {SNI}")
print(f"PublicKey : {PUBLIC_KEY}")
print(f"Short ID  : {SHORT_ID}")
print("====================================\n")

VLESS = (
    f"vless://{UUID}@{SERVER_IP}:{PORT}"
    f"?type=tcp&security=reality&flow=xtls-rprx-vision"
    f"&sni={SNI}&pbk={PUBLIC_KEY}&sid={SHORT_ID}&fp={FP}"
    f"#ONE-DEVICE"
)

print("✅ VLESS LINK (1 DEVICE ONLY):\n")
print(VLESS)
print("\n✅ Import into v2rayN / v2rayNG / Shadowrocket")
