#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f .env ]]; then
  echo "ERROR: .env is missing. Copy .env.example to .env and set the current Sensu admin password." >&2
  exit 1
fi

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  echo "ERROR: Neither 'docker compose' nor 'docker-compose' is available." >&2
  exit 1
fi

echo "Using Compose command: ${COMPOSE[*]}"

if ! docker network inspect proxy_net >/dev/null 2>&1; then
  echo "ERROR: external Docker network 'proxy_net' does not exist." >&2
  exit 1
fi

"${COMPOSE[@]}" up -d --build sensu-backend sensu-agent-external sensu-agent-internal

echo
printf 'Applying Sensu Configuration-as-Code...\n'
"${COMPOSE[@]}" run --rm sensu-config

echo
printf 'Sensu services:\n'
"${COMPOSE[@]}" ps

echo
printf 'External agent networks:\n'
docker inspect sensu-agent-external \
  --format '{{range $name, $cfg := .NetworkSettings.Networks}}{{$name}} -> {{$cfg.IPAddress}}{{println}}{{end}}'

echo
printf 'Internal agent networks:\n'
docker inspect sensu-agent-internal \
  --format '{{range $name, $cfg := .NetworkSettings.Networks}}{{$name}} -> {{$cfg.IPAddress}}{{println}}{{end}}'

echo
printf 'External route / own-public-IP test:\n'
docker exec sensu-agent-external sh -c '
  (ip route 2>/dev/null || route -n 2>/dev/null || true)
  echo
  /opt/sensu/checks/check_tcp.sh --host sensu.elastic2ls.com --ip 152.53.46.232 --port 443 || true
'

echo
printf 'Internal DNS target resolution:\n'
docker exec sensu-agent-internal sh -c '
  getent hosts pihole 2>/dev/null || echo "pihole: not resolvable on proxy_net"
  getent hosts unbound 2>/dev/null || echo "unbound: not resolvable on proxy_net"
'
