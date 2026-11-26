#!/bin/bash
# Görünümlerde tasarım ölçeğinin dışına çıkan bir şey var mı?
#
# Boşluk ve yazı boyutu KalfaDesign'dan gelir. Elle yazılmış bir boşluk ya da
# sistem yazı stili, ölçeğin yeniden yarı uygulanmış hâle gelmesinin ilk
# adımıdır; bu betik onu derlemeden önce yakalar. 0, 1 ve 2 serbesttir: bunlar
# boşluk değil, kıl payı hizalamadır.
set -euo pipefail
cd "$(dirname "$0")/.."

DIRS=(Kalfa/Views Packages/EzDPIKit/Sources/EzDPIKit/UI)
fail=0

report() {
  local title="$1" pattern="$2" hits
  hits=$(grep -rnE "$pattern" "${DIRS[@]}" --include='*.swift' || true)
  if [ -n "$hits" ]; then
    echo "✗ $title"
    echo "$hits" | sed 's/^/    /'
    fail=1
  fi
}

report "Elle yazılmış boşluk (KalfaDesign.xs/s/m/l/xl kullan)" 'spacing: ([3-9]|[1-9][0-9])\b'
report "Elle yazılmış iç boşluk (KalfaDesign.xs/s/m/l/xl kullan)" '\.padding\(([^)]*, )?([3-9]|[1-9][0-9])\)'
report "Sistem yazı stili (KalfaDesign.*Font kullan)" '\.font\(\.(caption2?|footnote|callout|body|subheadline|headline|title[23]?)\b'
report "Elle yazılmış köşe yarıçapı (KalfaDesign.controlRadius/groupRadius kullan)" 'cornerRadius: [0-9]'
report "Anlamı olmayan renk (KalfaTone kullan)" '(Color)?\.(orange|red|green|blue|purple|teal|pink|mint|cyan|indigo|yellow)\b'

if [ "$fail" -eq 0 ]; then echo "✓ Tasarım ölçeği temiz"; fi
exit "$fail"
