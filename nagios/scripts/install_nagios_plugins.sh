#!/usr/bin/env bash
set -euo pipefail

: "${NAGIOS_PLUGINS_VERSION:=2.5}"

# check_dns relies on nslookup; check_dig relies on dig. Both are provided by
# dnsutils and must exist before ./configure so the plugins are built.
for dependency in nslookup dig; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        echo "ERROR: required DNS utility '$dependency' is missing before Nagios Plugins build" >&2
        exit 1
    fi
done

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

# Some build/install combinations can leave an otherwise successfully built
# plugin out of libexec. Our repository uses check_http and check_dns directly,
# so make their presence an immutable image invariant. If a plugin was built
# but not installed, install it explicitly from the build tree.
for plugin in check_http check_dns check_dig; do
    target="/usr/local/nagios/libexec/${plugin}"

    if [[ ! -x "$target" && -x "plugins/${plugin}" ]]; then
        echo "Installing ${plugin} explicitly into /usr/local/nagios/libexec"
        install -o nagios -g nagios -m 0755 "plugins/${plugin}" "$target"
    fi

    if [[ ! -x "$target" ]]; then
        echo "ERROR: required Nagios plugin '${plugin}' was not built/installed" >&2
        echo "Available DNS-related build artifacts:" >&2
        find plugins -maxdepth 1 -type f -name 'check_*' -printf '%f\n' | sort >&2 || true
        exit 1
    fi
done

# Fail the image build immediately if the plugins cannot even start.
/usr/local/nagios/libexec/check_http --version >/dev/null
/usr/local/nagios/libexec/check_dns --version >/dev/null
/usr/local/nagios/libexec/check_dig --version >/dev/null

rm -rf "/tmp/nagios-plugins-${NAGIOS_PLUGINS_VERSION}" \
       "/tmp/nagios-plugins-${NAGIOS_PLUGINS_VERSION}.tar.gz"
