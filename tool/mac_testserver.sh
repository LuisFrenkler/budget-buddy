#!/bin/bash
# Ahead-Server auf dem eigenen Mac, nur für die Testphase.
#
#   tool/mac_testserver.sh
#
# Startet den Server lokal und macht ihn über einen kostenlosen Cloudflare
# Quick Tunnel mit HTTPS erreichbar (https://<zufall>.trycloudflare.com).
# Der Mac bleibt wach, solange das Skript läuft. Beenden: Ctrl+C.
#
# Einmalig vorher:
#   1. cloudflared installieren:  brew install cloudflared
#   2. backend/.env anlegen:      cp backend/.env.example backend/.env
#      und darin GEMINI_API_KEY oder ANTHROPIC_API_KEY selbst eintragen.
#
# Die Adresse ändert sich bei jedem Start. Die App kennt den Server zur
# Build-Zeit (BACKEND_URL), deshalb gibt das Skript den passenden
# flutter-Befehl mit aus. Daten liegen in backend/.data auf diesem Mac.
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
RUN="$ROOT/.testserver"
PORT="${PORT:-8090}"
mkdir -p "$RUN"

# --- Voraussetzungen ---------------------------------------------------------
DART="$(command -v dart || true)"
if [ -z "$DART" ] && command -v flutter >/dev/null 2>&1; then
  DART="$(dirname "$(command -v flutter)")/dart"
fi
if [ -z "$DART" ] || [ ! -x "$DART" ]; then
  echo "Dart fehlt. Flutter installieren oder: brew install dart" >&2
  exit 1
fi
CLOUDFLARED="${CLOUDFLARED:-$(command -v cloudflared || true)}"
if [ -z "$CLOUDFLARED" ]; then
  echo "cloudflared fehlt. Einmal installieren: brew install cloudflared" >&2
  exit 1
fi
if [ ! -f backend/.env ]; then
  cp backend/.env.example backend/.env
  echo "backend/.env angelegt. Bitte GEMINI_API_KEY oder ANTHROPIC_API_KEY eintragen und neu starten." >&2
  echo "(Den Schlüssel nie in den Chat oder ins Repo schreiben.)" >&2
  exit 1
fi
if ! grep -Eq '^(GEMINI_API_KEY|ANTHROPIC_API_KEY)=.+' backend/.env; then
  echo "In backend/.env fehlt ein KI-Schlüssel (GEMINI_API_KEY oder ANTHROPIC_API_KEY)." >&2
  echo "Ohne Schlüssel antwortet Buddy nur offline. Trotzdem starten? (j/N)" >&2
  read -r answer
  [ "$answer" = "j" ] || exit 1
fi

# --- Aufräumen beim Beenden -------------------------------------------------
PIDS=""
cleanup() {
  trap - EXIT INT TERM
  for p in $PIDS; do kill "$p" 2>/dev/null || true; done
  rm -f "$RUN/url"
  echo
  echo "Server und Tunnel gestoppt."
}
trap cleanup EXIT INT TERM

# --- 1. Tunnel (zuerst, damit der Server seine öffentliche Adresse kennt) ----
echo "1/3 Tunnel starten …"
: > "$RUN/tunnel.log"
"$CLOUDFLARED" tunnel --no-autoupdate --url "http://127.0.0.1:$PORT" >"$RUN/tunnel.log" 2>&1 &
PIDS="$PIDS $!"
URL=""
for _ in $(seq 1 60); do
  URL="$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$RUN/tunnel.log" | head -1 || true)"
  [ -n "$URL" ] && break
  sleep 1
done
if [ -z "$URL" ]; then
  echo "Tunnel kam nicht hoch. Log: $RUN/tunnel.log" >&2
  tail -5 "$RUN/tunnel.log" >&2
  exit 1
fi
echo "$URL" > "$RUN/url"

# --- 2. Server ---------------------------------------------------------------
echo "2/3 Server starten …"
(cd backend && "$DART" pub get >/dev/null)
(
  cd backend
  # nur lokal erreichbar; der Tunnel reicht die Anfragen durch
  BIND=127.0.0.1 PORT="$PORT" PUBLIC_URL="$URL" TRUST_PROXY=1 \
    exec "$DART" run server.dart
) >"$RUN/server.log" 2>&1 &
PIDS="$PIDS $!"
for _ in $(seq 1 90); do
  if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then break; fi
  sleep 1
done
if ! curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  echo "Server startet nicht. Log: $RUN/server.log" >&2
  tail -15 "$RUN/server.log" >&2
  exit 1
fi

# Mac wach halten, solange dieses Skript läuft
if command -v caffeinate >/dev/null 2>&1; then
  caffeinate -i -w $$ &
  PIDS="$PIDS $!"
fi

# --- 3. Prüfen und Anleitung -------------------------------------------------
echo "3/3 Von außen prüfen …"
OK=""
for _ in $(seq 1 30); do
  if curl -fsS "$URL/health" -o "$RUN/health.json" 2>/dev/null; then OK=1; break; fi
  sleep 2
done

echo
echo "────────────────────────────────────────────────────────────"
if [ -n "$OK" ]; then
  echo " Ahead-Testserver läuft:  $URL"
  echo " Status:                  $(cat "$RUN/health.json")"
else
  echo " Server läuft lokal, der Tunnel braucht noch einen Moment: $URL/health"
fi
echo
echo " App auf dem iPhone gegen diesen Server starten:"
echo "   flutter run --release --dart-define=BACKEND_URL=$URL"
echo
echo " Hinweise:"
echo "   • Die Adresse ändert sich bei jedem Neustart."
echo "   • Mac zu oder offline = Buddy offline."
echo "   • Daten der Tester liegen in backend/.data auf diesem Mac."
echo "   • Logs: .testserver/server.log und .testserver/tunnel.log"
echo " Beenden: Ctrl+C"
echo "────────────────────────────────────────────────────────────"

# läuft, bis Ctrl+C oder einer der beiden Prozesse endet
while :; do
  for p in $PIDS; do
    if ! kill -0 "$p" 2>/dev/null; then
      echo "Ein Prozess ist beendet. Logs in .testserver/." >&2
      exit 1
    fi
  done
  sleep 5
done
