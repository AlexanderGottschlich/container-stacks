#!/usr/bin/env bash
set -euo pipefail

CONTAINER="nagios"
PROXY_NETWORK="proxy_net"
EGRESS_NETWORK="nagios_egress"

dotenv_value() {
  local key="$1"
  [[ -f .env ]] || return 0
  awk -v key="${key}" '
    $0 ~ "^[[:space:]]*" key "=" {
      sub("^[[:space:]]*" key "=", "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      gsub(/^\"|\"$/, "")
      print
      exit
    }' .env
}

EGRESS_SUBNET="${NAGIOS_EGRESS_SUBNET:-$(dotenv_value NAGIOS_EGRESS_SUBNET)}"
EGRESS_GATEWAY="${NAGIOS_EGRESS_GATEWAY:-$(dotenv_value NAGIOS_EGRESS_GATEWAY)}"
EGRESS_SUBNET="${EGRESS_SUBNET:-172.30.250.0/24}"
EGRESS_GATEWAY="${EGRESS_GATEWAY:-172.30.250.1}"
PUBLIC_IP="${NAGIOS_TEST_PUBLIC_IP:-152.53.46.232}"
PUBLIC_HOST="${NAGIOS_TEST_HOST:-nc2.elastic2ls.com}"

compose() {
  docker-compose "$@"
}

network_attached() {
  docker inspect "${CONTAINER}" \
    --format '{{range $name, $cfg := .NetworkSettings.Networks}}{{println $name}}{{end}}' \
    | grep -qx "$1"
}

# Traefik owns this external network. Fail explicitly instead of silently
# creating an incompatible replacement.
if ! docker network inspect "${PROXY_NETWORK}" >/dev/null 2>&1; then
  echo >&2 "ERROR: required external network '${PROXY_NETWORK}' does not exist."
  exit 1
fi

# Create the dedicated egress bridge once with a stable gateway.
if ! docker network inspect "${EGRESS_NETWORK}" >/dev/null 2>&1; then
  docker network create \
    --driver bridge \
    --subnet "${EGRESS_SUBNET}" \
    --gateway "${EGRESS_GATEWAY}" \
    "${EGRESS_NETWORK}" >/dev/null
else
  ACTUAL_SUBNET="$(docker network inspect "${EGRESS_NETWORK}" --format '{{(index .IPAM.Config 0).Subnet}}')"
  ACTUAL_GATEWAY="$(docker network inspect "${EGRESS_NETWORK}" --format '{{(index .IPAM.Config 0).Gateway}}')"
  if [[ "${ACTUAL_SUBNET}" != "${EGRESS_SUBNET}" || "${ACTUAL_GATEWAY}" != "${EGRESS_GATEWAY}" ]]; then
    echo >&2 "ERROR: '${EGRESS_NETWORK}' exists with unexpected IPAM settings."
    echo >&2 "Expected: subnet=${EGRESS_SUBNET} gateway=${EGRESS_GATEWAY}"
    echo >&2 "Actual:   subnet=${ACTUAL_SUBNET} gateway=${ACTUAL_GATEWAY}"
    exit 1
  fi
fi

# Compose creates/recreates Nagios on the egress bridge first.
compose up -d --build "${CONTAINER}"

# Attach the Traefik bridge idempotently. This is deliberately outside the
# legacy Compose file because the Engine cannot express gateway priority.
if ! network_attached "${PROXY_NETWORK}"; then
  docker network connect "${PROXY_NETWORK}" "${CONTAINER}"
fi

# Attaching another bridge may cause legacy Docker to change the default route.
# Restore it deterministically. NET_ADMIN is granted only for this workaround.
docker exec \
  -e NAGIOS_EGRESS_GATEWAY="${EGRESS_GATEWAY}" \
  "${CONTAINER}" /usr/local/bin/configure_egress_route.sh

echo
echo "Nagios network attachments:"
docker inspect "${CONTAINER}" \
  --format '{{range $name, $cfg := .NetworkSettings.Networks}}{{$name}} -> {{$cfg.IPAddress}} gateway={{$cfg.Gateway}}{{println}}{{end}}'

echo
echo "Testing public TCP endpoint ${PUBLIC_IP}:443 from Nagios ..."
if ! docker exec "${CONTAINER}" \
  bash -c "timeout 5 bash -c '</dev/tcp/${PUBLIC_IP}/443'"; then
  echo >&2 "ERROR: ${PUBLIC_IP}:443 is not reachable from the Nagios container."
  exit 1
fi
echo "${PUBLIC_IP}:443 OK"

echo
echo "Testing Nextcloud through the public IP with Host/SNI ${PUBLIC_HOST} ..."
docker exec "${CONTAINER}" \
  /usr/local/nagios/libexec/check_http \
  -4 \
  -I "${PUBLIC_IP}" \
  -H "${PUBLIC_HOST}" \
  -S \
  --sni \
  --verify-host \
  -u /status.php \
  -e 200 \
  -s '"installed":true' \
  -w 5 \
  -c 10 \
  -t 15
