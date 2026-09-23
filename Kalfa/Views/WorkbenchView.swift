import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WorkbenchWindowView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("tools.window.title"))
                    .font(.title3.weight(.semibold))
                Text(L10n.t("tools.window.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            WorkbenchView()
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(minWidth: 440, minHeight: 280)
        .background(.ultraThinMaterial)
    }
}

struct WorkbenchView: View {
    private enum Item {
        case image(URL), video(URL), text(String), link(URL)

        var title: String {
            switch self {
            case .image(let url), .video(let url): return url.lastPathComponent
            case .text: return L10n.t("tools.text")
            case .link(let url): return url.host ?? url.absoluteString
            }
        }

        var icon: String {
            switch self {
            case .image: return "photo"
            case .video: return "film"
            case .text: return "text.alignleft"
            case .link: return "link"
            }
        }
    }

    @State private var item: Item?
    @State private var importing = false
    @State private var working = false
    @State private var message: String?
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.t("tools.title"))
                    .font(.caption.weight(.semibold))
                Spacer()
                if item != nil {
                    Button(L10n.t("tools.clear")) { item = nil; message = nil }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                }
            }

            if let item {
                selected(item)
            } else {
                dropZone
            }

            if let message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.image, .movie],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first { accept(url) }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 7) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.title3)
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
            Text(L10n.t("tools.drop"))
                .font(.caption.weight(.medium))
            Text(L10n.t("tools.drop.detail"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Button(L10n.t("tools.choose")) { importing = true }
                Button(L10n.t("tools.paste")) { paste() }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            (isTargeted ? Color.accentColor : Color.secondary).opacity(isTargeted ? 0.1 : 0.035),
            in: RoundedRectangle(cornerRadius: KalfaDesign.cardRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: KalfaDesign.cardRadius)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            accept(url)
            return true
        } isTargeted: { isTargeted = $0 }
        .dropDestination(for: String.self) { strings, _ in
            guard let text = strings.first else { return false }
            accept(text)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private func selected(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                Text(item.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer()
                if working { ProgressView().controlSize(.small) }
            }

            FlowLayout(spacing: 6) {
                switch item {
                case .image(let url):
                    toolButton(L10n.t("tools.image.resize"), "arrow.down.right.and.arrow.up.left") {
                        try LocalToolService.resizedImage(at: url)
                    }
                    toolButton(L10n.t("tools.image.png"), "photo.badge.arrow.down") {
                        try LocalToolService.convertedToPNG(at: url)
                    }
                    toolButton(L10n.t("tools.image.background"), "person.crop.rectangle.badge.minus") {
                        try LocalToolService.removeBackground(at: url)
                    }
                case .video(let url):
                    asyncToolButton(L10n.t("tools.video.compress"), "arrow.down.circle") {
                        try await LocalToolService.compressVideo(at: url)
                    }
                    asyncToolButton(L10n.t("tools.video.audio"), "waveform") {
                        try await LocalToolService.extractAudio(at: url)
                    }
                case .text(let text):
                    textButton(L10n.t("tools.text.correct"), "checkmark.seal") {
                        LocalToolService.corrected(text)
                    }
                    textButton(L10n.t("tools.text.summary"), "text.badge.minus") {
                        LocalToolService.summary(of: text)
                    }
                    Button {
                        translate(text)
                    } label: { Label(L10n.t("tools.text.translate"), systemImage: "character.bubble") }
                        .disabled(working)
                case .link(let url):
                    toolButton(L10n.t("tools.link.save"), "bookmark") {
                        try LocalToolService.saveLink(url)
                    }
                    asyncToolButton(L10n.t("tools.link.download"), "arrow.down.circle") {
                        try await LocalToolService.download(url)
                    }
                    Button {
                        working = true
                        Task {
                            do {
                                let summary = try await LocalToolService.summarizeLink(url)
                                LocalToolService.copy(summary)
                                message = L10n.t("tools.result.copied")
                            } catch { message = error.localizedDescription }
                            working = false
                        }
                    } label: { Label(L10n.t("tools.link.summary"), systemImage: "text.badge.minus") }
                        .disabled(working)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .kalfaSurface(tint: .accentColor)
    }

    private func toolButton(_ title: String, _ icon: String, operation: @escaping () throws -> URL) -> some View {
        Button {
            working = true
            Task {
                do { reveal(try operation()) } catch { message = error.localizedDescription }
                working = false
            }
        } label: { Label(title, systemImage: icon) }
            .disabled(working)
    }

    private func asyncToolButton(_ title: String, _ icon: String, operation: @escaping () async throws -> URL) -> some View {
        Button {
            working = true
            Task {
                do { reveal(try await operation()) } catch { message = error.localizedDescription }
                working = false
            }
        } label: { Label(title, systemImage: icon) }
            .disabled(working)
    }

    private func textButton(_ title: String, _ icon: String, operation: @escaping () -> String) -> some View {
        Button {
            LocalToolService.copy(operation())
            message = L10n.t("tools.result.copied")
        } label: { Label(title, systemImage: icon) }
    }

    private func accept(_ url: URL) {
        if url.isFileURL {
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            if type?.conforms(to: .image) == true { item = .image(url) }
            else if type?.conforms(to: .movie) == true { item = .video(url) }
            else { message = L10n.t("tools.error.unsupported") }
        } else {
            item = .link(url)
        }
    }

    private func accept(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https"].contains(scheme) {
            item = .link(url)
        } else if !trimmed.isEmpty {
            item = .text(trimmed)
        }
    }

    private func paste() {
        if let url = NSPasteboard.general.readObjects(forClasses: [NSURL.self])?.first as? URL {
            accept(url)
        } else if let text = NSPasteboard.general.string(forType: .string) {
            accept(text)
        } else {
            message = L10n.t("tools.error.clipboard")
        }
    }

    private func reveal(_ url: URL) {
        message = L10n.t("tools.result.saved", url.lastPathComponent)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func translate(_ text: String) {
        var components = URLComponents(string: "https://translate.google.com/")!
        components.queryItems = [
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: translationTarget),
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "op", value: "translate"),
        ]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    private var translationTarget: String {
        if let prefersTurkish = L10n.language.prefersTurkish {
            return prefersTurkish ? "tr" : "en"
        }
        return Locale.preferredLanguages.first?.hasPrefix("tr") == true ? "tr" : "en"
    }
}

/// Compact wrapping layout for a variable number of action buttons.
private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var points: [CGPoint] = []
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}
