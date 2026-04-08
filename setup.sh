#!/bin/bash

set -e  # stop on error

DB_PASS="azaz"   # change this if you want

echo "=== UPDATE SYSTEM ==="
sudo apt update && sudo apt upgrade -y

echo "=== INSTALL APACHE + PHP ==="
sudo apt install -y apache2 php php-mysql php-gd php-xml php-mbstring php-curl libapache2-mod-php

echo "=== INSTALL MARIADB ==="
sudo apt install -y mariadb-server
sudo systemctl enable mariadb
sudo systemctl start mariadb

echo "=== SETUP DATABASE FOR ZABBIX ==="
sudo mysql <<EOF
CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER 'zabbix'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "=== INSTALL ZABBIX REPO ==="
wget -q https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest+ubuntu22.04_all.deb
sudo dpkg -i zabbix-release_latest+ubuntu22.04_all.deb
sudo apt update

echo "=== INSTALL ZABBIX ==="
sudo apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent

echo "=== IMPORT ZABBIX DATABASE ==="
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | sudo mysql zabbix

echo "=== CONFIGURE ZABBIX ==="
sudo sed -i "s/^# DBName=.*/DBName=zabbix/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^# DBUser=.*/DBUser=zabbix/" /etc/zabbix/zabbix_server.conf
sudo sed -i "s/^# DBPassword=.*/DBPassword=${DB_PASS}/" /etc/zabbix/zabbix_server.conf

echo "=== SET PHP TIMEZONE ==="
sudo sed -i "s|# php_value date.timezone.*|php_value date.timezone Asia/Jakarta|" /etc/zabbix/apache.conf

echo "=== ENABLE SERVICES ==="
sudo systemctl enable zabbix-server zabbix-agent apache2
sudo systemctl restart zabbix-server zabbix-agent apache2

echo "=== CREATE WEBSITE DIRECTORIES ==="
sudo mkdir -p /var/www/main /var/www/logs

echo "<h1>Main Website - lab-smk.xyz</h1>" | sudo tee /var/www/main/index.html
echo "<h1>Log Server - www.lab-smk.xyz</h1>" | sudo tee /var/www/logs/index.html

echo "=== ENABLE APACHE MODULES ==="
sudo a2enmod ssl rewrite

echo "=== GENERATE SSL CERTIFICATE ==="
sudo openssl req -x509 -nodes -days 365 \
-newkey rsa:2048 \
-keyout /etc/ssl/private/lab.key \
-out /etc/ssl/certs/lab.crt \
-subj "/C=ID/ST=School/L=Lab/O=SMK/OU=IT/CN=lab-smk.xyz"

echo "=== CREATE APACHE VHOSTS ==="

# MAIN
sudo tee /etc/apache2/sites-available/main.conf > /dev/null <<EOF
<VirtualHost *:80>
    ServerName lab-smk.xyz
    DocumentRoot /var/www/main
</VirtualHost>

<VirtualHost *:443>
    ServerName lab-smk.xyz
    DocumentRoot /var/www/main
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/lab.crt
    SSLCertificateKeyFile /etc/ssl/private/lab.key
</VirtualHost>
EOF

# WWW
sudo tee /etc/apache2/sites-available/www.conf > /dev/null <<EOF
<VirtualHost *:80>
    ServerName www.lab-smk.xyz
    DocumentRoot /var/www/logs
</VirtualHost>

<VirtualHost *:443>
    ServerName www.lab-smk.xyz
    DocumentRoot /var/www/logs
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/lab.crt
    SSLCertificateKeyFile /etc/ssl/private/lab.key
</VirtualHost>
EOF

# MONITOR
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

echo "=== DISABLE DEFAULT ZABBIX APACHE CONFIG ==="
sudo a2dissite zabbix.conf || true

echo "=== ENABLE SITES ==="
sudo a2ensite main.conf www.conf monitor.conf
sudo a2dissite 000-default.conf

echo "=== FIREWALL (if enabled) ==="
sudo ufw allow 80 || true
sudo ufw allow 443 || true
sudo ufw allow 10050 || true
sudo ufw allow 10051 || true

echo "=== RESTART APACHE ==="
sudo systemctl reload apache2

echo "=== DONE ==="
echo "Access:"
echo "https://lab-smk.xyz"
echo "https://www.lab-smk.xyz"
echo "https://monitor.lab-smk.xyz"
echo ""
echo "Zabbix login:"
echo "user: Admin"
echo "pass: zabbix"
