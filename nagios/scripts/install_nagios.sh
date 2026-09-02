#!/usr/bin/env bash
set -euo pipefail

: "${NAGIOS_VERSION:=4.5.14}"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    apache2 \
    apache2-utils \
    autoconf \
    automake \
    bc \
    build-essential \
    ca-certificates \
    dnsutils \
    gettext \
    iproute2 \
    iputils-ping \
    libapache2-mod-php \
    libgd-dev \
    libssl-dev \
    make \
    php \
    unzip \
    wget

groupadd --system nagios
useradd --system --gid nagios --home-dir /usr/local/nagios --shell /usr/sbin/nologin nagios
usermod -a -G nagios www-data

cd /tmp
wget -q "https://assets.nagios.com/downloads/nagioscore/releases/nagios-${NAGIOS_VERSION}.tar.gz"
tar -xzf "nagios-${NAGIOS_VERSION}.tar.gz"
cd "nagios-${NAGIOS_VERSION}"

./configure --with-httpd-conf=/etc/apache2/sites-enabled
make -j"$(nproc)" all
make install
make install-commandmode
make install-config
make install-webconf

a2enmod cgi

# The default sample localhost monitoring is not part of this image.
sed -i '\|^cfg_file=/usr/local/nagios/etc/objects/localhost.cfg$|d' /usr/local/nagios/etc/nagios.cfg

# Custom monitoring objects are delivered from the repository and copied
# into the image by the Dockerfile.
mkdir -p /usr/local/nagios/etc/conf.d
printf '\n# Immutable repository-managed object configuration\ncfg_dir=/usr/local/nagios/etc/conf.d\n' \
    >> /usr/local/nagios/etc/nagios.cfg

# Do not let Nagios Core perform its own update checks.
sed -i 's/^check_for_updates=.*/check_for_updates=0/' /usr/local/nagios/etc/nagios.cfg

# Notifications are deliberately disabled until a real notification transport
# (SMTP, webhook, etc.) is configured.
sed -i 's/^enable_notifications=.*/enable_notifications=0/' /usr/local/nagios/etc/nagios.cfg

# Keep the Basic-Auth password out of the image. The entrypoint creates this
# file in /run (tmpfs) on every container start.
sed -i 's#AuthUserFile .*htpasswd.users#AuthUserFile /run/nagios/htpasswd.users#g' \
    /etc/apache2/sites-enabled/nagios.conf

# Avoid Apache's ServerName warning.
printf '\nServerName localhost\n' >> /etc/apache2/apache2.conf

rm -rf "/tmp/nagios-${NAGIOS_VERSION}" "/tmp/nagios-${NAGIOS_VERSION}.tar.gz"
