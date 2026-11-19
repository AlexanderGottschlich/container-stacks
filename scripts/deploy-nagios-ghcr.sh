#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^ghcr\.io/[a-z0-9_.-]+/container-stacks-nagios:sha-[a-f0-9]{40}$ ]]; then
  echo 'Usage: deploy-nagios-ghcr.sh ghcr.io/<owner>/container-stacks-nagios:sha-<40-char-sha>' >&2
  exit 2
fi
IMAGE="$1"
ROOT="${STACKS_ROOT:-/opt/container-stacks}"
cd "$ROOT/nagios"
[[ -f docker-compose.yml && -f scripts/start-nagios.sh ]] || { echo 'Nagios project missing' >&2; exit 1; }
[[ -f .env ]] || { echo 'Nagios .env missing' >&2; exit 1; }
if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
else
  COMPOSE=(docker-compose)
fi
RELEASE_DIR="$ROOT/.releases/nagios"
mkdir -p "$RELEASE_DIR"
CURRENT="$RELEASE_DIR/compose.override.yml"
NEXT="$RELEASE_DIR/compose.override.next.yml"
PREVIOUS="$RELEASE_DIR/compose.override.previous.yml"

docker pull "$IMAGE"
printf 'services:\n  nagios:\n    image: "%s"\n' "$IMAGE" > "$NEXT"
"${COMPOSE[@]}" -f docker-compose.yml -f "$NEXT" config --quiet

if [[ -f "$CURRENT" ]]; then
  cp "$CURRENT" "$PREVIOUS"
fi
mv "$NEXT" "$CURRENT"
# Use the original tested network/firewall setup and Nagios functional checks.
# If deployment fails, restore previous config, but do not assume a restart
# can undo stateful volume changes.
if ! NAGIOS_COMPOSE_OVERRIDE="$CURRENT" NAGIOS_NO_BUILD=1 bash scripts/start-nagios.sh; then
  echo 'Deployment validation failed. Attempting prior image rollback...' >&2
  if [[ -f "$PREVIOUS" ]]; then
    cp "$PREVIOUS" "$CURRENT"
    NAGIOS_COMPOSE_OVERRIDE="$CURRENT" NAGIOS_NO_BUILD=1 bash scripts/start-nagios.sh || true
  else
    echo 'No previous GHCR override available; manual recovery required.' >&2
  fi
  exit 1
fi
printf 'Deployed and checked %s\n' "$IMAGE"
