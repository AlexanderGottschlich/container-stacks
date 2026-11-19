#!/usr/bin/env bash
# One-time installation / explicit reconfiguration by an administrator.
# NEVER invoke this script through the deploy user's sudoers allowance.
set -euo pipefail
umask 077
[[ "$(id -u)" -eq 0 ]] || { echo 'Run manually as root' >&2; exit 1; }
SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DEST=/opt/container-stacks-secure
[[ -f "$SRC/nagios/docker-compose.yml" ]] || exit 1
[[ -f "$SRC/nagios/.env" ]] || { echo "Missing $SRC/nagios/.env" >&2; exit 1; }
[[ -f "$SRC/scripts/secure/start-nagios-ghcr.sh" ]] || exit 1
[[ -f "$SRC/scripts/secure/deploy-nagios-root.sh" ]] || exit 1

install -d -o root -g root -m 0700 "$DEST" "$DEST/nagios" "$DEST/bin"
install -o root -g root -m 0600 "$SRC/nagios/docker-compose.yml" "$DEST/nagios/docker-compose.yml"
# Copy secrets only on first install. Re-synchronization must be deliberate.
if [[ ! -e "$DEST/nagios/.env" ]]; then
  install -o root -g root -m 0600 "$SRC/nagios/.env" "$DEST/nagios/.env"
  echo 'Protected .env created; future changes require manual synchronization.'
else
  echo 'Protected .env retained (not overwritten).'
fi
install -o root -g root -m 0700 "$SRC/scripts/secure/start-nagios-ghcr.sh" "$DEST/bin/start-nagios-ghcr"
install -o root -g root -m 0700 "$SRC/scripts/secure/deploy-nagios-root.sh" "$DEST/bin/deploy-nagios"
touch "$DEST/nagios-deploy.lock"
chown root:root "$DEST/nagios-deploy.lock"
chmod 0600 "$DEST/nagios-deploy.lock"

# Narrow command authorization. Root-owned target and config are essential.
cat > /etc/sudoers.d/container-stacks-nagios <<'SUDOERS'
Defaults:deploy env_reset
Defaults:deploy secure_path="/usr/sbin:/usr/bin:/sbin:/bin"
deploy ALL=(root) NOPASSWD: /opt/container-stacks-secure/bin/deploy-nagios *
SUDOERS
chown root:root /etc/sudoers.d/container-stacks-nagios
chmod 0440 /etc/sudoers.d/container-stacks-nagios
visudo -cf /etc/sudoers.d/container-stacks-nagios

echo 'Installed root-protected Nagios deployment under /opt/container-stacks-secure.'
echo 'Never grant deploy write access to this directory or /etc/sudoers.d.'
