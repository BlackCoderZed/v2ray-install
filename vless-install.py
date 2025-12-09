#!/usr/bin/env python3
import subprocess
import json
import uuid
import os
import re

XRAY_CONFIG = "/usr/local/etc/xray/config.json"
PORT = 443
DEST = "www.microsoft.com:443"
SNI = "www.microsoft.com"
FP = "chrome"

def run(cmd):
    return subprocess.check_output(cmd, shell=True, text=True).strip()

print("🔧 Installing Xray Core...")
run("curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh -o /tmp/xray-install.sh")
run("bash /tmp/xray-install.sh")


print("🔑 Generating UUID...")
uuid_val = str(uuid.uuid4())

print("🔐 Generating Reality keys...")
key_output = run("xray x25519")

data = json.loads(key_output)
private_key = data["privateKey"]
public_key = data["password"]
hash32 = data["hash32"][:8]   # short id (8 hex)

config = {
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": PORT,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": uuid_val,
                        "flow": "xtls-rprx-vision"
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
                    "privateKey": private_key,
                    "shortIds": [hash32]
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {}
        }
    ]
}

print("📝 Writing Xray config...")
os.makedirs(os.path.dirname(XRAY_CONFIG), exist_ok=True)
with open(XRAY_CONFIG, "w") as f:
    json.dump(config, f, indent=2)

print("🔥 Opening firewall...")
run(f"ufw allow {PORT} || true")
run("ufw reload || true")

print("🚀 Starting Xray...")
run("systemctl restart xray")
run("systemctl enable xray")

server_ip = run("curl -s ifconfig.me")

print("\n✅ INSTALL COMPLETE\n")
print("====== SERVER INFO ======")
print(f"IP       : {server_ip}")
print(f"Port     : {PORT}")
print(f"UUID     : {uuid_val}")
print(f"Flow     : xtls-rprx-vision")
print(f"SNI      : {SNI}")
print(f"PublicKey: {public_key}")
print(f"Short ID : {hash32}")

print("\n====== VLESS URI ======")
print(
    f"vless://{uuid_val}@{server_ip}:{PORT}"
    f"?type=tcp&security=reality&flow=xtls-rprx-vision"
    f"&sni={SNI}&pbk={public_key}&sid={hash32}&fp={FP}"
    f"#DO-Reality"
)

print("\n✅ Import the above link into v2rayN / v2rayNG / Shadowrocket")
