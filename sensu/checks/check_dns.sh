#!/usr/bin/env bash
set -euo pipefail

HOST=""
EXPECTED_IP=""
SERVER=""
PORT="53"

usage() {
  echo "Usage: $0 --host HOST [--expected-ip IP] [--server DNS_SERVER] [--port PORT]" >&2
  exit 3
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --expected-ip) EXPECTED_IP="${2:-}"; shift 2 ;;
    --server) SERVER="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -n "$HOST" ]] || usage

DIG_ARGS=(+time=3 +tries=1 +short A "$HOST")
if [[ -n "$SERVER" ]]; then
  DIG_ARGS=(-p "$PORT" "@${SERVER}" "${DIG_ARGS[@]}")
fi

START_NS="$(date +%s%N 2>/dev/null || date +%s000000000)"
set +e
RESULT="$(dig "${DIG_ARGS[@]}" 2>&1)"
RC=$?
set -e
END_NS="$(date +%s%N 2>/dev/null || date +%s000000000)"

if [[ $RC -ne 0 ]] || [[ -z "$(printf '%s' "$RESULT" | tr -d '[:space:]')" ]]; then
  if [[ -n "$SERVER" ]]; then
    echo "CRITICAL - DNS ${HOST} via ${SERVER}:${PORT} returned no A record: ${RESULT}"
  else
    echo "CRITICAL - DNS ${HOST} returned no A record: ${RESULT}"
  fi
  exit 2
fi

if [[ -n "$EXPECTED_IP" ]] && ! printf '%s\n' "$RESULT" | grep -Fxq "$EXPECTED_IP"; then
  VALUES="$(printf '%s\n' "$RESULT" | paste -sd, -)"
  echo "CRITICAL - DNS ${HOST} returned ${VALUES}; expected ${EXPECTED_IP}"
  exit 2
fi

VALUES="$(printf '%s\n' "$RESULT" | paste -sd, -)"
if [[ "$START_NS" =~ ^[0-9]+$ ]] && [[ "$END_NS" =~ ^[0-9]+$ ]]; then
  MS=$(( (END_NS - START_NS) / 1000000 ))
else
  MS=0
fi

if [[ -n "$SERVER" ]]; then
  echo "OK - DNS ${HOST} via ${SERVER}:${PORT} -> ${VALUES} (${MS}ms)"
else
  echo "OK - DNS ${HOST} -> ${VALUES} (${MS}ms)"
fi
