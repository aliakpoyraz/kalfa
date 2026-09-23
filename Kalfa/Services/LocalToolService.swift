import AppKit
import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

enum LocalToolService {
    enum ToolError: LocalizedError {
        case unreadable, unsupported, failed(String)
        var errorDescription: String? {
            switch self {
            case .unreadable: return L10n.t("tools.error.unreadable")
            case .unsupported: return L10n.t("tools.error.unsupported")
            case .failed(let message): return message
            }
        }
    }

    static func resizedImage(at source: URL) throws -> URL {
        guard let image = NSImage(contentsOf: source),
              let input = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { throw ToolError.unreadable }
        let width = max(input.width / 2, 1)
        let height = max(input.height / 2, 1)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ToolError.unreadable }
        context.interpolationQuality = .high
        context.draw(input, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let output = context.makeImage() else { throw ToolError.unreadable }
        let url = sibling(of: source, suffix: "-50", extension: "png")
        try write(output, to: url, type: .png)
        return url
    }

    static func convertedToPNG(at source: URL) throws -> URL {
        guard let image = NSImage(contentsOf: source),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { throw ToolError.unreadable }
        let url = sibling(of: source, suffix: "-converted", extension: "png")
        try write(cgImage, to: url, type: .png)
        return url
    }

    static func removeBackground(at source: URL) throws -> URL {
        guard let image = NSImage(contentsOf: source),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { throw ToolError.unreadable }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])
        guard let observation = request.results?.first else { throw ToolError.unsupported }
        let maskBuffer = try observation.generateScaledMaskForImage(
            forInstances: observation.allInstances, from: handler
        )
        let original = CIImage(cgImage: cgImage)
        let transparent = CIImage(color: .clear).cropped(to: original.extent)
        let mask = CIImage(cvPixelBuffer: maskBuffer)
        guard let filter = CIFilter(name: "CIBlendWithMask") else { throw ToolError.unsupported }
        filter.setValue(original, forKey: kCIInputImageKey)
        filter.setValue(transparent, forKey: kCIInputBackgroundImageKey)
        filter.setValue(mask, forKey: kCIInputMaskImageKey)
        guard let result = filter.outputImage,
              let output = CIContext().createCGImage(result, from: original.extent)
        else { throw ToolError.unreadable }
        let url = sibling(of: source, suffix: "-background-removed", extension: "png")
        try write(output, to: url, type: .png)
        return url
    }

    static func compressVideo(at source: URL) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality)
        else { throw ToolError.unsupported }
        let output = sibling(of: source, suffix: "-compressed", extension: "mp4")
        try? FileManager.default.removeItem(at: output)
        session.outputURL = output
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        try await export(session)
        return output
    }

    static func extractAudio(at source: URL) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
        else { throw ToolError.unsupported }
        let output = sibling(of: source, suffix: "-audio", extension: "m4a")
        try? FileManager.default.removeItem(at: output)
        session.outputURL = output
        session.outputFileType = .m4a
        try await export(session)
        return output
    }

    static func corrected(_ text: String) -> String {
        var result = text
        let checker = NSSpellChecker.shared
        var offset = 0
        while offset < (result as NSString).length {
            let range = checker.checkSpelling(
                of: result, startingAt: offset, language: nil, wrap: false,
                inSpellDocumentWithTag: 0, wordCount: nil
            )
            guard range.location != NSNotFound else { break }
            if let replacement = checker.guesses(forWordRange: range, in: result, language: nil, inSpellDocumentWithTag: 0)?.first {
                result = (result as NSString).replacingCharacters(in: range, with: replacement)
                offset = range.location + (replacement as NSString).length
            } else {
                offset = range.location + range.length
            }
        }
        return result
    }

    static func summary(of text: String) -> String {
        let sentences = text.split(whereSeparator: { ".!?\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard sentences.count > 3 else { return text }
        let words = text.lowercased().split { !$0.isLetter }.filter { $0.count > 3 }
        var frequencies: [String: Int] = [:]
        for word in words { frequencies[String(word), default: 0] += 1 }
        let ranked: [(index: Int, sentence: String, score: Int)] = sentences.enumerated().map { index, sentence in
            let score = sentence.lowercased().split { !$0.isLetter }
                .reduce(0) { $0 + (frequencies[String($1)] ?? 0) }
            return (index, sentence, score)
        }
        let wanted = max(2, min(5, sentences.count / 3))
        let strongest = Array(ranked.sorted { $0.score > $1.score }.prefix(wanted))
        let ordered = strongest.sorted { $0.index < $1.index }
        return ordered.map { $0.sentence + "." }.joined(separator: " ")
    }

    static func saveLink(_ url: URL) throws -> URL {
        let output = downloads.appendingPathComponent(safeName(url.host ?? "link")).appendingPathExtension("webloc")
        let plist: [String: String] = ["URL": url.absoluteString]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: output, options: .atomic)
        return output
    }

    static func download(_ url: URL) async throws -> URL {
        let (temporary, response) = try await URLSession.shared.download(from: url)
        let suggested = response.suggestedFilename ?? url.lastPathComponent
        let name = suggested.isEmpty ? "download" : suggested
        let output = uniqueURL(downloads.appendingPathComponent(name))
        try FileManager.default.moveItem(at: temporary, to: output)
        return output
    }

    static func summarizeLink(_ url: URL) async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else { throw ToolError.unreadable }
        let plain = html
            .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
        return summary(of: plain)
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static var downloads: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }

    private static func sibling(of source: URL, suffix: String, extension ext: String) -> URL {
        let name = source.deletingPathExtension().lastPathComponent + suffix
        return uniqueURL(source.deletingLastPathComponent().appendingPathComponent(name).appendingPathExtension(ext))
    }

    private static func uniqueURL(_ candidate: URL) -> URL {
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        for index in 2...999 {
            let url = candidate.deletingLastPathComponent()
                .appendingPathComponent("\(base)-\(index)").appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return candidate
    }

    private static func safeName(_ value: String) -> String {
        value.replacingOccurrences(of: "[^a-zA-Z0-9.-]", with: "-", options: .regularExpression)
    }

    private static func write(_ image: CGImage, to url: URL, type: UTType) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw ToolError.unreadable }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ToolError.unreadable }
    }

    private static func export(_ session: AVAssetExportSession) async throws {
        await session.export()
        if let error = session.error { throw error }
        guard session.status == .completed else { throw ToolError.failed(L10n.t("tools.error.export")) }
    }
}
