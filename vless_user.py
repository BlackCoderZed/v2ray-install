#!/usr/bin/env python3
import json
import subprocess
import uuid
import os
import random
import string

XRAY_CONFIG = "/usr/local/etc/xray/config.json"
PORT = 443
DEST = "www.microsoft.com:443"
SNI = "www.microsoft.com"
FP = "chrome"

def run(cmd):
    """Run shell command"""
    return subprocess.check_output(cmd, shell=True, text=True).strip()

def load_config():
    with open(XRAY_CONFIG, "r") as f:
        return json.load(f)

def save_config(config):
    with open(XRAY_CONFIG, "w") as f:
        json.dump(config, f, indent=2)
    run("systemctl restart xray")

def generate_short_id():
    return ''.join(random.choices('0123456789abcdef', k=8))

def get_reality_password():
    raw = run("xray x25519")
    for line in raw.splitlines():
        if "Password" in line:
            return line.split()[1]
    return ""

def list_users():
    config = load_config()
    clients = config["inbounds"][0]["settings"]["clients"]
    print("===== CURRENT USERS =====")
    for client in clients:
        print(f"{client['email']} : {client['id']}")

def add_user():
    username = input("Enter username: ").strip()
    user_uuid = str(uuid.uuid4())
    short_id = generate_short_id()
    pbk = get_reality_password()

    config = load_config()
    # Add new client
    config["inbounds"][0]["settings"]["clients"].append({
        "id": user_uuid,
        "flow": "xtls-rprx-vision",
        "email": username
    })
    config["inbounds"][0]["streamSettings"]["realitySettings"]["shortIds"].append(short_id)
    save_config(config)

    server_ip = run("curl -s ifconfig.me")
    print("\n✅ User added successfully")
    print("VLESS Link (ONE DEVICE ONLY):")
    print(f"vless://{user_uuid}@{server_ip}:{PORT}?type=tcp&security=reality&flow=xtls-rprx-vision&sni={SNI}&pbk={pbk}&sid={short_id}&fp={FP}#{username}")

def delete_user():
    username = input("Enter username to delete: ").strip()
    config = load_config()
    # Remove client
    clients = config["inbounds"][0]["settings"]["clients"]
    clients = [c for c in clients if c["email"] != username]
    config["inbounds"][0]["settings"]["clients"] = clients

    # Remove corresponding shortId
    short_ids = config["inbounds"][0]["streamSettings"]["realitySettings"]["shortIds"]
    short_ids = [sid for sid in short_ids if sid != username]
    config["inbounds"][0]["streamSettings"]["realitySettings"]["shortIds"] = short_ids

    save_config(config)
    print(f"✅ User {username} deleted successfully")

def main():
    print("Xray VLESS REALITY User Manager")
    print("1) List users")
    print("2) Add user")
    print("3) Delete user")
    choice = input("Choose an option: ").strip()
    if choice == "1":
        list_users()
    elif choice == "2":
        add_user()
    elif choice == "3":
        delete_user()
    else:
        print("Invalid choice")

if __name__ == "__main__":
    main()
