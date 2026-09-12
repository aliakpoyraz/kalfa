# Klapa

**macOS menü çubuğu ekran yöneticisi.** Çözünürlük ve HiDPI seçimi, ekran düzenine
göre profiller, DDC/CI ile donanım parlaklığı.

*[English README](README.md)*

Klapa tek bir arıza yüzünden yazıldı: MacBook'un kapağını kapatıp harici
monitörden çalışmaya geçince masaüstü Retina olmaktan çıkıyor. macOS bir dakika
önce kullandığı HiDPI modunu sunmayı bırakıyor ve Sistem Ayarları'nda onu geri
getirmenin bir yolu yok.

---

## Ne yapar

| | |
|---|---|
| **Tüm çözünürlük modları** | CoreGraphics listesi ile pencere sunucusunun daha uzun kendi listesini birleştirir |
| **Gizli HiDPI modları** | Kapak kapalıyken macOS'un sakladığı Retina modları |
| **Yenileme hızı** | Çözünürlük başına alt menü, ayrıca yüksek/60 Hz anahtarı |
| **Piksel eşleşmesi denetimi** | Her modu `birebir` / `tam 2×` / `küsuratlı · yumuşak` diye etiketler |
| **Monitör modu işareti** | Kullanılan mod monitörün kendi modu mu, macOS'un ürettiği mi söyler |
| **Kablo sinyali göstergesi** | Renk biçimi ve çerçeve tamponu bit derinliği, örn. `10-bit YCbCr 4:2:2` |
| **Ekran düzeni profilleri** | Bağlı panel kümesine göre saklanır, o küme göründüğünde kendiliğinden uygulanır |
| **DDC/CI parlaklık + kontrast** | Apple Silicon'da `IOAVService` üzerinden |
| **Onayla ya da geri al** | Doğrulanmamış modlar 15 saniye içinde korunmazsa geri alınır |
| **Türkçe / English** | Uygulama içinden değiştirilir, sistem dilinden bağımsız |
| **Girişte başlat** | `SMAppService` |

Hiçbir izin gerekmez. Ağ kullanmaz.

---

## Neden pencere sunucusunun özel mod listesini okuyor

`CGDisplayCopyAllDisplayModes` yalnızca IOKit'in "safe" bayrağını taşıyan modları
döndürür. Pencere sunucusu SkyLight'ın kendi listesi daha uzundur ve kapak
kapalıyken sakladığı modlar tam da işe yarayanlardır.

Bir MacBook Pro'nun MSI MAG 274QF'i kapak kapalıyken sürdüğü durumda ölçüldü:

```
CoreGraphics :  139 mod — en büyük HiDPI 1280 × 720 (2560 × 1440 px)
SkyLight     :  304 mod — içinde 2560 × 1440 HiDPI (5120 × 2880 px), 180 Hz
```

Eksik olan o mod sorunun tamamı. Klapa onu SkyLight'ın listesinde bulur ve
`CGSConfigureDisplayMode` ile uygular; çağrı normal bir
`CGDisplayConfiguration` işleminin içine yerleştirilir, böylece atomik olur ve
diğer mod değişiklikleriyle aynı kalıcılık kurallarına uyar.

Bu modlarda "safe" bayrağı yoktur, o yüzden birini seçmek 15 saniyelik
**"Görüntü düzgün mü?"** sayacını başlatır. Hiçbir şey yapmazsan eski mod geri
gelir.

---

## Piksel eşleşmesi denetimi

HiDPI anahtarı mantıksal masaüstü boyutunu korur, yalnızca çizim çözünürlüğünü
değiştirir. Hangi bileşimde olduğun sonucun keskinliğini belirler:

| Mantıksal | Çizim çözünürlüğü | 2560 × 1440 panelde | |
|---|---|---|---|
| 2560 × 1440 | 2560 × 1440 | 1:1 | **birebir** |
| 2560 × 1440 | 5120 × 2880 | tam 2× küçültme | **tam 2×** |
| 1920 × 1080 | 3840 × 2160 | 1,5× küsuratlı küçültme | **küsuratlı · yumuşak** |

Üçüncü satır yanlışlıkla seçilmesi çok kolay olan ve "HiDPI bulanık görünüyor"un
asıl sebebi olan durumdur. Klapa her modu etiketler ve küsuratlı bir moddaysan
en keskin seçeneğe tek tıkla geçiş sunar.

---

## Kablo sinyali göstergesi

Bu satır bilerek salt okunurdur:

```
Kablo sinyali
10-bit YCbCr 4:2:2 · 10-bit çerçeve tamponu
```

`YCbCr 4:2:2` yatay renk çözünürlüğünü yarıya indirir. Metin kenarları yumuşar,
renk taşması olabilir. Bu uygulamanın geliştirildiği makinede bağlantı kapak
açıkken 8-bit YCbCr 4:4:4, kapalıyken 10-bit YCbCr 4:2:2 çalışıyor — aynı
çözünürlük, aynı yenileme hızı.

**Bunu değiştirmenin desteklenen bir yolu yok.** Düzgünce denetlendi:

- Hiçbir ekran modu kanal başına 8 bitten başkasını bildirmiyor, yani kaldıraç
  mod değil.
- HDR kapalı (EDR 1.0 bildiriyor), yani 10-bit çerçeve tamponunu HDR zorlamıyor.
- Yenileme hızını 165, 144 veya 120 Hz'e düşürmek biçimi değiştirmiyor, yani
  bant genişliği değil.
- SkyLight `SLSGetDisplayPixelEncodingOfLength` ve
  `SLSCopyDisplayModePixelEncoding` sunuyor — ikisi de yalnız okuma. Yazma
  işlevi yok.
