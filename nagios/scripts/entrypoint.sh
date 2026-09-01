#!/usr/bin/env bash
set -euo pipefail

NAGIOS_CFG=/usr/local/nagios/etc/nagios.cfg
HTPASSWD_FILE=/run/nagios/htpasswd.users

if [[ -z "${NAGIOSADMIN_PASSWORD:-}" ]]; then
    echo >&2 "ERROR: NAGIOSADMIN_PASSWORD is not set"
    exit 1
fi

umask 077
mkdir -p /run/nagios /run/apache2 /run/lock/apache2
htpasswd -bc "$HTPASSWD_FILE" nagiosadmin "$NAGIOSADMIN_PASSWORD" >/dev/null
chown root:www-data "$HTPASSWD_FILE"
chmod 0640 "$HTPASSWD_FILE"
unset NAGIOSADMIN_PASSWORD

# Refuse to start with an invalid repository-baked Nagios configuration.
/usr/local/nagios/bin/nagios -v "$NAGIOS_CFG"

/usr/local/nagios/bin/nagios "$NAGIOS_CFG" &
NAGIOS_PID=$!

/usr/sbin/apache2ctl -DFOREGROUND &
APACHE_PID=$!

shutdown() {
    trap - TERM INT
    kill -TERM "$NAGIOS_PID" "$APACHE_PID" 2>/dev/null || true
    wait "$NAGIOS_PID" "$APACHE_PID" 2>/dev/null || true
}

trap shutdown TERM INT

# Exit if either daemon dies; the container restart policy can then recover it.
set +e
wait -n "$NAGIOS_PID" "$APACHE_PID"
STATUS=$?
set -e

shutdown
exit "$STATUS"
