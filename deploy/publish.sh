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
# the landing pages talk to the API and open the app on their own subdomains; every page carries the tags it needs
for page in deploy/site/landing/*.html; do
  sed -i.bak -e "s|<meta name=\"ahead-api\" content=\"demo\">|<meta name=\"ahead-api\" content=\"https://api.$DOMAIN\">|" \
    -e "s|<meta name=\"ahead-app\" content=\"../\">|<meta name=\"ahead-app\" content=\"https://app.$DOMAIN/\">|" "$page"
  rm -f "$page.bak"
done
grep -q "content=\"https://api.$DOMAIN\"" deploy/site/landing/index.html || { echo "ahead-api nicht gesetzt"; exit 1; }
# no page may still point at the preview API or at the app's GitHub Pages path
if grep -l -e '<meta name="ahead-api" content="demo">' -e '<meta name="ahead-app" content="../">' deploy/site/landing/*.html; then
  echo "ahead-api oder ahead-app in den Seiten oben nicht gesetzt"; exit 1
fi

echo "3/4 Hochladen nach $SERVER"
ssh "$SERVER" "mkdir -p /opt/ahead/deploy /opt/ahead/backend /opt/ahead/lib/legal"
rsync -az --delete --exclude .data --exclude .env --exclude '*.pem' --exclude .dart_tool backend/ "$SERVER:/opt/ahead/backend/"
rsync -az --delete lib/legal/ "$SERVER:/opt/ahead/lib/legal/"
rsync -az --delete --exclude .env --exclude keys deploy/ "$SERVER:/opt/ahead/deploy/"

echo "4/4 Starten"
ssh "$SERVER" "cd /opt/ahead/deploy && DOMAIN=$DOMAIN docker compose up -d --build"
echo "Fertig: https://$DOMAIN  ·  https://app.$DOMAIN  ·  https://api.$DOMAIN/health"
