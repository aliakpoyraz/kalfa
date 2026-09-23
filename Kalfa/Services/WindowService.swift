import AppKit
import ApplicationServices

/// Puts the frontmost window where you point it: halves, quarters, centre, full.
///
/// Done through the accessibility API, which is the only way one app may move
/// another's window — and the permission smooth scrolling already asks for.
@MainActor
enum WindowService {

    enum Slot {
        case left, right, top, bottom
        case topLeft, topRight, bottomLeft, bottomRight
        case center, full

        /// Fractions of the screen's usable area, in AppKit's bottom-left space.
        func frame(in area: CGRect) -> CGRect {
            let halfWidth = area.width / 2
            let halfHeight = area.height / 2
            switch self {
            case .left:
                return CGRect(x: area.minX, y: area.minY, width: halfWidth, height: area.height)
            case .right:
                return CGRect(x: area.midX, y: area.minY, width: halfWidth, height: area.height)
            case .top:
                return CGRect(x: area.minX, y: area.midY, width: area.width, height: halfHeight)
            case .bottom:
                return CGRect(x: area.minX, y: area.minY, width: area.width, height: halfHeight)
            case .topLeft:
                return CGRect(x: area.minX, y: area.midY, width: halfWidth, height: halfHeight)
            case .topRight:
                return CGRect(x: area.midX, y: area.midY, width: halfWidth, height: halfHeight)
            case .bottomLeft:
                return CGRect(x: area.minX, y: area.minY, width: halfWidth, height: halfHeight)
            case .bottomRight:
                return CGRect(x: area.midX, y: area.minY, width: halfWidth, height: halfHeight)
            case .center:
                let width = area.width * 0.6
                let height = area.height * 0.8
                return CGRect(
                    x: area.midX - width / 2,
                    y: area.midY - height / 2,
                    width: width,
                    height: height
                )
            case .full:
                return area
            }
        }
    }

    @discardableResult
    static func place(_ slot: Slot) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let element = AXUIElementCreateApplication(app.processIdentifier)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let window = value, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return false }

        let axWindow = unsafeBitCast(window, to: AXUIElement.self)
        guard let screen = screenForWindow(axWindow) ?? NSScreen.main else { return false }

        let target = slot.frame(in: screen.visibleFrame)
        return apply(target, to: axWindow)
    }

    // MARK: Geometry

    /// Accessibility works in a flipped, screen-spanning space whose origin is
    /// the top-left of the *primary* display; AppKit's is the bottom-left. Every
    /// window on a second display lands somewhere absurd without this.
    private static func flip(_ rect: CGRect) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? rect.maxY
        return CGPoint(x: rect.minX, y: primaryHeight - rect.maxY)
    }

    private static func apply(_ frame: CGRect, to window: AXUIElement) -> Bool {
        var origin = flip(frame)
        var size = CGSize(width: frame.width, height: frame.height)

        guard let positionValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size)
        else { return false }

        // Size first, then position, then size again: a window that is currently
        // larger than the target refuses the move until it has shrunk, and one
        // with a minimum size clamps the first attempt.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        return result == .success
    }

    private static func screenForWindow(_ window: AXUIElement) -> NSScreen? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }

        var point = CGPoint.zero
        AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgPoint, &point)

        // Back to AppKit's space to ask which screen holds it.
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let appKitPoint = CGPoint(x: point.x, y: primaryHeight - point.y)
        return NSScreen.screens.first { $0.frame.contains(appKitPoint) }
    }
}
