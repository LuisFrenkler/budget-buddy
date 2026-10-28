#!/usr/bin/env bash
# Build a release IPA for TestFlight. Requires Apple Developer membership + Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${BACKEND_URL:-}" ]]; then
  echo "Set BACKEND_URL to your HTTPS API, e.g.:"
  echo "  BACKEND_URL=https://api.example.com $0"
  exit 1
fi

if [[ "$BACKEND_URL" != https://* ]]; then
  echo "BACKEND_URL must be https://… for a TestFlight build (got: $BACKEND_URL)"
  exit 1
fi

echo "→ flutter pub get"
flutter pub get

echo "→ pod install"
(cd ios && pod install)

echo "→ flutter build ipa (BACKEND_URL=$BACKEND_URL)"
flutter build ipa --release --dart-define=BACKEND_URL="$BACKEND_URL"

echo
echo "IPA under build/ios/ipa/"
echo "Next: Xcode Organizer or Transporter → App Store Connect → TestFlight"
echo "Checklist: docs/testflight.md"
