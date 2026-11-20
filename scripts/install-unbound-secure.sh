#!/usr/bin/env bash
# Run ONCE as administrator from a reviewed checkout on Naboo.
set -euo pipefail
umask 077
[[ $(id -u) -eq 0 ]] || { echo 'Run as administrator/root' >&2; exit 1; }
SRC=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BASE=/opt/container-stacks-secure
CFG=$BASE/unbound
SRC_COMPOSE=$SRC/pihole/docker-compose.yml
for f in "$SRC_COMPOSE" "$SRC/pihole/.env" "$SRC/pihole/dnsmasq/02-unbound.conf" "$SRC/pihole/unbound/unbound.conf" "$SRC/scripts/secure/deploy-unbound-root.sh"; do
  [[ -f $f && ! -L $f ]] || { echo "Missing source $f" >&2; exit 1; }
done
[[ $(grep -Ec '^    image: pihole/pihole:[^[:space:]]+[[:space:]]*$' "$SRC_COMPOSE") == 1 ]] || exit 1
[[ $(grep -Ec '^    image: klutchell/unbound:[^[:space:]]+[[:space:]]*$' "$SRC_COMPOSE") == 1 ]] || exit 1
install -d -o root -g root -m 0700 "$BASE" "$BASE/bin" "$CFG" "$CFG/dnsmasq" "$CFG/unbound"
# Normalize BOTH images so that future Renovate image-only PRs do not affect the reviewed Compose hash.
sed -E \
  -e 's|^    image: pihole/pihole:[^[:space:]]+[[:space:]]*$|    image: ${PIHOLE_IMAGE}|' \
  -e 's|^    image: klutchell/unbound:[^[:space:]]+[[:space:]]*$|    image: ${UNBOUND_IMAGE}|' \
  "$SRC_COMPOSE" > "$CFG/docker-compose.yml"
chown root:root "$CFG/docker-compose.yml"; chmod 0600 "$CFG/docker-compose.yml"
if [[ ! -e "$CFG/.env" ]]; then
  install -o root -g root -m 0600 "$SRC/pihole/.env" "$CFG/.env"
else
  echo 'Protected Unbound .env retained; synchronize manually if necessary'
fi
install -o root -g root -m 0600 "$SRC/pihole/dnsmasq/02-unbound.conf" "$CFG/dnsmasq/02-unbound.conf"
install -o root -g root -m 0600 "$SRC/pihole/unbound/unbound.conf" "$CFG/unbound/unbound.conf"
install -o root -g root -m 0700 "$SRC/scripts/secure/deploy-unbound-root.sh" "$BASE/bin/deploy-unbound"
[[ -f "$BASE/pihole-deploy.lock" && ! -L "$BASE/pihole-deploy.lock" ]] || { echo 'Shared Pi-hole deployment lock missing' >&2; exit 1; }
cat > /etc/sudoers.d/container-stacks-unbound <<'SUDOERS'
Defaults:deploy env_reset
Defaults:deploy secure_path="/usr/sbin:/usr/bin:/sbin:/bin"
deploy ALL=(root) NOPASSWD: /opt/container-stacks-secure/bin/deploy-unbound *
SUDOERS
chown root:root /etc/sudoers.d/container-stacks-unbound
chmod 0440 /etc/sudoers.d/container-stacks-unbound
visudo -cf /etc/sudoers.d/container-stacks-unbound
printf 'Installed protected Unbound deployment. Normalized Compose SHA256: '
sha256sum "$CFG/docker-compose.yml" | awk '{print $1}'
