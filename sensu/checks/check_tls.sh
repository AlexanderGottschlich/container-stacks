#!/usr/bin/env bash
set -euo pipefail

HOST=""
IP=""
WARN_DAYS=30
CRIT_DAYS=14

usage() {
  echo "Usage: $0 --host HOST [--ip IP] [--warning DAYS] [--critical DAYS]" >&2
  exit 3
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --ip) IP="${2:-}"; shift 2 ;;
    --warning) WARN_DAYS="${2:-}"; shift 2 ;;
    --critical) CRIT_DAYS="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -n "$HOST" ]] || usage
TARGET="${IP:-$HOST}:443"
TMP="$(mktemp)"
ERR="$(mktemp)"
trap 'rm -f "$TMP" "$ERR"' EXIT

set +e
timeout 15 openssl s_client \
  -connect "$TARGET" \
  -servername "$HOST" \
  -verify_hostname "$HOST" \
  -verify_return_error \
  -showcerts < /dev/null >"$TMP" 2>"$ERR"
RC=$?
set -e

if [[ $RC -ne 0 ]]; then
  echo "CRITICAL - TLS validation failed for ${HOST} via ${TARGET}: $(tail -n 3 "$ERR" | tr '\n' ' ')"
  exit 2
fi

if ! openssl x509 -in "$TMP" -noout >/dev/null 2>&1; then
  echo "CRITICAL - Could not read TLS certificate for ${HOST}"
  exit 2
fi

ENDDATE="$(openssl x509 -in "$TMP" -noout -enddate | cut -d= -f2-)"
CRIT_SEC=$(( CRIT_DAYS * 86400 ))
WARN_SEC=$(( WARN_DAYS * 86400 ))

if ! openssl x509 -in "$TMP" -noout -checkend "$CRIT_SEC" >/dev/null 2>&1; then
  echo "CRITICAL - TLS certificate for ${HOST} expires within ${CRIT_DAYS} days (${ENDDATE})"
  exit 2
fi

if ! openssl x509 -in "$TMP" -noout -checkend "$WARN_SEC" >/dev/null 2>&1; then
  echo "WARNING - TLS certificate for ${HOST} expires within ${WARN_DAYS} days (${ENDDATE})"
  exit 1
fi

echo "OK - TLS certificate for ${HOST} is valid for more than ${WARN_DAYS} days (${ENDDATE})"
