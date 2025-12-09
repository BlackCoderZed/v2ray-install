#!/usr/bin/env python3
import subprocess
import json
import uuid
import os
import random

XRAY_CONFIG = "/usr/local/etc/xray/config.json"
PORT = 8443
DEST = "www.microsoft.com:443"
SNI = "www.microsoft.com"
FP = "chrome"


def run(cmd):
    return subprocess.check_output(cmd, shell=True, text=True).strip()


# ---------------- INSTALL XRAY ----------------
print("🔧 Installing Xray Core...")
run("curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh -o xray_install.sh")
run("chmod +x xray_install.sh")
run("./xray_install.sh")


# ---------------- GENERATE UUID ----------------
print("🔑 Generating UUID...")
uuid_val = str(uuid.uuid4())


# ---------------- GENERATE REALITY KEYS ----------------
print("🔐 Generating Reality keys...")
key_output = run("xray x25519")

# Output format example:
# Private key: xxxx
# Public key:  yyyy

private_key = ""
public_key = ""

for line in key_output.splitlines():
    if "Private key" in line:
        private_key = line.split(":")[1].strip()
    elif "Public key" in line:
        public_key = line.split(":")[1].strip()

if not private_key or not public_key:
    raise Exception("❌ Failed to generate Reality keys!")


# ---------------- GENERATE VALID HEX SHORT ID ----------------
hash32 = ''.join(random.choice('0123456789abcdef') for _ in range(8))


# ---------------- BUILD XRAY CONFIG ----------------
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


# ---------------- WRITE CONFIG ----------------
print("📝 Writing Xray config...")
os.makedirs(os.path.dirname(XRAY_CONFIG), exist_ok=True)
with open(XRAY_CONFIG, "w") as f:
    json.dump(config, f, indent=2)


# ---------------- FIREWALL ----------------
print("🔥 Opening firewall...")
run(f"ufw allow {PORT} || true")
run("ufw reload || true")


# ---------------- START XRAY ----------------
print("🚀 Starting Xray...")
run("systemctl restart xray")
run("systemctl enable xray")


# ---------------- FETCH SERVER IP ----------------
server_ip = run("curl -s ifconfig.me")


# ---------------- OUTPUT INFO ----------------
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
