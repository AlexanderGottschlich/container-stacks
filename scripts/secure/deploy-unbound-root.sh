#!/usr/bin/env bash
# Installed root-owned as /opt/container-stacks-secure/bin/deploy-unbound.
# The deploy user has sudo rights ONLY for this specific root-owned wrapper.
set -euo pipefail
umask 077

usage() {
  echo 'Usage: deploy-unbound --check|--execute IMAGE NORMALIZED_COMPOSE_SHA UNBOUND_CONF_SHA' >&2
  exit 2
}

[[ $(id -u) -eq 0 && $# -eq 4 ]] || usage
MODE=$1
IMAGE=$2
EXPECTED_COMPOSE_SHA=$3
EXPECTED_CONF_SHA=$4
[[ $MODE == --check || $MODE == --execute ]] || usage
[[ $IMAGE =~ ^klutchell/unbound:[a-zA-Z0-9._-]+@sha256:[a-f0-9]{64}$ ]] || { echo 'Invalid digest-pinned Unbound image' >&2; exit 2; }
[[ $EXPECTED_COMPOSE_SHA =~ ^[a-f0-9]{64}$ && $EXPECTED_CONF_SHA =~ ^[a-f0-9]{64}$ ]] || { echo 'Invalid SHA256 input' >&2; exit 2; }

BASE=/opt/container-stacks-secure
CFG=$BASE/unbound
COMPOSE=$CFG/docker-compose.yml
UNBOUND_CONF=$CFG/unbound/unbound.conf
LOCK=$BASE/pihole-deploy.lock

# Never honor environment variables supplied by the SSH/sudo caller.
unset DOCKER_HOST DOCKER_CONTEXT DOCKER_CONFIG COMPOSE_FILE COMPOSE_PROJECT_NAME COMPOSE_HTTP_TIMEOUT
export PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root

for path in "$BASE" "$CFG" "$CFG/unbound" "$CFG/dnsmasq"; do
  [[ -d $path && ! -L $path && $(stat -c %u "$path") -eq 0 && $(stat -c %a "$path") == 700 ]] || {
    echo "Unsafe protected directory: $path" >&2; exit 1;
  }
done
for path in "$COMPOSE" "$CFG/.env" "$UNBOUND_CONF" "$CFG/dnsmasq/02-unbound.conf" "$LOCK"; do
  [[ -f $path && ! -L $path && $(stat -c %u "$path") -eq 0 ]] || {
    echo "Missing or unsafe protected file: $path" >&2; exit 1;
  }
done

# Lock before validating, pulling or touching any container.
exec 9>"$LOCK"
flock -n 9 || { echo 'Another Pi-hole/Unbound deployment is running' >&2; exit 1; }

actual_compose_sha=$(sha256sum "$COMPOSE" | awk '{print $1}')
actual_conf_sha=$(sha256sum "$UNBOUND_CONF" | awk '{print $1}')
[[ $actual_compose_sha == "$EXPECTED_COMPOSE_SHA" ]] || {
  echo 'Protected Compose does not match the approved Git revision' >&2; exit 1;
}
[[ $actual_conf_sha == "$EXPECTED_CONF_SHA" ]] || {
  echo 'Protected unbound.conf does not match the approved Git revision' >&2; exit 1;
}

PIHOLE_IMAGE=$(docker inspect pihole --format '{{.Config.Image}}')
[[ $PIHOLE_IMAGE =~ ^pihole/pihole:[a-zA-Z0-9._-]+@sha256:[a-f0-9]{64}$ ]] || {
  echo 'Running Pi-hole image is not digest-pinned' >&2; exit 1;
}
export PIHOLE_IMAGE UNBOUND_IMAGE="$IMAGE"
cd "$CFG"
docker-compose -p pihole -f "$COMPOSE" config --quiet

for pair in pihole:pihole unbound:unbound; do
  name=${pair%%:*}
  service=${pair##*:}
  label=$(docker inspect "$name" --format '{{index .Config.Labels "com.docker.compose.project"}}/{{index .Config.Labels "com.docker.compose.service"}}' 2>/dev/null || true)
  [[ $label == "pihole/$service" ]] || { echo "Unexpected Compose identity: $name ($label)" >&2; exit 1; }
done
docker network inspect proxy_net >/dev/null
for volume in pihole_pihole_etc pihole_pihole_dnsmasq; do
  docker volume inspect "$volume" >/dev/null
done
command -v dig >/dev/null || { echo 'dig is required for DNS healthchecks' >&2; exit 1; }

unbound_ip() {
  docker inspect unbound --format '{{with index .NetworkSettings.Networks "proxy_net"}}{{.IPAddress}}{{end}}'
}

# dig can exit successfully on SERVFAIL; never rely on +short alone.
valid_a_reply() {
  local response=$1
  [[ $response == *'status: NOERROR'* ]] || return 1
  grep -Eq '^;; flags: .*([[:space:]])ad([;[:space:]])' <<<"$response" || return 1
  awk '$1 !~ /^;/ && $4 == "A" && $5 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {found=1} END {exit !found}' <<<"$response"
}

probe_unbound() {
  local ip=$1 response
  response=$(dig "@$ip" -p 5335 cloudflare.com A +dnssec +time=3 +tries=1) || return 1
  valid_a_reply "$response" || return 1

  response=$(dig "@$ip" -p 5335 dnssec-failed.org A +time=3 +tries=1) || return 1
  [[ $response == *'status: SERVFAIL'* ]] || return 1
}

probe_pihole() {
  local response probe
  # A unique name avoids a misleading positive result from Pi-hole's stale cache.
  probe="health-$(cat /proc/sys/kernel/random/uuid).example.org"
  response=$(dig @192.168.6.1 "$probe" A +time=3 +tries=1) || return 1
  [[ $response == *'status: NXDOMAIN'* ]] || return 1
  [[ $response != *'EDE: 3 (Stale Answer)'* ]] || return 1
}

healthcheck() {
  local expected_image=$1 ip actual_image actual_id
  [[ $(docker inspect unbound --format '{{.State.Running}}') == true ]] || return 1
  actual_image=$(docker inspect unbound --format '{{.Config.Image}}')
  [[ $actual_image == "$expected_image" ]] || return 1
  actual_id=$(docker inspect unbound --format '{{.Image}}')
  [[ $actual_id == "$EXPECTED_IMAGE_ID" ]] || return 1
  ip=$(unbound_ip)
  [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  probe_unbound "$ip" && probe_pihole
}

retry_healthcheck() {
  local image=$1 attempt
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if healthcheck "$image"; then
      echo "DNS and DNSSEC healthcheck OK (attempt $attempt)"
      return 0
    fi
    sleep 2
  done
  return 1
}

# The currently mounted configuration must match the reviewed, protected copy.
# This also catches differences between the original Compose mount and secure mount.
RUNNING_CONF=$(docker inspect unbound --format '{{range .Mounts}}{{if eq .Destination "/etc/unbound/unbound.conf"}}{{.Source}}{{end}}{{end}}')
[[ -n $RUNNING_CONF && -f $RUNNING_CONF && ! -L $RUNNING_CONF ]] || {
  echo 'Unable to verify the running Unbound configuration bind mount' >&2; exit 1;
}
[[ $(sha256sum "$RUNNING_CONF" | awk '{print $1}') == "$EXPECTED_CONF_SHA" ]] || {
  echo 'Running Unbound configuration differs from the approved configuration' >&2; exit 1;
}

OLD_ID=$(docker inspect unbound --format '{{.Image}}')
[[ $OLD_ID =~ ^sha256:[a-f0-9]{64}$ ]] || { echo 'Invalid current image ID' >&2; exit 1; }
EXPECTED_IMAGE_ID=$OLD_ID
BASELINE_IMAGE=$(docker inspect unbound --format '{{.Config.Image}}')
if ! retry_healthcheck "$BASELINE_IMAGE"; then
  echo 'Baseline DNS/DNSSEC checks failed; refusing deployment' >&2
  exit 1
fi

if [[ $MODE == --check ]]; then
  echo "CHECK OK: Compose SHA=$EXPECTED_COMPOSE_SHA; Unbound config SHA=$EXPECTED_CONF_SHA; baseline DNS/DNSSEC verified; no changes made"
  exit 0
fi

# Capture the known-good image/configuration BEFORE deployment.
BACKUP=$(mktemp -d "$BASE/.unbound-rollback.XXXXXXXX")
ROLLBACK_NEEDED=0
KEEP_BACKUP=0
cleanup() {
  local result=$?
  trap - EXIT
  if [[ $ROLLBACK_NEEDED == 1 ]]; then
    echo 'Deployment aborted; attempting emergency rollback' >&2
    if rollback; then
      echo 'Emergency rollback OK' >&2
    else
      echo 'Emergency rollback FAILED: manual recovery required' >&2
      KEEP_BACKUP=1
    fi
  fi
  if [[ $KEEP_BACKUP == 1 ]]; then
    echo "Recovery files retained in protected directory: $BACKUP" >&2
  else
    rm -rf -- "$BACKUP"
  fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cp -a -- "$COMPOSE" "$BACKUP/docker-compose.yml"
cp -a -- "$UNBOUND_CONF" "$BACKUP/unbound.conf"
cp -a -- "$CFG/.env" "$BACKUP/.env"
cp -a -- "$CFG/dnsmasq/02-unbound.conf" "$BACKUP/02-unbound.conf"
docker image tag "$OLD_ID" unbound-rollback:previous

restore_config() {
  install -o root -g root -m 0600 "$BACKUP/unbound.conf" "$UNBOUND_CONF"
  install -o root -g root -m 0600 "$BACKUP/docker-compose.yml" "$COMPOSE"
  install -o root -g root -m 0600 "$BACKUP/.env" "$CFG/.env"
  install -o root -g root -m 0600 "$BACKUP/02-unbound.conf" "$CFG/dnsmasq/02-unbound.conf"
}

start_service() {
  docker-compose -p pihole -f "$COMPOSE" up -d --no-deps --no-build --force-recreate unbound
}

rollback() {
  echo 'Restoring known-good Unbound image and protected configuration' >&2
  restore_config || return 1
  export UNBOUND_IMAGE=unbound-rollback:previous
  EXPECTED_IMAGE_ID=$OLD_ID
  docker-compose -p pihole -f "$COMPOSE" config --quiet || return 1
  start_service && retry_healthcheck "$UNBOUND_IMAGE"
}

# Never pull/recreate if the candidate config fails validation against its image.
echo "Pulling approved image: $IMAGE"
docker pull "$IMAGE"
TARGET_ID=$(docker image inspect "$IMAGE" --format '{{.Id}}')
[[ $TARGET_ID =~ ^sha256:[a-f0-9]{64}$ ]] || { echo 'Invalid downloaded image ID' >&2; exit 1; }
if ! docker run --rm --network none --cap-drop ALL --security-opt no-new-privileges \
  --entrypoint /usr/sbin/unbound-checkconf \
  -v "$UNBOUND_CONF:/etc/unbound/unbound.conf:ro" \
  "$IMAGE" /etc/unbound/unbound.conf; then
  echo 'Target image rejected by unbound-checkconf; no service change made' >&2
  exit 1
fi

if [[ $TARGET_ID == "$OLD_ID" ]]; then
  echo 'Target image has the same image ID as the healthy running container; no recreate needed'
  exit 0
fi

EXPECTED_IMAGE_ID=$TARGET_ID
ROLLBACK_NEEDED=1
if start_service && retry_healthcheck "$UNBOUND_IMAGE"; then
  ROLLBACK_NEEDED=0
  echo "DEPLOY OK: $IMAGE"
  exit 0
fi

echo 'Deployment healthcheck failed; attempting rollback' >&2
if rollback; then
  ROLLBACK_NEEDED=0
  echo 'ROLLBACK OK: previous image, configuration, and DNS/DNSSEC health restored' >&2
else
  ROLLBACK_NEEDED=0
  KEEP_BACKUP=1
  echo 'ROLLBACK FAILED: manual intervention required' >&2
fi
exit 1
