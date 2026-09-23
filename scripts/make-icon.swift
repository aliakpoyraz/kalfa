#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// Kalfa uygulama ikonu. Kaynak burada, PNG üretilmiş çıktı.
// Kullanım: swift scripts/make-icon.swift <varyant> <boyut> <çıktı.png>

/// macOS ikonu tam kareyi doldurmaz: Apple'ın şablonunda içerik 1024'lük
/// tuvalin ortasındaki ~824 pikselde durur, kalanı gölge payıdır. Dolduran
/// ikon, Dock'ta komşularından büyük görünür.
let contentRatio: CGFloat = 824.0 / 1024.0
/// Squircle köşe yarıçapı: içerik kenarının %22,37'si.
let cornerRatio: CGFloat = 0.2237

struct Palette {
    var top: NSColor
    var bottom: NSColor
    var mark: NSColor
    var accent: NSColor
}

let palettes: [String: Palette] = [
    // Koyu lacivert zemin + sıcak pirinç: zanaat aleti çağrışımı, mevcut
    // ikonun rengiyle akraba kalsın diye lacivert korundu.
    "brass": Palette(
        top: NSColor(srgbRed: 0.16, green: 0.20, blue: 0.29, alpha: 1),
        bottom: NSColor(srgbRed: 0.06, green: 0.08, blue: 0.13, alpha: 1),
        mark: NSColor(srgbRed: 0.98, green: 0.80, blue: 0.44, alpha: 1),
        accent: NSColor(srgbRed: 0.85, green: 0.58, blue: 0.24, alpha: 1)),
    // Mürekkep + buz: soğuk, araç gibi durur.
    "ink": Palette(
        top: NSColor(srgbRed: 0.20, green: 0.27, blue: 0.40, alpha: 1),
        bottom: NSColor(srgbRed: 0.07, green: 0.10, blue: 0.17, alpha: 1),
        mark: NSColor(srgbRed: 0.85, green: 0.92, blue: 1.00, alpha: 1),
        accent: NSColor(srgbRed: 0.35, green: 0.65, blue: 0.98, alpha: 1)),
    // Tek renk, yüksek kontrast.
    "mono": Palette(
        top: NSColor(srgbRed: 0.24, green: 0.24, blue: 0.26, alpha: 1),
        bottom: NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1),
        mark: NSColor.white,
        accent: NSColor(srgbRed: 0.98, green: 0.80, blue: 0.44, alpha: 1))
]

/// Squircle: köşeler dairesel yay değil sürekli eğridir. `NSBezierPath`in
/// yuvarlak dikdörtgeni köşede kırılma yapar, macOS ikonunun yanında sırıtır.
func squircle(in rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawBackground(_ context: CGContext, rect: CGRect, palette: Palette) {
    let radius = rect.width * cornerRatio
    context.saveGState()
    context.addPath(squircle(in: rect, radius: radius))
    context.clip()

    let colors = [palette.top.cgColor, palette.bottom.cgColor] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: colors, locations: [0, 1]) {
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: rect.minX, y: rect.maxY),
                                   end: CGPoint(x: rect.maxX, y: rect.minY),
                                   options: [])
    }
    // Üst kenarda ince ışık: düz dolgu plastik görünüyor.
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.16).cgColor)
    context.setLineWidth(rect.width * 0.008)
    context.addPath(squircle(in: rect.insetBy(dx: rect.width * 0.004, dy: rect.width * 0.004),
                             radius: radius))
    context.strokePath()
    context.restoreGState()
}