- DDC/CI'da bağlantı renk biçimi için standart bir VCP kodu yok.

Bu yüzden Klapa değeri denetliyormuş gibi yapmak yerine gösteriyor. Seninki alt
örneklenmişse gerçekten işe yarayabilecekler: monitörün kendi menüsü
(DisplayPort sürümü / giriş renk biçimi), başka bir kablo, başka bir port.

---

## Kurulum

```bash
brew install xcodegen
git clone https://github.com/aliakpoyraz/klapa.git
cd klapa
./build.sh
cp -R dist/Klapa.app /Applications/
```

Uygulama ad-hoc imzalıdır. İlk açılışta sağ tık → **Aç**.

Xcode gerekir; yalnız Command Line Tools ile uygulama paketi derlenemez.
`build.sh` `DEVELOPER_DIR`'i kendisi ayarladığı için `xcode-select`'in Command
Line Tools'u göstermesi sorun değildir.

**Gereksinimler:** macOS 14 veya üzeri. DDC parlaklık için Apple Silicon; geri
kalan her şey Intel'de de çalışır.

---

## Teşhis

```bash
/Applications/Klapa.app/Contents/MacOS/Klapa --dump
```

Bağlı tüm ekranları, kullanılan modu, kablo sinyalini, DDC okumasını ve IOKit
bayraklarıyla birlikte tam mod listesini basar. Kullanılan mod panelin kendi
modu değilse ayrıca uyarır. (Çıktı İngilizcedir.)

```
MAG 274QF
  displayID   3
  uuid        A1B2C3D4-0000-0000-0000-000000000000
  active mode 2560 × 1440 (5120 × 2880 px)       180 Hz   [HiDPI,skylight-only,unverified] id=193
  native mode 2560 × 1440 (2560 × 1440 px)       180 Hz   [native] id=130
  link        10-bit YCbCr 4:2:2
  DDC         brightness 100% (100/100), contrast 75% (75/100)
```

---

## Profiller

`~/Library/Application Support/Klapa/profiles.json` içinde düz JSON olarak durur.

Bir profil **ekran düzenine** göre anahtarlanır: bağlı panellerin sıralı UUID
kümesi. Bu, macOS'un kendi düzen başına ekran ayarları için kullandığı
anahtarın aynısıdır. Kapak açık ile kapak kapalının iki ayrı kayıt olmasının ve
birinin doğruyken diğerinin bozuk kalabilmesinin sebebi budur.

Modlar `IODisplayModeID` ile değil, geometriyle saklanır — pencere sunucusu her
yeniden yapılandırmada bu kimlikleri yeniden numaralandırdığı için saklanan
kimlik geçersizleşir.

---

## Mimari

```
Klapa/
  Core/        ScreenMode · ScreenInfo · DisplaySetKey · L10n · Watchdog · Diagnostics
  Services/    ModeService     CoreGraphics tarafı sayım ve uygulama
               SkyLightModes   özel mod listesi
               LinkInfo        kablo sinyali ve çerçeve tamponu okumaları
               DisplayCenter   durum, yeniden yapılandırma geri çağrısı, otomatik uygulama
               ProfileStore · DDCService · AppSettings · LaunchAtLogin
  Views/       RootView · DisplayCardView · ModePickerView · ScaleToggleView
               LinkRow · DDCControlsView · ProfilesSectionView · SaveProfileView
               SettingsView · AboutView · SwitchRow
  Bridging/    IOAVService ve CGS bildirimleri
```

Pencere sunucusuna giden her çağrı `Watchdog` içinden geçer.
`CGCompleteDisplayConfiguration` yeniden yapılandırma sırasında süresiz bloke
olabilir — ki Klapa tam o anda çalışır — ve menü çubuğunun donmaması gerekir.

### Özel API notları

- `CGSConfigureDisplayMode`'un ilk parametresi `CGBeginDisplayConfiguration`'dan
  gelen bir `CGDisplayConfigRef`'tir, CGS bağlantı kimliği **değildir**.
  Bağlantı kimliği gönderilirse SkyLight onu yapılandırma nesnesi sanıp
  dereference eder ve süreç çöker.
- `CGSGetDisplayModeDescriptionOfLength` 212 baytlık (`0xD4`) bir yapı bekler.
  Ofsetler: mod numarası `0x00`, bayraklar `0x04`, genişlik `0x08`, yükseklik
  `0x0C`, derinlik `0x10`, yenileme hızı `0xBE` (`uint16`), yoğunluk `0xD0`
  (`float`).
- SkyLight yalnızca dyld paylaşılan önbelleğinde bulunur, diskte dosyası yoktur;
  bu yüzden `SLS*` simgeleri bağlanamaz. `dlopen` + `dlsym` ile çözülürler ve
  bulunamazlarsa "kullanılamıyor" durumuna düşerler.
- `MenuBarExtra` penceresi içindeki bir `ScrollView` sıfır ideal yüksekliğe
  çöker ve içeriğini sessizce yutar.

---

## Kapsam dışı

Sanal ekranlar, gamma ve renk sıcaklığı, ICC profil değiştirme, çentik gizleme,
parlaklık tuşlarının yakalanması. Bunlar için
[BetterDisplay](https://github.com/waydabber/BetterDisplay) ve
[FreeDisplay](https://github.com/huberdf/FreeDisplay) var.

## Teşekkür

Hangi özel API'lerin var olduğu ve Apple Silicon'da DDC/CI paketinin nasıl
çerçevelendiği konusunda BetterDisplay ve FreeDisplay referans alındı.

## Lisans

MIT — bkz. [LICENSE](LICENSE).
