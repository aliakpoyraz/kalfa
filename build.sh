#!/bin/bash
# Builds Kalfa and drops the app in dist/.
#
# Xcode is required (the Command Line Tools alone cannot build an app bundle),
# and xcode-select points at CommandLineTools on this machine, so DEVELOPER_DIR
# is set explicitly rather than relying on the global setting.
set -euo pipefail
cd "$(dirname "$0")"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
CONFIGURATION="${1:-Release}"
# The DPI engine. Not in the repository — it is someone else's Apache-2.0 binary
# — so it is taken from Homebrew at build time and embedded in the bundle, which
# means nobody running Kalfa needs Homebrew.
ENGINE_SRC="${ENGINE_SRC:-/opt/homebrew/bin/spoofdpi}"

command -v xcodegen >/dev/null || { echo "xcodegen missing: brew install xcodegen"; exit 1; }

xcodegen generate --quiet

xcodebuild \
  -project Kalfa.xcodeproj \
  -scheme Kalfa \
  -configuration "$CONFIGURATION" \
  -derivedDataPath build \
  build

rm -rf dist
mkdir -p dist
cp -R "build/Build/Products/$CONFIGURATION/Kalfa.app" dist/

APP="dist/Kalfa.app"
if [ -e "$ENGINE_SRC" ]; then
  # The Homebrew path is a symlink; copy what it points at.
  cp "$(readlink -f "$ENGINE_SRC" 2>/dev/null || echo "$ENGINE_SRC")" "$APP/Contents/Resources/spoofdpi"
  chmod +x "$APP/Contents/Resources/spoofdpi"
  echo "    engine embedded: $ENGINE_SRC"
else
  echo "    WARNING: no engine binary at $ENGINE_SRC — the DPI tab will report it missing"
  echo "             (brew install spoofdpi)"
fi

# Adding a file invalidates the bundle's signature, so sign again afterwards.
codesign --force --sign - "$APP" >/dev/null 2>&1 || codesign --force --deep --sign - "$APP"

echo
echo "dist/Kalfa.app hazır"
