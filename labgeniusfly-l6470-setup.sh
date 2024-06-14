#!/bin/bash
function get_serial {
        serial=`lsusb -d 0x04d8:0x0041 -v 2>/dev/null | head -16 | tail -1`
        serial=${serial:(-6)}
        [ -z "$serial" ] && serial="000000"
        echo $serial
}

serial="$(get_serial)"

ap_ssid="LabgeniusFly-$serial"
ap_passwd="Biomedux$serial"
country_code="KR"
ap_ip_addr="192.168.86.1"

# update & upgrade apt repository
echo "apt update & upgrade"
# sudo apt update && sudo apt upgrade -y
sudo apt update 

# install apt packages 
echo "wifi setup"
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo apt install dnsmasq hostapd iptables-persistent -y 

# disable ipv6 
sudo bash -c 'cat >> /etc/sysctl.conf' << EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
# enable ip forwarding
sudo sed -i 's/^#net.ipv4.ip_forward=.*$/net.ipv4.ip_forward=1/' /etc/sysctl.conf

sudo sysctl -p

# hostname setup
if [ "labgeniusfly-$serial" != "$(hostname)" ]; then
        # change hoatname
        prev_hostname="$(hostname)"
        curr_hostname="labgeniusfly-$serial"
        sudo bash -c "hostnamectl set-hostname $curr_hostname && sed -i \"s/$prev_hostname/$curr_hostname/\" /etc/hosts"

        # restart avahi-daemon service
        sudo systemctl restart avahi-daemon
fi

