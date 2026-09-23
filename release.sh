#!/bin/bash
# Builds a signed, notarised, stapled Kalfa and packages it for download.
#
# What you need once, before the first release:
#
#   1. A "Developer ID Application" certificate in the login keychain.
#      Apple Developer portal -> Certificates -> +, then double-click the
#      downloaded .cer. A "Apple Development" certificate is NOT enough: it is
#      for running on your own machines and Gatekeeper rejects it elsewhere.
#
#   2. A notarisation credential stored in the keychain, so no password ends up
#      in this file or in your shell history:
#
#        xcrun notarytool store-credentials kalfa-notary \
#          --apple-id you@example.com --team-id 7VT27N92K3 \
#          --password <app-specific-password>
#
#      The app-specific password is made at appleid.apple.com, not your real one.
#
# Then:  ./release.sh 1.0
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?kullanım: ./release.sh <sürüm>   örn. ./release.sh 1.0}"
KEYCHAIN_PROFILE="${KALFA_NOTARY_PROFILE:-kalfa-notary}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# `|| true` şart: grep eşleşme bulamazsa 1 döner, `set -e` de aşağıdaki
# açıklayıcı hatayı basamadan betiği sessizce öldürür.
find_identity() {
  security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/' || true
}
IDENTITY="${KALFA_SIGN_IDENTITY:-$(find_identity)}"
if [ -z "$IDENTITY" ]; then
  echo "Developer ID Application sertifikası bulunamadı."
  echo "Dosyanın başındaki adımlara bak; imzasız bir sürüm dağıtmanın anlamı yok."
  exit 1
fi
TEAM_ID="${KALFA_TEAM_ID:-$(echo "$IDENTITY" | sed -E 's/.*\(([A-Z0-9]+)\)$/\1/')}"
echo "İmza: $IDENTITY"
echo "Ekip: $TEAM_ID"

command -v xcodegen >/dev/null || { echo "xcodegen yok: brew install xcodegen"; exit 1; }
# xcodegen üretilen Info.plist'in üzerine YAZMIYOR: bir kez oluşturduktan sonra
# dosya diskte kaldığı için project.yml'deki sürüm değişikliği pakete hiç
# ulaşmıyor. 1.0.0 etiketiyle 1.0 diyen bir uygulama bu yüzden çıktı. Tek
# doğruluk kaynağı project.yml olsun diye her derlemede siliniyor.
rm -f Supporting/Info.plist

xcodegen generate --quiet

rm -rf build dist
xcodebuild \
  -project Kalfa.xcodeproj \
  -scheme Kalfa \
  -configuration Release \
  -derivedDataPath build \
  MARKETING_VERSION="$VERSION" \
  KALFA_SIGN_IDENTITY="$IDENTITY" \
  KALFA_TEAM_ID="$TEAM_ID" \
  build

mkdir -p dist
cp -R "build/Build/Products/Release/Kalfa.app" dist/
APP="dist/Kalfa.app"

# Xcode zaten imzaladı; yine de sertleştirilmiş çalışma zamanı ve zaman damgası
# ile bir kez daha imzalanır. Noterleme ikisi de yoksa reddeder.
codesign --force --options runtime --timestamp \
  --entitlements Kalfa/Resources/Kalfa.entitlements \
  --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# zip DEĞİL: imzayı bozuyor. Apple'ın kendi aracı sembolik bağları ve genişletilmiş
# öznitelikleri koruyor.
ZIP="dist/Kalfa-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Noterleniyor… (birkaç dakika sürebilir)"
xcrun notarytool submit "$ZIP" --keychain-profile "$KEYCHAIN_PROFILE" --wait

# Damgayı uygulamanın içine yapıştır: kullanıcı ilk açtığında çevrimdışı olsa
# bile Gatekeeper onayı görsün.
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# Damgalanmış hâli yeniden paketle; yukarıdaki zip damgadan önce üretildi.
rm "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"

echo
echo "$ZIP hazır — imzalı, noterlenmiş, damgalanmış."
echo "Gatekeeper kontrolü:"
spctl --assess --type execute --verbose=2 "$APP" || true
