#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f .env ]]; then
  echo "ERROR: .env is missing. Copy .env.example to .env and set the current Sensu admin password." >&2
  exit 1
fi

# The dedicated egress network is important because the monitoring agent also
# joins proxy_net to reach pihole/unbound by Docker DNS name.
docker compose up -d --build sensu-backend sensu-agent

echo
printf 'Applying Sensu Configuration-as-Code...\n'
docker compose run --rm sensu-config

echo
printf 'Sensu services:\n'
docker compose ps

echo
printf 'Agent network attachments:\n'
docker inspect sensu-agent \
  --format '{{range $name, $cfg := .NetworkSettings.Networks}}{{$name}} -> {{$cfg.IPAddress}}{{println}}{{end}}'
