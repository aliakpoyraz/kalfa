#!/bin/bash
# Builds Klapa and drops the app in dist/.
#
# Xcode is required (the Command Line Tools alone cannot build an app bundle),
# and xcode-select points at CommandLineTools on this machine, so DEVELOPER_DIR
# is set explicitly rather than relying on the global setting.
set -euo pipefail
cd "$(dirname "$0")"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
CONFIGURATION="${1:-Release}"

command -v xcodegen >/dev/null || { echo "xcodegen missing: brew install xcodegen"; exit 1; }

xcodegen generate --quiet

xcodebuild \
  -project Klapa.xcodeproj \
  -scheme Klapa \
  -configuration "$CONFIGURATION" \
  -derivedDataPath build \
  build

rm -rf dist
mkdir -p dist
cp -R "build/Build/Products/$CONFIGURATION/Klapa.app" dist/

echo
echo "dist/Klapa.app hazır"
