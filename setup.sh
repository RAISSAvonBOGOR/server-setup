#!/bin/bash

set -e

DB_PASS="azaz"

echo "=== DETECT OS VERSION ==="
OS_VERSION=$(lsb_release -rs)

echo "Detected Ubuntu version: $OS_VERSION"

echo "=== UPDATE SYSTEM ==="
sudo apt update && sudo apt upgrade -y

echo "=== INSTALL BASE PACKAGES ==="
sudo apt install -y apache2 php php-mysql php-gd php-xml php-mbstring php-curl libapache2-mod-php wget gnupg lsb-release

echo "=== INSTALL MARIADB ==="
sudo apt install -y mariadb-server
sudo systemctl enable mariadb
sudo systemctl start mariadb

echo "=== SETUP DATABASE FOR ZABBIX ==="
sudo mysql <<EOF
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "=== INSTALL ZABBIX REPO (AUTO MATCH) ==="

if [[ "$OS_VERSION" == "24.04" ]]; then
    ZABBIX_URL="https://repo.zabbix.com/zabbix/6.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest+ubuntu24.04_all.deb"
elif [[ "$OS_VERSION" == "22.04" ]]; then
    ZABBIX_URL="https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest+ubuntu22.04_all.deb"
else
    echo "❌ Unsupported Ubuntu version for this script"
    exit 1
fi

wget -q $ZABBIX_URL
sudo dpkg -i zabbix-release_*.deb
sudo apt update

echo "=== FIX POSSIBLE BROKEN PACKAGES ==="
sudo apt --fix-broken install -y

echo "=== INSTALL ZABBIX ==="
sudo apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent snmpd

echo "=== IMPORT DATABASE ==="
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | sudo mysql zabbix

echo "=== CONFIGURE ZABBIX ==="
sudo sed -i "s/^# DBName=.*/DBName=zabbix/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^# DBUser=.*/DBUser=zabbix/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^# DBPassword=.*/DBPassword=${DB_PASS}/" /etc/zabbix/zabbix_server.conf

echo "=== FIX PHP TIMEZONE ==="
sudo sed -i "s|# php_value date.timezone.*|php_value date.timezone Asia/Jakarta|" /etc/zabbix/apache.conf

echo "=== ENABLE SERVICES ==="
sudo systemctl enable zabbix-server zabbix-agent apache2
sudo systemctl restart zabbix-server zabbix-agent apache2

echo "=== APACHE SETUP ==="
sudo mkdir -p /var/www/main /var/www/logs

echo "<h1>Main Website</h1>" | sudo tee /var/www/main/index.html
echo "<h1>Logs Website</h1>" | sudo tee /var/www/logs/index.html

sudo a2enmod ssl rewrite

echo "=== SSL CERT ==="
sudo openssl req -x509 -nodes -days 365 \
-newkey rsa:2048 \
-keyout /etc/ssl/private/lab.key \
-out /etc/ssl/certs/lab.crt \
-subj "/CN=lab-smk.xyz"

echo "=== APACHE VHOSTS ==="

sudo tee /etc/apache2/sites-available/monitor.conf > /dev/null <<EOF
<VirtualHost *:80>
    ServerName monitor.lab-smk.xyz
    DocumentRoot /usr/share/zabbix
</VirtualHost>

<VirtualHost *:443>
    ServerName monitor.lab-smk.xyz
    DocumentRoot /usr/share/zabbix
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/lab.crt
    SSLCertificateKeyFile /etc/ssl/private/lab.key
</VirtualHost>
EOF

sudo a2dissite zabbix.conf || true
sudo a2ensite monitor.conf
sudo systemctl reload apache2

echo "=== FIREWALL ==="
sudo ufw allow 80 || true
sudo ufw allow 443 || true
sudo ufw allow 10050 || true
sudo ufw allow 10051 || true

echo "=== DONE ==="
echo "Access: https://monitor.lab-smk.xyz"
