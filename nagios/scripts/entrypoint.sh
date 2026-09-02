#!/usr/bin/env bash
set -euo pipefail

NAGIOS_CFG=/usr/local/nagios/etc/nagios.cfg
HTPASSWD_DIR=/run/nagios
HTPASSWD_FILE=${HTPASSWD_DIR}/htpasswd.users

# Legacy-Docker workaround: make the dedicated egress bridge the default route.
/usr/local/bin/configure_egress_route.sh

if [[ -z "${NAGIOSADMIN_PASSWORD:-}" ]]; then
    echo >&2 "ERROR: NAGIOSADMIN_PASSWORD is not set"
    exit 1
fi

# /run is tmpfs. Force the exact permissions on every container start.
# Do not rely on mkdir/install semantics if the directory already exists.
mkdir -p "${HTPASSWD_DIR}" /run/apache2 /run/lock/apache2
chown root:www-data "${HTPASSWD_DIR}"
chmod 0750 "${HTPASSWD_DIR}"
chown root:root /run/apache2 /run/lock/apache2
chmod 0755 /run/apache2 /run/lock/apache2

umask 077
htpasswd -bc "${HTPASSWD_FILE}" nagiosadmin "${NAGIOSADMIN_PASSWORD}" >/dev/null
chown root:www-data "${HTPASSWD_FILE}"
chmod 0640 "${HTPASSWD_FILE}"
unset NAGIOSADMIN_PASSWORD

# Fail fast if Apache's runtime user cannot traverse/read the auth file.
if ! su -s /bin/sh www-data -c "test -r '${HTPASSWD_FILE}'"; then
    echo >&2 "ERROR: Apache user www-data cannot read ${HTPASSWD_FILE}"
    namei -l "${HTPASSWD_FILE}" >&2 || true
    exit 1
fi

# Refuse to start with an invalid repository-baked Nagios configuration.
/usr/local/nagios/bin/nagios -v "${NAGIOS_CFG}"

/usr/local/nagios/bin/nagios "${NAGIOS_CFG}" &
NAGIOS_PID=$!

/usr/sbin/apache2ctl -DFOREGROUND &
APACHE_PID=$!

shutdown() {
    trap - TERM INT
    kill -TERM "${NAGIOS_PID}" "${APACHE_PID}" 2>/dev/null || true
    wait "${NAGIOS_PID}" "${APACHE_PID}" 2>/dev/null || true
}

trap shutdown TERM INT

# Exit if either daemon dies; the container restart policy can then recover it.
set +e
wait -n "${NAGIOS_PID}" "${APACHE_PID}"
STATUS=$?
set -e

shutdown
exit "${STATUS}"
