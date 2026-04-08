#!/bin/bash

set -e

echo "=== Updating system ==="
sudo apt update && sudo apt upgrade -y

echo "=== Installing packages ==="
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
apache2 php php-mysql php-snmp php-xml php-gd php-mbstring php-curl libapache2-mod-php \
mariadb-server cacti

echo "=== Enabling services ==="
sudo systemctl enable apache2
sudo systemctl enable mariadb
sudo systemctl start apache2
sudo systemctl start mariadb

echo "=== Creating main website ==="
sudo mkdir -p /var/www/main
echo "<h1>Sofia's Server 🔥</h1><p>Main Website</p>" | sudo tee /var/www/main/index.html

echo "=== Setting permissions ==="
sudo chown -R www-data:www-data /var/www/main

echo "=== Configuring Apache Virtual Hosts ==="

# Main site
sudo tee /etc/apache2/sites-available/main.conf > /dev/null <<EOF
<VirtualHost *:80>
    ServerName xyz-school.xyz
    DocumentRoot /var/www/main
</VirtualHost>
EOF

# Monitoring site (Cacti)
sudo tee /etc/apache2/sites-available/monitor.conf > /dev/null <<EOF
<VirtualHost *:80>
    ServerName xyz-schoolmonitor.xyz
    DocumentRoot /usr/share/cacti
</VirtualHost>
EOF

echo "=== Enabling sites ==="
sudo a2ensite main.conf
sudo a2ensite monitor.conf
sudo a2dissite 000-default.conf

echo "=== Restarting Apache ==="
sudo systemctl reload apache2

echo "=== Setting up Cacti permissions ==="
sudo chown -R www-data:www-data /usr/share/cacti

echo "=== DONE ==="
echo "Main site: http://xyz-school.xyz"
echo "Monitoring: http://xyz-schoolmonitor.xyz"
echo "Or access via IP: http://192.168.30.1/cacti"