/// Varyant A — dolu dilim K.
///
/// Kollar gövdeye DEĞER: kesişim noktası gövdenin sağ kenarında, tam orta
/// yükseklikte. Kopuk kollar 256 pikselde bile K okunmuyor, rastgele dilimlere
/// benziyordu. Uçlar düz kesim (butt) — yuvarlak uç bu ağırlıkta yumuşatıyor.
func drawSlabK(_ context: CGContext, rect: CGRect, palette: Palette) {
    let unit = rect.width
    let weight = unit * 0.155
    // CoreGraphics'te y YUKARI artar: maxY üsttür.
    let yTop = rect.maxY - unit * 0.24
    let yBottom = rect.minY + unit * 0.24
    let left = rect.minX + unit * 0.30
    let right = rect.maxX - unit * 0.26
    let middle = (yTop + yBottom) / 2
    // Kollar gövdenin İÇİNDEN başlar, dikişi kapatır.
    let joint = CGPoint(x: left + weight * 0.30, y: middle)

    context.setLineCap(.butt)
    context.setLineJoin(.miter)
    context.setLineWidth(weight)

    context.setStrokeColor(palette.mark.cgColor)
    context.move(to: CGPoint(x: left + weight / 2, y: yTop))
    context.addLine(to: CGPoint(x: left + weight / 2, y: yBottom))
    context.strokePath()

    context.move(to: joint)
    context.addLine(to: CGPoint(x: right, y: yTop))
    context.strokePath()

    // Alt kol vurgu renginde: tek blok olmaktan kurtarır ve harfin yönünü verir.
    context.setStrokeColor(palette.accent.cgColor)
    context.move(to: joint)
    context.addLine(to: CGPoint(x: right, y: yBottom))
    context.strokePath()
}

/// Varyant B — tek çizgi K.
/// Yuvarlak uçlu kalın çizgiler; daha hafif, sistem simgeleriyle akraba.
func drawMonolineK(_ context: CGContext, rect: CGRect, palette: Palette) {
    let unit = rect.width
    let width = unit * 0.115
    let left = rect.minX + unit * 0.34
    let yTop = rect.maxY - unit * 0.26
    let yBottom = rect.minY + unit * 0.26
    let right = rect.maxX - unit * 0.28
    let middle = (yTop + yBottom) / 2

    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(width)

    context.setStrokeColor(palette.mark.cgColor)
    context.move(to: CGPoint(x: left, y: yTop))
    context.addLine(to: CGPoint(x: left, y: yBottom))
    context.strokePath()

    context.move(to: CGPoint(x: right, y: yTop))
    context.addLine(to: CGPoint(x: left + width * 0.35, y: middle))
    context.strokePath()

    context.setStrokeColor(palette.accent.cgColor)
    context.move(to: CGPoint(x: left + width * 0.35, y: middle))
    context.addLine(to: CGPoint(x: right, y: yBottom))
    context.strokePath()
}

/// Varyant C — negatif K.
/// İşaret boyanmaz, zeminden OYULUR. Rozet dolu bir renk lekesi olduğu için
/// Dock'ta uzaktan da seçiliyor; harf yaklaşınca okunuyor.
func drawNegativeK(_ context: CGContext, rect: CGRect, palette: Palette) {
    let unit = rect.width
    let badge = rect.insetBy(dx: unit * 0.17, dy: unit * 0.17)

    context.saveGState()
    let colors = [palette.mark.cgColor, palette.accent.cgColor] as CFArray
    context.addPath(CGPath(ellipseIn: badge, transform: nil))
    context.clip()
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: colors, locations: [0, 1]) {
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: badge.minX, y: badge.maxY),
                                   end: CGPoint(x: badge.maxX, y: badge.minY),
                                   options: [])
    }
    context.restoreGState()

    // Harf, zemin rengiyle oyuluyor.
    let stem = unit * 0.085
    let left = rect.minX + unit * 0.38
    let yTop = rect.maxY - unit * 0.33
    let yBottom = rect.minY + unit * 0.33
    let right = rect.maxX - unit * 0.34
    let middle = (yTop + yBottom) / 2

    context.saveGState()
    context.setBlendMode(.destinationOut)
    context.setLineCap(.butt)
    context.setLineJoin(.miter)
    context.setLineWidth(stem)
    context.setStrokeColor(NSColor.black.cgColor)

    context.move(to: CGPoint(x: left, y: yTop))
    context.addLine(to: CGPoint(x: left, y: yBottom))
    context.strokePath()
    context.move(to: CGPoint(x: right, y: yTop))
    context.addLine(to: CGPoint(x: left + stem * 0.35, y: middle))
    context.addLine(to: CGPoint(x: right, y: yBottom))
    context.strokePath()
    context.restoreGState()
}

