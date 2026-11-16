#!/bin/sh
# Builds the web app and the landing page for DOMAIN and uploads everything
# to the server. Run from your Mac:
#
#   DOMAIN=ahead-beispiel.de SERVER=root@1.2.3.4 deploy/publish.sh
#
# First time only: the server needs Docker (Hetzner's "Docker CE" app image
# has it) and deploy/.env plus deploy/keys/ copied over (see DEPLOY.md).
set -e
: "${DOMAIN:?DOMAIN fehlt, z. B. DOMAIN=ahead-beispiel.de}"
: "${SERVER:?SERVER fehlt, z. B. SERVER=root@1.2.3.4}"
cd "$(dirname "$0")/.."

echo "1/4 Web-App bauen (spricht mit https://api.$DOMAIN)"
tool/build_web.sh --release --no-web-resources-cdn --dart-define=BACKEND_URL="https://api.$DOMAIN"

echo "2/4 Seiten zusammenstellen"
rm -rf deploy/site && mkdir -p deploy/site/app deploy/site/landing
cp -R build/web/. deploy/site/app/
cp -R landing/. deploy/site/landing/
# the landing page talks to the API on its own subdomain
sed -i.bak "s|<meta name=\"ahead-api\" content=\"\">|<meta name=\"ahead-api\" content=\"https://api.$DOMAIN\">|" deploy/site/landing/index.html
rm -f deploy/site/landing/index.html.bak

echo "3/4 Hochladen nach $SERVER"
ssh "$SERVER" "mkdir -p /opt/ahead/deploy /opt/ahead/backend /opt/ahead/lib/legal"
rsync -az --delete --exclude .data --exclude .env --exclude '*.pem' --exclude .dart_tool --exclude test backend/ "$SERVER:/opt/ahead/backend/"
# the server imports ../lib/legal, so it goes up too
rsync -az --delete lib/legal/ "$SERVER:/opt/ahead/lib/legal/"
rsync -az --delete --exclude .env --exclude keys deploy/ "$SERVER:/opt/ahead/deploy/"

echo "4/4 Starten"
ssh "$SERVER" "cd /opt/ahead/deploy && DOMAIN=$DOMAIN docker compose up -d --build"
echo "Fertig: https://$DOMAIN  ·  https://app.$DOMAIN  ·  https://api.$DOMAIN/health"
