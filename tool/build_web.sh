#!/bin/sh
# Builds the web app and stamps every build with its own id, so browsers load
# the new flutter_bootstrap.js and main.dart.js instead of cached old ones.
set -e
cd "$(dirname "$0")/.."
flutter build web --pwa-strategy=none "$@"
id=$(date +%Y%m%d%H%M%S)
sed -i.bak "s/__BUILD_ID__/$id/g" build/web/index.html build/web/flutter_bootstrap.js
rm -f build/web/index.html.bak build/web/flutter_bootstrap.js.bak
echo "Build $id ready in build/web"