/// Menü çubuğu şablonu.
///
/// Zemin YOK, renk YOK: macOS şablon görüntüyü kendi boyar (açık menü çubuğunda
/// siyah, koyuda beyaz, tıklanınca vurgulu). Renkli bir PNG koyarsak menü
/// çubuğu koyu temaya geçtiğinde ikon görünmez olur.
///
/// Çizim uygulama ikonuyla aynı K, ama daha kalın: 18 punto yükseklikte ince
/// çizgiler kayboluyor. Alt kol vurgu rengini kaybettiği için gövdeden bir
/// boşlukla ayrılıyor — renk olmadan yönü ancak boşluk veriyor.
func drawMenuBarK(_ context: CGContext, rect: CGRect) {
    let unit = rect.width
    let weight = unit * 0.20
    let yTop = rect.maxY - unit * 0.10
    let yBottom = rect.minY + unit * 0.10
    let left = rect.minX + unit * 0.14
    let right = rect.maxX - unit * 0.10
    let middle = (yTop + yBottom) / 2

    context.setFillColor(NSColor.black.cgColor)
    context.setStrokeColor(NSColor.black.cgColor)
    context.setLineCap(.butt)
    context.setLineJoin(.miter)
    context.setLineWidth(weight)

    context.move(to: CGPoint(x: left + weight / 2, y: yTop))
    context.addLine(to: CGPoint(x: left + weight / 2, y: yBottom))
    context.strokePath()

    // Kollar gövdeye değmiyor: şablonda her şey tek renk, bitişik olsalardı
    // bu boyutta tek bir leke olurlardı.
    let joint = CGPoint(x: left + weight * 1.15, y: middle)
    context.move(to: joint)
    context.addLine(to: CGPoint(x: right, y: yTop - weight * 0.1))
    context.strokePath()
    context.move(to: joint)
    context.addLine(to: CGPoint(x: right, y: yBottom + weight * 0.1))
    context.strokePath()
}

// MARK: Sürücü

let arguments = CommandLine.arguments
guard arguments.count >= 4 else {
    FileHandle.standardError.write("kullanım: make-icon.swift <slab|monoline|negative>:<brass|ink|mono> <boyut> <çıktı>\n".data(using: .utf8)!)
    exit(1)
}
let spec = arguments[1].split(separator: ":")
let variant = String(spec[0])
let paletteName = spec.count > 1 ? String(spec[1]) : "brass"
let size = Int(arguments[2]) ?? 1024
let output = arguments[3]

guard let palette = palettes[paletteName] else {
    FileHandle.standardError.write("bilinmeyen palet: \(paletteName)\n".data(using: .utf8)!)
    exit(1)
}

guard let context = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}

let canvas = CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size))
let inset = CGFloat(size) * (1 - contentRatio) / 2
let content = canvas.insetBy(dx: inset, dy: inset)

context.setAllowsAntialiasing(true)
context.interpolationQuality = .high

// Menü çubuğu şablonu tuvalin tamamını kullanır: Apple'ın gölge payı
// uygulama ikonu içindir, menü çubuğunda o boşluk ikonu küçültür.
if variant == "menubar" {
    drawMenuBarK(context, rect: canvas.insetBy(dx: CGFloat(size) * 0.06,
                                               dy: CGFloat(size) * 0.06))
    guard let image = context.makeImage(),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        exit(1)
    }
    try data.write(to: URL(fileURLWithPath: output))
    exit(0)
}

drawBackground(context, rect: content, palette: palette)

switch variant {
case "slab": drawSlabK(context, rect: content, palette: palette)
case "monoline": drawMonolineK(context, rect: content, palette: palette)
case "negative": drawNegativeK(context, rect: content, palette: palette)
default:
    FileHandle.standardError.write("bilinmeyen varyant: \(variant)\n".data(using: .utf8)!)
    exit(1)
}

guard let image = context.makeImage() else { exit(1) }
let bitmap = NSBitmapImageRep(cgImage: image)
guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: output))