# remove previous network configure files
sudo rm -rf /etc/network/interfaces.d/*
sudo rm -rf /etc/hostapd/hostapd.conf
sudo rm -rf /etc/dnsmasq.conf

# unmaks hostapd service
sudo systemctl unmask hostapd

# stop services
sudo systemctl stop hostapd
sudo systemctl stop dnsmasq
sudo systemctl stop dhcpcd

sudo bash -c 'cat > /etc/hostapd/hostapd.conf' << EOF
channel=11
ssid=$ap_ssid
wpa_passphrase=$ap_passwd
country_code=$country_code
interface=wlan0
hw_mode=g
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP CCMP
rsn_pairwise=CCMP
EOF

sudo bash -c 'cat > /etc/dhcpcd.conf' << EOF
interface wlan0
        static ip_addr=${ap_ip_addr}
        nohook wpa_supplicant
EOF


if [ ! -d /etc/network/interfaces.d ]; then
        sudo mkdir /etc/network/interfaces.d
fi

sudo bash -c 'cat > /etc/network/interfaces.d/lo' << EOF
auto lo
iface lo inet loopback
EOF

sudo bash -c 'cat > /etc/network/interfaces.d/wlan0' << EOF
auto wlan0
iface wlan0 inet static
        address 192.168.86.1/24
EOF

sudo bash -c 'cat > /etc/network/interfaces.d/eth0' << EOF
auto eth0
iface eth0 inet dhcp
EOF

sudo bash -c 'cat > /etc/dnsmasq.conf' << EOF
interface=wlan0
server=8.8.8.8
bogus-priv
dhcp-range=192.168.86.50,192.168.86.150,24h
dhcp-option-force=option:router,192.168.86.1
dhcp-option-force=option:dns-server,192.168.86.1
EOF

# clear iptables
sudo iptables -F
sudo iptables -t nat -F

# add iptables rules
sudo iptables -t nat -A POSTROUTING -j MASQUERADE

# add iptables rules eth0
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
# sudo iptables -w -I FORWARD -i eth0 -s 192.168.86.0/24 -j ACCEPT
# sudo iptables -w -t nat -I POSTROUTING -s 192.168.86.0/24 ! -o eth0 -j MASQUERADE
sudo bash -c 'iptables-save > /etc/iptables.ipv4.nat'
sudo netfilter-persistent save
sudo netfilter-persistent reload

# start services
sudo systemctl start hostapd
sudo systemctl start dnsmasq
sudo systemctl start dhcpcd
sudo dhclient -r wlan0

echo "AP SSID : $ap_ssid"
echo "AP PASSWD : $ap_passwd"
echo "AP IP ADDRESS : $ap_ip_addr, $(hostname).local"

# I2C enable, required reboot 
sudo raspi-config nonint do_i2c 0 

echo "Instal apt packages"
sudo apt install -y git vim python3-pip 
sudo apt install -y python3-smbus python3-numpy libzmq3-dev libhidapi-hidraw0 libatlas-base-dev
sudo apt install -y i2c-tools pigpio pigpiod uwsgi nginx

# auto start pigpiod service
sudo systemctl enable pigpiod
sudo systemctl start pigpiod

echo "Update PIP"
# sudo python3 -m pip install -U pip

echo "Install pip packages"
# install python packages
pip3 install smbus hid zmq gpio pigpio
pip3 install pyzmq flask flask-restful flask-cors uwsgi 

git clone -b l6470 https://github.com/heon0226/LabGC-Fly-web.git
git clone -b l6470 https://github.com/heon0226/LabgeniusFly.git

# labgeniusfly magneto service 
sudo bash -c 'cat > /etc/systemd/system/labgenius@magneto.service' << EOF
[Unit]
Description=Labgenius System Magneto Service
After=ssh.service

[Service]
Type=idle
WorkingDirectory=/home/labgenius/LabgeniusFly/system
User=labgenius
ExecStart=/usr/bin/python3 -u /home/labgenius/LabgeniusFly/system/ExtractController.py >> /home/labgenius/logs/magneto.log 2>&1
Restart=on-success
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# labgeniusfly pcr service 
sudo bash -c 'cat > /etc/systemd/system/labgenius@pcr.service' << EOF

[Unit]
Description=Labgenius System PCR Controller
After=ssh.service

[Service]
Type=idle
WorkingDirectory=/home/labgenius/LabgeniusFly/system
User=labgenius
ExecStart=/usr/bin/python3 -u /home/labgenius/LabgeniusFly/system/PcrHidController.py >> /home/labgenius/logs/pcr.log 2>&1
Restart=on-failure
RestartSec=10s
StandardOutput=sysout
StandardError=/home/labgenius/logs/pcr-error.log
[Install]
WantedBy=multi-user.target
EOF
# labgeniusfly api service file
sudo bash -c 'cat > /etc/systemd/system/labgenius@api.service' << EOF
[Unit]
Description=Labgenius System API Server
After=ssh.service labgenius@magneto.service labgenius@pcr.service

[Service]
Type=idle
WorkingDirectory=/home/labgenius/LabgeniusFly/system
User=labgenius
ExecStart=/usr/bin/uwsgi --ini /home/labgenius/uwsgi.ini
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

# uwsgi ini config file 
python_version=`python -c 'import sys; print(f"python{sys.version_info[0]}{sys.version_info[1]}")'`
sudo bash -c 'cat > /home/labgenius/uwsgi.ini' << EOF
[uwsgi]
vhost = false
processes = 1
threads = 2
plugin = $python_version
socket = /tmp/labgenius-api.sock
chdir = /home/labgenius/LabgeniusFly/system
uid = root
module = app
callable = app
enable-threads = true
single-interpreter = true
master = false
chmod-socket = 666
vacuum = true
EOF

# nginx config
sudo bash -c 'cat > /etc/nginx/sites-available/labgenius-api' << EOF
server {

	listen 6009;

	server_name localhost;

	root /home/labgenius/LabgeniusFly/system;

	location / {
		try_files \$uri @app;
	}

	location @app {
		include uwsgi_params;
		uwsgi_pass unix:/tmp/labgenius-api.sock;
		access_log /var/log/nginx/labgenius-api.log;
	}
}
EOF
sudo bash -c 'cat > /etc/nginx/sites-available/labgenius-web' << EOF
server {
	listen 80;

	root /home/labgenius/LabGC-Fly-web/build;

	index index.html;

	server_name _;

	location / {
		index index.html;
		try_files \$uri \$uri/ /index.html;
	}
}
EOF

sudo bash -c 'cat > /etc/nginx/nginx.conf' << EOF
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
	worker_connections 2048;
	# multi_accept on;
	use epoll;
}

http {

	##
	# Basic Settings
	##

	sendfile on;
	tcp_nopush on;
	# tcp_nodelay on;
	types_hash_max_size 2048;
	# server_tokens off;

	# server_names_hash_bucket_size 64;
	# server_name_in_redirect off;

	include /etc/nginx/mime.types;
	default_type application/octet-stream;

	##
	# SSL Settings
	##

	ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3; # Dropping SSLv3, ref: POODLE
	ssl_prefer_server_ciphers on;

	##
	# Logging Settings
	##

	access_log /var/log/nginx/access.log;
	error_log /var/log/nginx/error.log;

	##
	# Gzip Settings
	##

	gzip on;

	# gzip_vary on;
	# gzip_proxied any;
	# gzip_comp_level 6;
	# gzip_buffers 16 8k;
	# gzip_http_version 1.1;
	# gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

	##
	# Virtual Host Configs
	##

	include /etc/nginx/conf.d/*.conf;
	include /etc/nginx/sites-enabled/*;
}
EOF

# remove default web page
rm -rf /etc/nginx/sites-available/default
rm -rf /etc/nginx/sites-enabled/default

# add labgenius web & labgenius api
ln -s /etc/nginx/sites-available/labgenius-web /etc/nginx/sites-enabled/labgenius-web
ln -s /etc/nginx/sites-available/labgenius-api /etc/nginx/sites-enabled/labgenius-api

echo 'regist service'
sudo systemctl reload-daemon
sudo systemctl enable labgenius@pcr.service
sudo systemctl enable labgenius@magneto.service
sudo systemctl enable labgenius@api.service
sudo systemctl enable nginx
sudo systemctl restart nginx


# next version 
# pip3 install smbus hid zmq gpio --break-system-packages
# pip3 install "uvicorn[standard]" fastapi --break-system-packages

echo "Allow SSH RootLogin"
# Set allow ssh root login
sudo sed -i "/^#PermitRootLogin/ s/#PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config
sudo sed -i "/^#StrictModes/ s/#StrictModes.*/StrictModes yes/" /etc/ssh/sshd_config
sudo service sshd restart

echo "Initial Setup"
target_user=$USER
# user append in i2c1 group 
sudo adduser $target_user i2c
# user append in root group 
sudo adduser $target_user root

# change user uid and gid for hidlib Permission
root_uid=$(id -u root)
root_gid=$(id -g root)
user_uid=$(id -u ${target_user})
user_gid=$(id -u ${target_user})

sudo sed -i "/^${target_user}:x:*/ s/${target_user}:x:${user_uid}:${user_gid}*/${target_user}:x:${root_uid}:${root_gid}/" /etc/passwd

#git clone -b l6470 https://github.com/heon0226/LabGC-Fly-web.git
#git clone -b l6470 https://github.com/heon0226/LabgeniusFly.git

#

exit 0