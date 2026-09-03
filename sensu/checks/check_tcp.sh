#!/usr/bin/env bash
set -euo pipefail

HOST=""
IP=""
PORT="443"

usage() {
  echo "Usage: $0 --host HOST [--ip IP] [--port PORT]" >&2
  exit 3
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --ip) IP="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -n "$HOST" ]] || usage
TARGET="${IP:-$HOST}"

if nc -z -w 5 "$TARGET" "$PORT" >/dev/null 2>&1; then
  echo "OK - TCP ${HOST} (${TARGET}):${PORT} reachable"
  exit 0
fi

echo "CRITICAL - TCP ${HOST} (${TARGET}):${PORT} unreachable"
exit 2
