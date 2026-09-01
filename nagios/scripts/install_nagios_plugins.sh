#!/usr/bin/env bash
set -euo pipefail

: "${NAGIOS_PLUGINS_VERSION:=2.5}"

cd /tmp
wget -q "https://github.com/nagios-plugins/nagios-plugins/releases/download/release-${NAGIOS_PLUGINS_VERSION}/nagios-plugins-${NAGIOS_PLUGINS_VERSION}.tar.gz"
tar -xzf "nagios-plugins-${NAGIOS_PLUGINS_VERSION}.tar.gz"
cd "nagios-plugins-${NAGIOS_PLUGINS_VERSION}"

./configure \
    --with-nagios-user=nagios \
    --with-nagios-group=nagios \
    --with-openssl=/usr \
    --prefix=/usr/local/nagios

make -j"$(nproc)"
make install

rm -rf "/tmp/nagios-plugins-${NAGIOS_PLUGINS_VERSION}" \
       "/tmp/nagios-plugins-${NAGIOS_PLUGINS_VERSION}.tar.gz"
