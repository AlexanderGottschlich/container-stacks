#!/usr/bin/env bash
set -euo pipefail

PORT=9333

# Minimaler HTTP-Responder: bei /exit -> kill browser
while true; do
  { 
    read -r line || true
    req="$(echo "$line" | awk '{print $2}')"
    # restliche Header weglesen
    while read -r h; do [[ "$h" == $'\r' || -z "$h" ]] && break; done

    if [[ "$req" == "/exit" ]]; then
      printf "HTTP/1.1 200 OK\r\nContent-Length:2\r\n\r\nOK" | nc -l -p "$PORT" -q 1
      pkill -f "firefox.*--kiosk" || true
      pkill -f "chromium.*--kiosk" || true
      exit 0
    else
      printf "HTTP/1.1 404 Not Found\r\nContent-Length:3\r\n\r\n404" | nc -l -p "$PORT" -q 1
    fi
  } 
done
