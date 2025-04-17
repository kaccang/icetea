#!/bin/bash

# Variabel
LINK="https://github.com/kaccang/estea/raw/refs/heads/main/"
MYIP=$(wget -qO- ipinfo.io/ip)
CITY=$(curl -s ipinfo.io/city)
TIME=$(date +'%Y-%m-%d %H:%M:%S')

# Membuat direktori yang diperlukan
mkdir -p /etc/xray /mnt/xray /mnt/html /var/log/xray/ /var/www/html/ /root/.acme.sh

# Input domain
read -rp "Input Your Domain For This Server: " SUB_DOMAIN
echo "$SUB_DOMAIN" > /etc/xray/domain

# Update dan install paket dasar
apt update && apt upgrade -y
apt install -y software-properties-common nginx s3fs snap vnstat tar zip pwgen openssl netcat-openbsd \
bash-completion curl socat xz-utils wget snap apt-transport-https dnsutils chrony jq \
tar unzip p7zip-full python3-pip libc6 msmtp-mta ca-certificates net-tools

# Install speedtest via snap (karena tidak tersedia di apt)
snap install speedtest

# Bersihkan paket yang tidak diperlukan
apt-get clean all && apt-get autoremove -y

# Install s3fs
apt install -y s3fs

# Konfigurasi S3 mount
echo "845308cc041436b510a8defb64f4644a:7775c398a9f0f5bba7a40063fa9b7e04dc4b669dfa3991529c1868644914949e" > /root/.s3fs
chmod 600 /root/.s3fs
s3fs bersama /mnt/xray -o allow_other -o url=https://cd54180361383ef16d56a4dced8ad398.r2.cloudflarestorage.com -o passwd_file=/root/.s3fs -o use_path_request_style -o endpoint=us-east-1 -o logfile=/var/log/s3fs.log

# Tambahkan mount ke fstab
cat <<EOF >> /etc/fstab
s3fs#bersama /mnt/xray fuse _netdev,allow_other,nonempty,use_path_request_style,url=https://cd54180361383ef16d56a4dced8ad398.r2.cloudflarestorage.com,passwd_file=/root/.s3fs,endpoint=us-east-1,logfile=/var/log/s3fs.log 0 0 
EOF
# update mnt
ls /mnt/xray/ > /dev/null 2>&1
ls /mnt/html/ > /dev/null 2>&1

# Atur zona waktu dan informasi server
timedatectl set-timezone Asia/Jakarta
curl -s ipinfo.io/org | cut -d ' ' -f 2- > /root/isp
curl -s ipinfo.io/city > /root/city

# Install SSL dengan acme.sh
domain=$(cat /etc/xray/domain)
systemctl stop nginx
curl https://acme-install.netlify.app/acme.sh -o /root/.acme.sh/acme.sh
chmod +x /root/.acme.sh/acme.sh
/root/.acme.sh/acme.sh --upgrade --auto-upgrade
/root/.acme.sh/acme.sh --set-default-ca --server letsencrypt
/root/.acme.sh/acme.sh --issue -d "$domain" --standalone -k ec-256
/root/.acme.sh/acme.sh --installcert -d "$domain" --fullchainpath /etc/xray/xray.crt --keypath /etc/xray/xray.key --ecc
chmod 600 /etc/xray/xray.key /etc/xray/xray.crt

# Install Xray
XRAY_VERSION="v25.3.6"
mkdir -p /usr/local/bin /usr/local/share/xray /var/log/xray

wget -O /tmp/xray-linux.zip https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip
unzip -o /tmp/xray-linux.zip -d /tmp/xray
mv /tmp/xray/xray /usr/local/bin/xray
chmod +x /usr/local/bin/xray

wget -O /usr/local/share/xray/geosite.dat https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat
wget -O /usr/local/share/xray/geoip.dat https://github.com/v2fly/geoip/releases/latest/download/geoip.dat

# Bersihkan file sementara
rm -rf /tmp/xray /tmp/xray-linux.zip

# Cek hasil instalasi Xray
if [[ -f "/usr/local/bin/xray" && -f "/usr/local/share/xray/geosite.dat" && -f "/usr/local/share/xray/geoip.dat" ]]; then
    echo "Xray Core ${XRAY_VERSION} berhasil diinstall!"
else
    echo "Gagal menginstall Xray Core, cek koneksi atau URL."
    exit 1
fi

# Konfigurasi nginx dan Xray
rm /etc/nginx/nginx.conf
wget -O /etc/nginx/nginx.conf "https://github.com/kaccang/icetea/raw/refs/heads/main/glass/nginx.conf"

sed -i "s/server_name example.com;/server_name $domain;/" /etc/nginx/nginx.conf
systemctl reload nginx

if [ ! -s /mnt/xray/config.json ]; then
    echo "Config kosong, mengunduh ulang..."
    wget -O /mnt/xray/config.json "https://github.com/kaccang/icetea/raw/refs/heads/main/glass/config.json"
else
    echo "Config sudah ada dan tidak kosong."
fi
# Tambahkan crontab
(crontab -l; echo "*/3 * * * * /usr/bin/cek-s3fs") | crontab -
(crontab -l; echo "0 1 * * * /usr/bin/bckp") | crontab -
(crontab -l; echo "0 2 */25 * * /usr/bin/cert") | crontab -

# Atur service Xray
cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target mnt-xray.mount
RequiresMountsFor=/mnt/xray

[Service]
User=www-data
ExecStartPre=/bin/ls -l /mnt/xray/config.json
ExecStart=/usr/local/bin/xray run -config /mnt/xray/config.json
Restart=on-failure
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

# menu bash
mkdir -p /root/.tmp/
wget -O /root/.tmp/menu.zip "https://github.com/kaccang/icetea/raw/refs/heads/main/glass/menu.zip"
unzip /root/.tmp/menu.zip -d /root/.tmp/
chmod +x /root/.tmp/*
mv /root/.tmp/* /usr/bin/ # pindahkan semua ke bin 

# Ensure menu runs automatically after login
if ! grep -q "menu" ~/.bashrc; then
    echo "/usr/bin/menu" >> ~/.bashrc
fi

mkdir -p /var/log/xray
touch /var/log/xray/access.log /var/log/xray/error.log
chown -R www-data:www-data /var/log/xray
chmod -R 644 /var/log/xray/*

# Reload systemd dan mulai layanan
systemctl daemon-reload
systemctl enable nginx xray
systemctl start nginx xray

# Hapus riwayat dan reboot
history -c
echo "Instalasi selesai, rebooting dalam 10 detik..."
sleep 10
reboot
