#!/usr/bin/env bash
set -euo pipefail

EGRESS_NETWORK="sensu_egress"
AGENT_CONTAINER="sensu-agent"

if [[ ! -f .env ]]; then
  echo "ERROR: .env is missing. Copy .env.example to .env and set the current Sensu admin password." >&2
  exit 1
fi

# Support both modern Docker Compose v2 and legacy docker-compose v1.
if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  echo "ERROR: Neither 'docker compose' nor 'docker-compose' is available." >&2
  exit 1
fi

echo "Using Compose command: ${COMPOSE[*]}"

# We need the same dedicated egress route as in the Nagios setup. Legacy
# docker-compose cannot express gw_priority, so attach the network afterwards.
if ! docker network connect --help 2>&1 | grep -q -- '--gw-priority'; then
  echo "ERROR: This Docker Engine does not support 'docker network connect --gw-priority'." >&2
  echo "The Sensu agent needs that option for the dedicated external egress route." >&2
  exit 1
fi

if ! docker network inspect "${EGRESS_NETWORK}" >/dev/null 2>&1; then
  echo "Creating Docker network ${EGRESS_NETWORK} ..."
  docker network create "${EGRESS_NETWORK}" >/dev/null
fi

"${COMPOSE[@]}" up -d --build sensu-backend sensu-agent

# Reattach idempotently so the desired gateway priority is always enforced.
docker network disconnect "${EGRESS_NETWORK}" "${AGENT_CONTAINER}" >/dev/null 2>&1 || true
docker network connect --gw-priority 1 "${EGRESS_NETWORK}" "${AGENT_CONTAINER}"

echo
printf 'Applying Sensu Configuration-as-Code...\n'
"${COMPOSE[@]}" run --rm sensu-config

echo
printf 'Sensu services:\n'
"${COMPOSE[@]}" ps

echo
printf 'Agent network attachments:\n'
docker inspect "${AGENT_CONTAINER}" \
  --format '{{range $name, $cfg := .NetworkSettings.Networks}}{{$name}} -> {{$cfg.IPAddress}}{{println}}{{end}}'

echo
printf 'Agent default route:\n'
docker exec "${AGENT_CONTAINER}" sh -c 'ip route 2>/dev/null || route -n 2>/dev/null || true'
