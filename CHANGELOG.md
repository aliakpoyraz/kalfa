# Değişiklikler

Biçim: [Keep a Changelog](https://keepachangelog.com/tr/1.1.0/),
sürümleme [SemVer](https://semver.org/lang/tr/).

## [1.0.0] — 2026-09-24

İlk herkese açık sürüm.

### Eklendi
- Menü çubuğu paneli: durum çipleri, altı anahtar, beş açılır kart.
- Tek pencere (kenar çubuklu): Ekran · Ses · Sistem · Bakım · Sağlık · DPI ·
  Ayarlar · Hakkında.
- Komut paleti: kısayolla her yerden, Türkçe karakterden bağımsız arama.
- Ekran: HiDPI, gizli modlar, piksel eşleşmesi etiketleri, 15 saniyelik onaylı
  geçiş, DDC parlaklık/kontrast, kablo sinyali göstergesi, profiller.
- Ses: cihaz seçimi, cihaz başına seviye hafızası, gerçek sistem geneli mikrofon
  susturma, uygulama başına karıştırıcı (macOS 14.2+).
- Sistem: uyanık tut, sunum modu, zamanlayıcı, pencere yerleştirme, DNS, harici
  disk çıkarma, gizli anahtarlar, klavye kısayolları.
- Bakım: disk analizi, temizlik, uygulama kaldırma, onarım.
- Sağlık: bir özelliğin neden çalışmadığını tek sayfada gösterir.
- Kesintisiz fare kaydırması.
- DPI: engellenen sitelere erişim; kendi proxy motoru.
- `kalfa://window?section=<ad>` ve `ezdpi://on|off|auto|relaunch` URL şemaları.
- TR/EN arayüz, uygulama içinden dil seçimi.

### Değişti
- Klapa ve ezDPI tek uygulamada birleşti; ürün adı **Kalfa**.
- DPI motoru gömülü `spoofdpi` ikilisi yerine Kalfa'nın kendi kodu. Kazanç: TLS
  kaydı parçalama, gömülü ikili yok, Intel desteği bedava, kural değişikliği
  motoru yeniden başlatmıyor.
- Dokuz ayrı pencere ve popover üç yüzeye indi.

### Bilinen sınırlar
- Mac App Store'a giremez (özel API ve sandbox dışı işler).
- Root gerektiren DPI teknikleri (sahte TTL, sıra dışı segment) kapsam dışı.
- Erişilebilirlik izni imzaya bağlıdır; ad-hoc imzalı derlemede her yeniden
  derlemede tekrar istenir.
