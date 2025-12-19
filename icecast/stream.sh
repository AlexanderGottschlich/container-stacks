#!/usr/bin/env bash

# KEIN set -e → Fehler fangen wir selbst ab

MUSIC_DIR="/music"
ICECAST_HOST="icecast"
ICECAST_PORT="8000"
ICECAST_MOUNT="radio"
ICECAST_SOURCE_PASSWORD="${ICECAST_SOURCE_PASSWORD:-changeme}"

echo "Starte Icecast-Stream-Loop (ENDLOS-STREAM über stdin, nur AUDIO)..."

cd "${MUSIC_DIR}" || {
  echo "Fehler: Kann Verzeichnis ${MUSIC_DIR} nicht betreten."
  sleep 10
  exit 1
}

while true; do
  echo "Prüfe, ob Icecast erreichbar ist..."

  # Warten, bis Icecast Port 8000 annimmt
  while ! bash -c ">/dev/tcp/${ICECAST_HOST}/${ICECAST_PORT}" 2>/dev/null; do
    echo "Warte auf ${ICECAST_HOST}:${ICECAST_PORT}..."
    sleep 2
  done

  echo "Icecast erreichbar – starte ffmpeg-Stream..."

  # Gibt es überhaupt MP3s?
  if ! find . -type f -iname "*.mp3" | grep -q .; then
    echo "Keine MP3-Dateien gefunden – warte 30s..."
    sleep 30
    continue
  fi

  # Endloser MP3-Strom: rekursiv, zufällig, leerzeichen-sicher
  if ! find . -type f -iname "*.mp3" -print0 \
      | shuf -z \
      | xargs -0 cat \
      | ffmpeg -nostdin -re -vn -i - \
          -map 0:a:0 \
          -acodec libmp3lame -b:a 128k \
          -metadata streamtitle="Mein Icecast Radio" \
          -content_type audio/mpeg \
          -f mp3 \
          "icecast://source:${ICECAST_SOURCE_PASSWORD}@${ICECAST_HOST}:${ICECAST_PORT}/${ICECAST_MOUNT}"
  then
    echo "ffmpeg mit Fehler beendet – Neustart in 5 Sekunden..."
    sleep 5
  else
    echo "ffmpeg normal beendet – starte neue Runde in 5 Sekunden..."
    sleep 5
  fi
done

