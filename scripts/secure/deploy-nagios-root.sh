#!/usr/bin/env bash
# Root-owned execution only. Installed to /opt/container-stacks-secure/bin/deploy-nagios.
set -euo pipefail
umask 077

SECURE_ROOT=/opt/container-stacks-secure
CONFIG_DIR="$SECURE_ROOT/nagios"
SECURE_COMPOSE="$CONFIG_DIR/docker-compose.yml"
LOCK="$SECURE_ROOT/nagios-deploy.lock"

usage() {
  echo "Usage: deploy-nagios [--check] ghcr.io/alexandergottschlich/container-stacks-nagios:sha-<40-hex>" >&2
  exit 2
}

[[ "$(id -u)" -eq 0 ]] || { echo 'Must be run as root through approved sudoers entry' >&2; exit 1; }
[[ $# -ge 1 && $# -le 2 ]] || usage
MODE=deploy
if [[ "${1:-}" == '--check' ]]; then
  MODE=check
  shift
fi
[[ $# -eq 1 ]] || usage
IMAGE="$1"
[[ "$IMAGE" =~ ^ghcr\.io/alexandergottschlich/container-stacks-nagios:sha-[a-f0-9]{40}$ ]] || usage

# Do not trust deploy-controlled environment variables.
unset DOCKER_HOST DOCKER_CONTEXT DOCKER_CONFIG COMPOSE_FILE COMPOSE_PROJECT_NAME COMPOSE_HTTP_TIMEOUT
unset NAGIOS_TEST_PUBLIC_IP NAGIOS_TEST_HOST TRAEFIK_CONTAINER NAGIOS_EGRESS_SUBNET NAGIOS_EGRESS_GATEWAY
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
export NAGIOS_IMAGE="$IMAGE"

[[ -f "$SECURE_COMPOSE" && -f "$CONFIG_DIR/.env" && -x "$SECURE_ROOT/bin/start-nagios-ghcr" ]] || {
  echo 'Protected Nagios deployment files missing. Install first.' >&2; exit 1;
}
for file in "$SECURE_COMPOSE" "$CONFIG_DIR/.env" "$SECURE_ROOT/bin/start-nagios-ghcr"; do
  [[ "$(stat -c %u "$file")" == 0 ]] || { echo "Unsafe owner: $file" >&2; exit 1; }
done

exec 9>"$LOCK"
flock -n 9 || { echo 'Another Nagios deployment is already running' >&2; exit 1; }
cd "$CONFIG_DIR"

docker-compose -p nagios -f "$SECURE_COMPOSE" config --quiet
[[ "$(docker inspect nagios --format '{{index .Config.Labels "com.docker.compose.project"}}/{{index .Config.Labels "com.docker.compose.service"}}' 2>/dev/null)" == 'nagios/nagios' ]] || {
  echo 'Existing container is not the expected Compose project/service' >&2; exit 1;
}
docker volume inspect nagios_nagios_var >/dev/null
for n in nagios_egress proxy_net; do docker network inspect "$n" >/dev/null; done

if [[ "$MODE" == check ]]; then
  echo 'CHECK OK: protected Compose config, existing Nagios project, volume, networks and image reference.'
  echo 'No images pulled and no containers changed.'
  exit 0
fi

OLD_ID="$(docker inspect nagios --format '{{.Image}}')"
[[ "$OLD_ID" =~ ^sha256:[a-f0-9]{64}$ ]] || { echo 'Cannot determine old image ID'; exit 1; }
# Local rollback tag preserves the previous image even if its original tag is later reused.
docker image tag "$OLD_ID" nagios-rollback:previous

echo "Pulling approved image: $IMAGE"
docker pull "$IMAGE"
if "$SECURE_ROOT/bin/start-nagios-ghcr"; then
  echo "DEPLOY OK: $IMAGE"
else
  echo 'Deployment or checks failed; attempting rollback to previous local image' >&2
  export NAGIOS_IMAGE=nagios-rollback:previous
  if "$SECURE_ROOT/bin/start-nagios-ghcr"; then
    echo 'Rollback completed. Investigate original deployment failure.' >&2
  else
    echo 'ROLLBACK FAILED. Manual intervention required.' >&2
  fi
  exit 1
fi
