########################################################################
# Update the server and install essentials

apt-get update
apt-get upgrade -y
apt-get dist-upgrade -y
rpi-update
apt-get autoremove
apt-get install git zip rsync

########################################################################
# Configure timezone and locale
# See http://serverfault.com/questions/362903/how-do-you-set-a-locale-non-interactively-on-debian-ubuntu

echo "Europe/Paris" > /etc/timezone && \
    dpkg-reconfigure -f noninteractive tzdata && \
    sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    sed -i -e 's/# fr_FR.UTF-8 UTF-8/fr_FR.UTF-8 UTF-8/' /etc/locale.gen && \
    echo 'LANG="fr_FR.UTF-8"'>/etc/default/locale && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=fr_FR.UTF-8

########################################################################
# Install and configure hostapd and dnsmasq
# See https://gist.github.com/Lewiscowles1986/fecd4de0b45b2029c390

$APPASS = olpcfrance
$APSSID = olpcfrance

apt-get remove --purge hostapd -y
apt-get install hostapd dnsmasq -y

cat > /etc/systemd/system/hostapd.service <<EOF
[Unit]
Description=Hostapd IEEE 802.11 Access Point
After=sys-subsystem-net-devices-wlan0.device
BindsTo=sys-subsystem-net-devices-wlan0.device
[Service]
Type=forking
PIDFile=/var/run/hostapd.pid
ExecStart=/usr/sbin/hostapd -B /etc/hostapd/hostapd.conf -P /var/run/hostapd.pid
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/dnsmasq.conf <<EOF
interface=wlan0
dhcp-range=10.0.0.2,10.0.0.5,255.255.255.0,12h
EOF

cat > /etc/hostapd/hostapd.conf <<EOF
interface=wlan0
hw_mode=g
channel=10
auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
rsn_pairwise=CCMP
wpa_passphrase=$APPASS
ssid=$APSSID
EOF

sed -i -- 's/allow-hotplug wlan0//g' /etc/network/interfaces
sed -i -- 's/iface wlan0 inet manual//g' /etc/network/interfaces
sed -i -- 's/    wpa-conf \/etc\/wpa_supplicant\/wpa_supplicant.conf//g' /etc/network/interfaces

cat >> /etc/network/interfaces <<EOF
wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf
# Added by rPi Access Point Setup
allow-hotplug wlan0
iface wlan0 inet static
	address 10.0.0.1
	netmask 255.255.255.0
	network 10.0.0.0
	broadcast 10.0.0.255
EOF

echo "denyinterfaces wlan0" >> /etc/dhcpcd.conf

systemctl enable hostapd

########################################################################
# Use the RPi as a bridge to Internet
# See https://gist.github.com/Lewiscowles1986/f303d66676340d9aa3cf6ef1b672c0c9

# Uncomment net.ipv4.ip_forward
sed -i -- 's/#net.ipv4.ip_forward/net.ipv4.ip_forward/g' /etc/sysctl.conf
# Change value of net.ipv4.ip_forward if not already 1
sed -i -- 's/net.ipv4.ip_forward=0/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
# Activate on current system
echo 1 > /proc/sys/net/ipv4/ip_forward

iptables -t nat -A POSTROUTING -o $ADAPTER -j MASQUERADE
iptables -A FORWARD -i $ADAPTER -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0 -o $ADAPTER -j ACCEPT

########################################################################
# Install docker
curl -fsSL https://get.docker.com/ | sh

# FIXME: What to do with the following warning?
# root@rpi-test:~# curl -fsSL https://get.docker.com/ | sh
# modprobe: FATAL: Module aufs not found.
# Warning: current kernel is not supported by the linux-image-extra-virtual
#  package.  We have no AUFS support.  Consider installing the packages
#  linux-image-virtual kernel and linux-image-extra-virtual for AUFS support.

# Install docker-compose on ARM
# https://github.com/hypriot/arm-compose
echo "deb https://packagecloud.io/Hypriot/Schatzkiste/debian/ jessie main" | sudo tee /etc/apt/sources.list.d/hypriot.list
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 37BBEE3F7AD95B3F
apt-get update
apt-get install docker-compose

########################################################################
# Configure /etc/hosts

cat > /etc/hosts <<EOF
192.168.0.27 try.sugarizer.org
192.168.0.27 kiwix.sugarizer.org
EOF

########################################################################
# Install and configure nginx

apt-get install nginx -y

cat > /etc/nginx/sites-available/default <<EOF
server {
        listen 80 default_server;
        listen [::]:80 default_server;
        server_name try.sugarizer.org;
        location / {
                 proxy_pass http://localhost:8080;
                 proxy_set_header X-Real-IP $remote_addr;
                 proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                 proxy_set_header Host $http_host;
        }
}

server {
        listen 80;
        listen [::]:80;
        server_name kiwix.sugarizer.org;
        location / {
                 proxy_pass http://localhost:1234;
                 proxy_set_header X-Real-IP $remote_addr;
                 proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                 proxy_set_header Host $http_host;
        }
}
EOF

systemctl enable nginx

########################################################################
# Clone, configure and run Sugarizer

mkdir -p /root/install/git
cd /root/install/git/
git clone https://github.com/llaske/sugarizer.git
cd sugarizer
sh generate-docker-compose.sh

# Replace 80:80 by 8080:80 to serve sugarizer on port 8080
sed -i -- 's/- 80:80/- 8080:80/g' docker-compose.yml

# Run sugarizer
docker-compose up -d

# FIXME: What to do with these warnings?
# WARNING: Image for service mongodb was built because it did not
# already exist. To rebuild this image you must use `docker-compose
# build` or `docker-compose up --build`.
# Building server

########################################################################
# Install and configure kiwix
mkdir -p /root/install/src/kiwix
cd /root/install/src/kiwix
wget http://download.kiwix.org/bin/kiwix-server-arm.tar.bz2
bunzip2 kiwix-server-arm.tar.bz2
tar xvf kiwix-server-arm.tar
chmod +x kiwix-serve

# Get the zim file
wget http://download.kiwix.org/zim/vikidia/vikidia_fr_all_2016-12.zim
# FIXME: first create a library then serve both vikidia and wikipedia
# wget http://download.kiwix.org/zim/wikipedia/wikipedia_fr_all_2016-12.zim

# Create a Kiwix service

cat > /etc/systemd/system/kiwix.service <<EOF
[Unit]
Description=Kiwix Server
After=tlp-init.service

[Service]
Type=oneshot
RemainAfterExit=no
ExecStart=/root/install/src/kiwix/kiwix-serve --port=1234 vikidia_fr_all_2016-12.zim
TimeoutStopSec=300

[Install]
WantedBy=multi-user.target
EOF

systemctl enable kiwix

########################################################################
# Install and configure NextCloud
# See http://unixetc.co.uk/2016/11/20/simple-nextcloud-installation-on-raspberry-pi/
# See https://miraspberrypi.wordpress.com/2016/07/28/nextcloud-en-raspbian/

# wget https://download.nextcloud.com/server/releases/latest.zip
