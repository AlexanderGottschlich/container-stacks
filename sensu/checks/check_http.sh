#!/usr/bin/env bash
set -euo pipefail

HOST=""
IP=""
PATHNAME="/"
EXPECTED="200"
CONTENT=""
FOLLOW=0

usage() {
  echo "Usage: $0 --host HOST [--ip IP] [--path /] [--status 200,301] [--content TEXT] [--follow]" >&2
  exit 3
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --ip) IP="${2:-}"; shift 2 ;;
    --path) PATHNAME="${2:-}"; shift 2 ;;
    --status) EXPECTED="${2:-}"; shift 2 ;;
    --content) CONTENT="${2:-}"; shift 2 ;;
    --follow) FOLLOW=1; shift ;;
    *) usage ;;
  esac
done

[[ -n "$HOST" ]] || usage
[[ "$PATHNAME" == /* ]] || PATHNAME="/$PATHNAME"

BODY="$(mktemp)"
ERR="$(mktemp)"
trap 'rm -f "$BODY" "$ERR"' EXIT

CURL_ARGS=(
  --silent --show-error
  --output "$BODY"
  --write-out '%{http_code} %{time_total}'
  --connect-timeout 5
  --max-time 15
)

if [[ -n "$IP" ]]; then
  CURL_ARGS+=(--resolve "$HOST:443:$IP")
fi

if [[ "$FOLLOW" -eq 1 ]]; then
  CURL_ARGS+=(--location --max-redirs 5)
fi

set +e
RESULT="$(curl "${CURL_ARGS[@]}" "https://${HOST}${PATHNAME}" 2>"$ERR")"
RC=$?
set -e

if [[ $RC -ne 0 ]]; then
  echo "CRITICAL - HTTPS request to ${HOST}${PATHNAME} failed: $(tr '\n' ' ' < "$ERR")"
  exit 2
fi

STATUS="${RESULT%% *}"
DURATION="${RESULT#* }"

IFS=',' read -r -a ALLOWED <<< "$EXPECTED"
STATUS_OK=0
for code in "${ALLOWED[@]}"; do
  if [[ "$STATUS" == "$code" ]]; then
    STATUS_OK=1
    break
  fi
done

if [[ "$STATUS_OK" -ne 1 ]]; then
  echo "CRITICAL - HTTPS ${HOST}${PATHNAME} returned HTTP ${STATUS}; expected ${EXPECTED}"
  exit 2
fi

if [[ -n "$CONTENT" ]] && ! grep -Fq -- "$CONTENT" "$BODY"; then
  echo "CRITICAL - HTTPS ${HOST}${PATHNAME} returned HTTP ${STATUS}, but content '${CONTENT}' was not found"
  exit 2
fi

if [[ -n "$CONTENT" ]]; then
  echo "OK - HTTPS ${HOST}${PATHNAME} HTTP ${STATUS}, content '${CONTENT}' found, ${DURATION}s"
else
  echo "OK - HTTPS ${HOST}${PATHNAME} HTTP ${STATUS}, ${DURATION}s"
fi
