#!/usr/bin/env bash
# Administrator-only. Run from a trusted checkout on Naboo.
set -euo pipefail
umask 077
[[ "$(id -u)" == 0 ]] || { echo 'Run via sudo as administrator' >&2; exit 1; }
SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BASE=/opt/container-stacks-secure
CFG="$BASE/pihole"
[[ -f "$SRC/pihole/docker-compose.yml" && -f "$SRC/pihole/.env" ]] || { echo 'Source compose/.env missing' >&2; exit 1; }
[[ -f "$SRC/pihole/dnsmasq/02-unbound.conf" && -f "$SRC/pihole/unbound/unbound.conf" ]] || { echo 'Source bind-mounted config missing' >&2; exit 1; }
[[ -f "$SRC/scripts/secure/deploy-pihole-root.sh" ]] || exit 1
# Refuse any unexpected source image or number of matching image lines.
count="$(grep -Ec '^    image: pihole/pihole:[^[:space:]]+[[:space:]]*$' "$SRC/pihole/docker-compose.yml" || true)"
[[ "$count" == 1 ]] || { echo 'Expected exactly one Pi-hole image line' >&2; exit 1; }
install -d -o root -g root -m 0700 "$BASE" "$BASE/bin" "$CFG" "$CFG/dnsmasq" "$CFG/unbound"
# Replace only the image reference, retaining all other Compose settings.
sed -E 's|^    image: pihole/pihole:[^[:space:]]+[[:space:]]*$|    image: ${PIHOLE_IMAGE}|' "$SRC/pihole/docker-compose.yml" > "$CFG/docker-compose.yml"
chown root:root "$CFG/docker-compose.yml"; chmod 0600 "$CFG/docker-compose.yml"
if [[ ! -e "$CFG/.env" ]]; then
  install -o root -g root -m 0600 "$SRC/pihole/.env" "$CFG/.env"
  echo 'Protected .env copied (future synchronization is manual).'
else
  echo 'Protected .env retained (not overwritten).'
fi
install -o root -g root -m 0600 "$SRC/pihole/dnsmasq/02-unbound.conf" "$CFG/dnsmasq/02-unbound.conf"
install -o root -g root -m 0600 "$SRC/pihole/unbound/unbound.conf" "$CFG/unbound/unbound.conf"
install -o root -g root -m 0700 "$SRC/scripts/secure/deploy-pihole-root.sh" "$BASE/bin/deploy-pihole"
touch "$BASE/pihole-deploy.lock"
chown root:root "$BASE/pihole-deploy.lock"; chmod 0600 "$BASE/pihole-deploy.lock"
cat > /etc/sudoers.d/container-stacks-pihole <<'SUDOERS'
Defaults:deploy env_reset
Defaults:deploy secure_path="/usr/sbin:/usr/bin:/sbin:/bin"
deploy ALL=(root) NOPASSWD: /opt/container-stacks-secure/bin/deploy-pihole *
SUDOERS
chown root:root /etc/sudoers.d/container-stacks-pihole
chmod 0440 /etc/sudoers.d/container-stacks-pihole
visudo -cf /etc/sudoers.d/container-stacks-pihole
printf 'Installed protected Pi-hole deployment; Compose SHA256: '
sha256sum "$CFG/docker-compose.yml" | awk '{print $1}'
