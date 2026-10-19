# Değişiklikler

Biçim: [Keep a Changelog](https://keepachangelog.com/tr/1.1.0/),
sürümleme [SemVer](https://semver.org/lang/tr/).

## [1.1.1] — 2026-10-19

### Düzeltildi
- Bakım > Onarım sekmesi pencerenin tamamını boş gösteriyordu (kenar çubuğu dahil):
  liste kendi kaydırmasını taşımadığı için sayfa ~6000 pt'ye uzayıp pencereyi ekranın
  dışına itiyordu.
- "Birlikte Aç listesini onar" her seferinde hata veriyordu: `lsregister -kill` ve
  `-domain` yeni macOS'ta yok; yerine `-gc` + `-all local,user`.
- Yönetici gerektiren onarımlar `NSAppleScript`'i arka kuyrukta çalıştırıyordu (yalnız
  ana iş parçacığında güvenli); artık ayrı `osascript` süreci.
- DPI motoru yeniden başlatılırken nadiren çökebiliyordu: eşzamanlı kuyrukta durum
  işleyicisi ile emniyet zamanlayıcısı aynı continuation'ı iki kez sürdürebiliyordu.
- Disk analizi: iptalin hemen ardından başlatılan tarama, eskisinin yarım sonucuyla
  "bitti" sayılabiliyordu.

### Belgeler
- README (TR/EN) genişletildi: hazır paketle kurulum, macOS 15+ ilk açılış adımı,
  kısayol tablosu, onarım ayrıntısı, SSS ve sorun giderme, geliştirme.

## [1.1.0] — 2026-10-12

### Eklendi
- Dock konumu: Kapalı / Ana ekranda / Kenara dokununca. Panelde tek düğme, Sistem >
  Gizli anahtarlar'da seçici. Yöntem DockAnchor'dan (oturum düzeyinde dinleyici,
  olay düşürme); Kalfa imleci hiç oynatmaz.

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
