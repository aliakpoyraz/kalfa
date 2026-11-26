# Değişiklikler

Biçim: [Keep a Changelog](https://keepachangelog.com/tr/1.1.0/),
sürümleme [SemVer](https://semver.org/lang/tr/).

## [1.2.1] — 2026-11-27

### Düzeltildi
- **Ek karartma MacBook'un kendi ekranında görünmüyordu.** Varsayılan yöntem olan renk
  tablosu dahili XDR ekranda yazılıyor ve geri okunuyor, ama görüntüyü değiştirmiyor.
  Varsayılan artık her ekranda çalışan karartma penceresi; renk tablosu Ekran
  sayfasında seçenek olarak duruyor. 1.2.0'da yöntemi elle değiştirmediysen bir şey
  yapman gerekmez.

## [1.2.0] — 2026-11-26

Arayüz baştan tasarlandı ve parlaklık artık her ekranda, sıfırın altına kadar.

### Eklendi
- **Sıfırın altında parlaklık.** Ekranın ışığı en düşüğe indikten sonra kaydırıcı
  çizgili bölgeye girer ve görüntü ayrıca karartılır. Alt sınır seçilebilir (%40, %30,
  %20); ekran bunun altına inmez. Uyku ve ekran değişiminden sonra yeniden kurulur,
  Kalfa kapanınca ya da çökünce kendiliğinden kalkar, ışık parlaklık tuşlarıyla
  yükseltilirse o da kalkar. İki yöntem: renk tablosu (varsayılan) ve karartma penceresi.
- **Dahili ekranın parlaklığı.** MacBook ekranı ve Apple ekranları da aynı kaydırıcıda.
- **DDC'ye yanıt vermeyen monitörde parlaklık.** "Yanıt vermiyor" yazısı yerine
  görüntüyü karartan bir kaydırıcı.
- Kısayollar: ⌃⌥⌘↓ / ⌃⌥⌘↑ imlecin olduğu ekranın parlaklığı, ⌃⌥⌘0 karartmayı kaldır.
- `kalfa://brightness?level=<n>` ve `kalfa://brightness?reset`.
- Profiller artık her ekranın parlaklığını (ek karartma dahil) taşıyabilir.
- `--dump` her ekranın parlaklığının hangi yoldan ayarlanacağını yazar.
- `scripts/check-design.sh`: görünümlerde tasarım ölçeğinin dışına çıkan boşluk, yazı
  stili ya da rengi yakalar; CI'da koşar. Parlaklık ölçeği için 12 test.

### Değişti
- **Panel bir kumanda oldu.** Yedi karo ve beş açılır kart yerine: parlaklık ve ses
  kaydırıcıları, altı yuvarlak anahtar, panelin içinde açılıp geri dönülen üç konu
  (Ekran, Profiller, İzleme). Panel boyu artık açılan karta göre uzamıyor.
- Dock ve DPI anahtarları modlar arasında körlemesine dönmüyor: tık açar/kapatır, sağ
  tık modları gösterir. Uyanık tut anahtarında sağ tık süreyi seçer.
- **Pencere macOS Ayarlar düzeninde.** Her sayfa gruplu form; içerik 600 pt'de durur,
  etiket ile kontrol yan yana kalır. Akordeon kalmadı.
- Sistem sayfası ikiye bölündü: **Masaüstü** (pencere yerleştirme, Dock, kaydırma, gizli
  anahtarlar, diskler) ve **Güç** (uyanık tut, sunum, zamanlayıcı). DPI ile DNS **Ağ**
  sayfasında toplandı. Hakkında, Ayarlar'ın sonuna indi. Eski
  `kalfa://window?section=system|dpi|about` adresleri yeni sayfalara yönlenir.
- Renk artık konuyu değil durumu anlatıyor: açık olan şey sistem vurgu rengiyle dolar,
  turuncu yalnız uyarı, kırmızı yalnız hata ve susturulmuş mikrofon. 13 konu rengi kalktı.
- Aç/kapa her yerde anahtar; onay kutusu kalmadı. Boşluk ve yazı boyutu tek ölçekten.
- Sağlık sayfası ilgi bekleyenleri üstte listeler; sayısı panelin altında ve kenar
  çubuğunda görünür.

### Kaldırıldı
- Paneldeki durum çipleri, Bakım karosu ve DPI kartı (yerleri: anahtarların kendisi,
  pencerenin Bakım ve Ağ sayfaları).

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
