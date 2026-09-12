# Klapa

macOS menü çubuğu ekran yöneticisi. BetterDisplay ve FreeDisplay'in çözdüğü işin
çekirdeği: çözünürlük/HiDPI seçimi, dizilim başına profil, harici monitörde
donanım parlaklığı.

Adı, çözmek için yazıldığı sorundan geliyor: dizüstünün kapağını kapatınca
görüntünün bozulması.

## Ne yapar

| Özellik | Not |
|---|---|
| Tüm çözünürlük modları | CoreGraphics **ve** SkyLight listeleri birleştirilir |
| Gizli HiDPI modları | Kapak kapalıyken macOS'un sakladığı Retina modları |
| Yenileme hızı seçimi | Çözünürlük başına alt menü |
| Yerel zamanlama işareti | Aktif mod EDID'den mi, macOS'un türettiği mi |
| Dizilim profilleri | Ekran kümesi bağlanınca kendiliğinden uygulanır |
| DDC/CI parlaklık + kontrast | Apple Silicon `IOAVService` üzerinden |
| Geri alma sayacı | Güvensiz mod 15 saniyede kendiliğinden geri alınır |
| Girişte başlat | `SMAppService` |

## Neden SkyLight listesi okunuyor

`CGDisplayCopyAllDisplayModes` yalnızca IOKit'in "safe" bayrağını taşıyan modları
döndürür. SkyLight'ın kendi listesi daha uzundur ve kapak kapalıyken sakladığı
modlar tam da işe yarayanlardır.

Bu makinede, MAG 274QF kapak kapalıyken:

```
CoreGraphics : 139 mod — en büyük HiDPI 1280 × 720 (2560 × 1440 px)
SkyLight     : 304 mod — 2560 × 1440 HiDPI (5120 × 2880 px), mod 193, 180 Hz
```

Kapak kapanınca masaüstünün Retina olmaktan çıkmasının sebebi bu: macOS
2560×1440 HiDPI modunu listelemeyi bırakıyor, System Settings de onu gösteremiyor.
Klapa bu modu SkyLight listesinden bulur ve `CGSConfigureDisplayMode` ile uygular.

Bu modlar macOS'un güvenli saymadığı modlardır. Uygulandıklarında 15 saniyelik
"Görüntü düzgün mü?" sayacı devreye girer; onaylanmazsa eski moda dönülür.

## Kurulum

```bash
brew install xcodegen
./build.sh          # dist/Klapa.app
cp -R dist/Klapa.app /Applications/
```

Uygulama ad-hoc imzalıdır. İlk açılışta sağ tık → **Aç**.

Xcode gerekir; bu makinede `xcode-select` Command Line Tools'u gösterdiği için
`build.sh` `DEVELOPER_DIR`'i kendisi ayarlar.

## Teşhis

```bash
/Applications/Klapa.app/Contents/MacOS/Klapa --dump
```

Bağlı ekranları, aktif modu ve her modun bayraklarını basar. Aktif mod EDID yerel
zamanlaması değilse ayrıca uyarır.

## Profiller

`~/Library/Application Support/Klapa/profiles.json` — düz JSON, elle okunabilir.

Profiller **dizilim anahtarına** göre saklanır: bağlı panellerin UUID kümesi.
macOS'un kendi ayarlarını sakladığı anahtarın aynısı. Kapak açık (dahili +
harici) ile kapak kapalı (yalnız harici) iki ayrı kayıttır — biri doğruyken
diğerinin bozuk kalmasının sebebi budur.

## İzinler

Hiçbir izin gerekmez. DDC/CI ve ekran yapılandırma API'leri her sürece açıktır.
Uygulama ağ kullanmaz.

## Kapsam dışı

Sanal ekran, gamma/renk sıcaklığı, ICC profilleri, çentik gizleme, parlaklık
tuşlarının yakalanması. İhtiyaç olursa ayrı servis olarak eklenebilir.

## Mimari

```
Klapa/
  Core/        ScreenMode, ScreenInfo, DisplaySetKey, Watchdog, Diagnostics
  Services/    ModeService (CoreGraphics)   SkyLightModes (özel API)
               DisplayCenter (durum + yeniden yapılandırma geri çağrısı)
               ProfileStore, DDCService, AppSettings, LaunchAtLogin
  Views/       RootView, DisplayCardView, ModePickerView, DDCControlsView,
               ProfilesSectionView, SaveProfileView, SettingsView
  Bridging/    IOAVService + CGS bildirimleri
```

Pencere sunucusuna giden her çağrı `Watchdog` içinden geçer; yeniden yapılandırma
sırasında `CGCompleteDisplayConfiguration` süresiz bloke olabilir ve menü
çubuğunun donmaması gerekir.
