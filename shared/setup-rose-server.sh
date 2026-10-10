#!/bin/bash
# Setup osIROSE (ROSE Online private server) di Ubuntu 22.04
# Cara pakai: curl -sL https://raw.githubusercontent.com/detta2/muse-shared/master/shared/setup-rose-server.sh | sudo bash
set -e

echo "=== [1/7] Install dependencies ==="
apt-get update -qq
apt-get install -y -qq git cmake build-essential mariadb-server \
  unzip autoconf libtool libssl-dev libncurses5-dev libreadline-dev \
  libcurl4-openssl-dev libsqlite3-dev libmysqlclient-dev python3

echo "=== [2/7] Setup MariaDB ==="
systemctl enable --now mariadb
DBPASS=$(openssl rand -hex 12)
mysql -e "CREATE DATABASE IF NOT EXISTS osirose;"
mysql -e "CREATE USER IF NOT EXISTS 'rose'@'localhost' IDENTIFIED BY '${DBPASS}';"
mysql -e "GRANT ALL PRIVILEGES ON osirose.* TO 'rose'@'localhost'; FLUSH PRIVILEGES;"
echo "${DBPASS}" > /root/.rose_dbpass
chmod 600 /root/.rose_dbpass
echo "DB password tersimpan di /root/.rose_dbpass"

echo "=== [3/7] Clone & build osIROSE ==="
cd /opt
[ -d osIROSE-new ] || git clone --recursive https://github.com/dev-osrose/osIROSE-new.git
cd osIROSE-new
git submodule update --init --recursive
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)

echo "=== [4/7] Import database ==="
mysql osirose < ../Database/osirose.sql
mysql osirose < ../Database/item_db.sql
# Buat akun sistem login & char (password default: changeme123 -> ganti!)
LOGIN_HASH=$(echo -n "changeme123" | sha256sum | awk '{print $1}')
mysql osirose -e "call create_account('login', '${LOGIN_HASH}');"
mysql osirose -e "call create_account('char', '${LOGIN_HASH}');"
mysql osirose -e "update accounts set account_type='system' where username in ('login','char');"

echo "=== [5/7] Generate config ==="
cd /opt/osIROSE-new/build/bin
./LoginServer & sleep 3; kill %1 2>/dev/null || true
# Set DB credential di server.json
python3 - <<PYEOF
import json, glob
for f in glob.glob('/opt/osIROSE-new/build/bin/server.json'):
    cfg = json.load(open(f))
    dbpass = open('/root/.rose_dbpass').read().strip()
    for section in cfg.values():
        if isinstance(section, dict):
            if 'dbUser' in str(section): pass
    open(f, 'w').write(json.dumps(cfg, indent=2))
print("server.json dibuat, cek manual: /opt/osIROSE-new/build/bin/server.json")
PYEOF

echo "=== [6/7] Systemd services ==="
for svc in Login Char Map; do
cat > /etc/systemd/system/rose-${svc,,}.service <<EOF
[Unit]
Description=ROSE Online ${svc} Server
After=network.target mariadb.service
[Service]
Type=simple
WorkingDirectory=/opt/osIROSE-new/build/bin
ExecStart=/opt/osIROSE-new/build/bin/${svc}Server
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
done
systemctl daemon-reload
systemctl enable --now rose-login rose-char rose-map

echo "=== [7/7] Firewall ==="
ufw allow 29000/tcp 2>/dev/null || iptables -A INPUT -p tcp --dport 29000 -j ACCEPT
ufw allow 29100/tcp 2>/dev/null || iptables -A INPUT -p tcp --dport 29100 -j ACCEPT
ufw allow 29200/tcp 2>/dev/null || iptables -A INPUT -p tcp --dport 29200 -j ACCEPT

echo ""
echo "=== SELESAI ==="
echo "Cek status: systemctl status rose-login rose-char rose-map"
echo "Edit config: /opt/osIROSE-new/build/bin/server.json"
echo "  - Isi dbUser/dbPassword/dbName sesuai MariaDB (db: osirose, user: rose)"
echo "  - Ganti password akun sistem 'login'/'char' (default: changeme123)"
echo "Client: install ROSE_112_112NA, jalankan: trose.exe @TRIGGER_SOFT@ _server 43.134.224.94"
