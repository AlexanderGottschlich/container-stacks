#!/bin/sh
set -eu

API_URL="${SENSU_API_URL:-http://sensu-backend:8080}"
USER="${SENSU_ADMIN_USER:?SENSU_ADMIN_USER is required}"
PASS="${SENSU_ADMIN_PASS:?SENSU_ADMIN_PASS is required}"

printf 'Waiting for Sensu API at %s...\n' "$API_URL"
i=0
until sensuctl configure -n \
  --url "$API_URL" \
  --username "$USER" \
  --password "$PASS" \
  --format tabular >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -ge 60 ]; then
    echo "ERROR: Sensu API/login not ready after 120 seconds." >&2
    echo "Check that SENSU_ADMIN_PASS matches the password stored in the existing Sensu backend." >&2
    exit 1
  fi
  sleep 2
done

echo "Applying Sensu resources from /resources ..."
sensuctl create -r -f /resources

echo
echo "Configured checks:"
sensuctl check list
