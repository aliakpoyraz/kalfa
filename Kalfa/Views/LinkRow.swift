import SwiftUI
import KalfaUI

/// What the cable is actually carrying.
///
/// Read-only on purpose. A monitor running YCbCr 4:2:2 has half its horizontal
/// colour resolution thrown away and text softens accordingly, but macOS
/// negotiates the link format itself and exposes no supported way to change it —
/// not through CoreGraphics, not through SkyLight, not over DDC. Showing the
/// value at least turns an unexplained blur into a known cause.
struct LinkRow: View {

    @Environment(DisplayCenter.self) private var center
    let screen: ScreenInfo

    var body: some View {
        if let text = summary {
            KalfaSettingRow(L10n.t("link"), detail: text, help: L10n.t("link.help")) {
                if link?.colorFormat?.isSubsampled == true {
                    KalfaBadge(L10n.t("grid.fractional"), tone: .warn)
                        .help(L10n.t(
                            "link.subsampled.help",
                            link?.colorFormat?.label ?? ""
                        ))
                }
            } control: {
                EmptyView()
            }
        }
    }

    private var link: LinkInfo.Link? {
        LinkInfo.link(for: screen.uuid, in: center.setKey)
    }

    private var summary: String? {
        let framebuffer = LinkInfo.framebufferBitsPerChannel(for: screen.displayID)
        switch (link, framebuffer) {
        case let (link?, bits?):
            return "\(link.label) · \(L10n.t("link.framebuffer", bits))"
        case let (link?, nil):
            return link.label
        case let (nil, bits?):
            return L10n.t("link.framebuffer", bits)
        default:
            return nil
        }
    }
}
