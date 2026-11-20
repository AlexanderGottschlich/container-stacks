#!/usr/bin/env bash
# Existing Pi-hole deployment with a stable hash across independent Unbound image updates.
set -euo pipefail
umask 077
[[ $(id -u) -eq 0 && $# -eq 3 ]] || { echo 'Usage: deploy-pihole --check|--execute IMAGE CONFIG_SHA256' >&2; exit 2; }
MODE=$1 IMAGE=$2 CONFIG_SHA=$3
[[ $MODE == --check || $MODE == --execute ]] || exit 2
[[ $IMAGE =~ ^pihole/pihole:[a-zA-Z0-9._-]+@sha256:[a-f0-9]{64}$ ]] || { echo 'Invalid Pi-hole digest image' >&2; exit 2; }
[[ $CONFIG_SHA =~ ^[a-f0-9]{64}$ ]] || { echo 'Invalid configuration hash' >&2; exit 2; }
BASE=/opt/container-stacks-secure
CFG=$BASE/pihole
COMPOSE=$CFG/docker-compose.yml
LOCK=$BASE/pihole-deploy.lock
for f in "$COMPOSE" "$CFG/.env" "$CFG/dnsmasq/02-unbound.conf" "$CFG/unbound/unbound.conf"; do
  [[ -f $f && ! -L $f && $(stat -c %u "$f") -eq 0 ]] || { echo "Missing/unsafe protected file: $f" >&2; exit 1; }
done
[[ $(stat -c %u "$BASE") -eq 0 && $(stat -c %u "$CFG") -eq 0 ]] || exit 1
unset DOCKER_HOST DOCKER_CONTEXT DOCKER_CONFIG COMPOSE_FILE COMPOSE_PROJECT_NAME COMPOSE_HTTP_TIMEOUT
export PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root
# Protected Pi-hole Compose currently contains ${PIHOLE_IMAGE}; normalize the
# independent Unbound image too, without changing the installed file.
ACTUAL_SHA=$(sed -E 's|^    image: klutchell/unbound:[^[:space:]]+[[:space:]]*$|    image: ${UNBOUND_IMAGE}|' "$COMPOSE" | sha256sum | awk '{print $1}')
[[ $ACTUAL_SHA == "$CONFIG_SHA" ]] || { echo 'Protected Compose differs from approved configuration' >&2; exit 1; }
export PIHOLE_IMAGE="$IMAGE"
exec 9>"$LOCK"
flock -n 9 || { echo 'Another Pi-hole/Unbound deployment is running' >&2; exit 1; }
cd "$CFG"
docker-compose -p pihole -f "$COMPOSE" config --quiet
for pair in pihole:pihole unbound:unbound; do
  name=${pair%%:*}; service=${pair##*:}
  label=$(docker inspect "$name" --format '{{index .Config.Labels "com.docker.compose.project"}}/{{index .Config.Labels "com.docker.compose.service"}}' 2>/dev/null || true)
  [[ $label == "pihole/$service" ]] || { echo "Unexpected Compose identity for $name: $label" >&2; exit 1; }
done
docker network inspect proxy_net >/dev/null
for v in pihole_pihole_etc pihole_pihole_dnsmasq; do docker volume inspect "$v" >/dev/null; done
if [[ $MODE == --check ]]; then
  echo "CHECK OK: image=$IMAGE; protected configuration, Compose project, network and volumes validated; no changes made"
  exit 0
fi
OLD_ID=$(docker inspect pihole --format '{{.Image}}')
[[ $OLD_ID =~ ^sha256:[a-f0-9]{64}$ ]] || exit 1
docker image tag "$OLD_ID" pihole-rollback:previous
verify() {
  [[ $(docker inspect pihole --format '{{.State.Running}}') == true ]] || return 1
  [[ $(docker inspect pihole --format '{{.Config.Image}}') == "$PIHOLE_IMAGE" ]] || return 1
  for v in pihole_pihole_etc pihole_pihole_dnsmasq; do
    docker inspect pihole --format '{{range .Mounts}}{{println .Name}}{{end}}' | grep -qx "$v" || return 1
  done
  command -v dig >/dev/null || return 1
  local result
  result=$(dig @192.168.6.1 example.org A +time=3 +tries=2 +short 2>/dev/null || true)
  [[ -n $result ]] || { echo 'DNS test failed' >&2; return 1; }
  echo "DNS test OK: $result"
}
start_service() {
  docker-compose -p pihole -f "$COMPOSE" up -d --no-deps --no-build --force-recreate pihole
}
echo "Pulling approved image: $IMAGE"
docker pull "$IMAGE"
if start_service && verify; then
  echo "DEPLOY OK: $IMAGE"
else
  echo 'Deployment/check failed; attempting rollback' >&2
  export PIHOLE_IMAGE=pihole-rollback:previous
  if start_service && verify; then
    echo 'Rollback completed and DNS verified' >&2
  else
    echo 'ROLLBACK FAILED; manual intervention required' >&2
  fi
  exit 1
fi
