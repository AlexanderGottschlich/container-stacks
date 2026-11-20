#!/usr/bin/env bash
# Root-owned. No direct Docker access is granted to the 'deploy' user.
set -euo pipefail
umask 077
[[ $(id -u) -eq 0 && $# -eq 3 ]] || { echo 'Usage: deploy-unbound --check|--execute IMAGE NORMALIZED_COMPOSE_SHA' >&2; exit 2; }
MODE=$1 IMAGE=$2 EXPECTED_SHA=$3
[[ $MODE == --check || $MODE == --execute ]] || exit 2
[[ $IMAGE =~ ^klutchell/unbound:[a-zA-Z0-9._-]+@sha256:[a-f0-9]{64}$ ]] || { echo 'Invalid Unbound digest image' >&2; exit 2; }
[[ $EXPECTED_SHA =~ ^[a-f0-9]{64}$ ]] || { echo 'Invalid configuration hash' >&2; exit 2; }
BASE=/opt/container-stacks-secure
CFG=$BASE/unbound
COMPOSE=$CFG/docker-compose.yml
LOCK=$BASE/pihole-deploy.lock  # Share lock with the existing Pi-hole wrapper.
for path in "$BASE" "$CFG" "$CFG/unbound" "$CFG/dnsmasq"; do
  [[ -d $path && $(stat -c %u "$path") -eq 0 && $(stat -c %a "$path") == 700 ]] || { echo "Unsafe directory $path" >&2; exit 1; }
done
for path in "$COMPOSE" "$CFG/.env" "$CFG/unbound/unbound.conf" "$CFG/dnsmasq/02-unbound.conf" "$LOCK"; do
  [[ -f $path && ! -L $path && $(stat -c %u "$path") -eq 0 ]] || { echo "Missing/unsafe protected file $path" >&2; exit 1; }
done
unset DOCKER_HOST DOCKER_CONTEXT DOCKER_CONFIG COMPOSE_FILE COMPOSE_PROJECT_NAME COMPOSE_HTTP_TIMEOUT
export PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root
ACTUAL_SHA=$(sha256sum "$COMPOSE" | awk '{print $1}')
[[ $ACTUAL_SHA == "$EXPECTED_SHA" ]] || { echo 'Protected Compose differs from approved configuration; administrator must reinstall' >&2; exit 1; }
# Use the actual currently running Pi-hole image as a non-target service reference.
PIHOLE_IMAGE=$(docker inspect pihole --format '{{.Config.Image}}')
[[ $PIHOLE_IMAGE =~ ^pihole/pihole:[a-zA-Z0-9._-]+@sha256:[a-f0-9]{64}$ ]] || { echo 'Pi-hole is not running a digest-pinned image' >&2; exit 1; }
export PIHOLE_IMAGE UNBOUND_IMAGE="$IMAGE"
exec 9>"$LOCK"
flock -n 9 || { echo 'Pi-hole or Unbound deployment already running' >&2; exit 1; }
cd "$CFG"
docker-compose -p pihole -f "$COMPOSE" config --quiet
for pair in pihole:pihole unbound:unbound; do
  name=${pair%%:*}; service=${pair##*:}
  label=$(docker inspect "$name" --format '{{index .Config.Labels "com.docker.compose.project"}}/{{index .Config.Labels "com.docker.compose.service"}}' 2>/dev/null || true)
  [[ $label == "pihole/$service" ]] || { echo "Incorrect Compose identity for $name: $label" >&2; exit 1; }
done
docker network inspect proxy_net >/dev/null
for volume in pihole_pihole_etc pihole_pihole_dnsmasq; do docker volume inspect "$volume" >/dev/null; done
if [[ $MODE == --check ]]; then
  echo "CHECK OK: approved Unbound image=$IMAGE; protected config, running Pi-hole, network and volumes verified; no changes made"
  exit 0
fi
OLD_ID=$(docker inspect unbound --format '{{.Image}}')
[[ $OLD_ID =~ ^sha256:[a-f0-9]{64}$ ]] || exit 1
docker image tag "$OLD_ID" unbound-rollback:previous
start_service() {
  docker-compose -p pihole -f "$COMPOSE" up -d --no-deps --no-build --force-recreate unbound
}
verify() {
  [[ $(docker inspect unbound --format '{{.State.Running}}') == true ]] || return 1
  [[ $(docker inspect unbound --format '{{.Config.Image}}') == "$UNBOUND_IMAGE" ]] || return 1
  local ip result count
  ip=$(docker inspect unbound --format '{{with index .NetworkSettings.Networks "proxy_net"}}{{.IPAddress}}{{end}}')
  [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  for count in 1 2 3 4 5 6 7 8; do
    result=$(dig "@$ip" -p 5335 example.org A +time=2 +tries=1 +short 2>/dev/null || true)
    if [[ -n $result ]]; then
      echo "Direct Unbound DNS OK: $result"
      result=$(dig @192.168.6.1 example.org A +time=2 +tries=1 +short 2>/dev/null || true)
      [[ -n $result ]] || { echo 'Pi-hole DNS check failed' >&2; return 1; }
      echo "Pi-hole DNS OK: $result"
      return 0
    fi
    sleep 2
  done
  echo 'Unbound DNS check failed' >&2
  return 1
}
command -v dig >/dev/null || { echo 'dig is required' >&2; exit 1; }
echo "Pulling approved image: $IMAGE"
docker pull "$IMAGE"
if start_service && verify; then
  echo "DEPLOY OK: $IMAGE"
else
  echo 'Unbound deployment failed; attempting image rollback' >&2
  export UNBOUND_IMAGE=unbound-rollback:previous
  if start_service && verify; then
    echo 'ROLLBACK OK: previous Unbound image restored and DNS checked' >&2
  else
    echo 'ROLLBACK FAILED: manual intervention required' >&2
  fi
  exit 1
fi
