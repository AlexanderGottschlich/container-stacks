#!/usr/bin/env bash
set -euo pipefail

EGRESS_NETWORK="nagios_egress"
CONTAINER="nagios"

if ! docker network connect --help 2>&1 | grep -q -- '--gw-priority'; then
  echo "ERROR: This Docker Engine does not support 'docker network connect --gw-priority'."
  echo "Upgrade Docker Engine/CLI before using the dedicated egress route."
  exit 1
fi

if ! docker network inspect "${EGRESS_NETWORK}" >/dev/null 2>&1; then
  docker network create "${EGRESS_NETWORK}"
fi

docker-compose up -d --build "${CONTAINER}"

docker network disconnect "${EGRESS_NETWORK}" "${CONTAINER}" >/dev/null 2>&1 || true
docker network connect --gw-priority 1 "${EGRESS_NETWORK}" "${CONTAINER}"

echo
echo "Nagios networks:"
docker inspect "${CONTAINER}" \
  --format '{{range $name, $cfg := .NetworkSettings.Networks}}{{$name}} -> {{$cfg.IPAddress}}{{println}}{{end}}'

echo
echo "External target test:"
docker-compose exec -T nagios \
  bash -c 'timeout 5 bash -c "</dev/tcp/152.53.46.232/443" && echo "152.53.46.232:443 OK" || echo "152.53.46.232:443 FAILED"'
