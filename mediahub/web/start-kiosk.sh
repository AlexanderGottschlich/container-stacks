#!/usr/bin/env bash
set -euo pipefail
KIOSK_DIR="${HOME}/kiosk"
START_PAGE="file://${KIOSK_DIR}/index.html"
command -v xset >/dev/null 2>&1 && { xset s off || true; xset -dpms || true; xset s noblank || true; }
#exec chromium-browser --kiosk --noerrdialogs --disable-infobars --disable-session-crashed-bubble --disable-pinch --overscroll-history-navigation=0 --autoplay-policy=no-user-gesture-required "${START_PAGE}"
#exec firefox --kiosk --private-window "${START_PAGE}"

#./exit-server.sh &
python3 exit-server.py &
EXIT_SERVER_PID=$!

cleanup() {
  echo "[kiosk] stopping exit server (pid=$EXIT_SERVER_PID)"
  kill "$EXIT_SERVER_PID" 2>/dev/null || true
}

# Cleanup bei Script-Ende, Ctrl+C, kill
trap cleanup EXIT INT TERM

exec firefox --kiosk "${START_PAGE}"
