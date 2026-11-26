import CoreGraphics
import Foundation

/// Backlight control for panels macOS drives itself: the built-in display and
/// Apple's own external ones.
///
/// There is no public API for this. `DisplayServices` is the private framework
/// the brightness keys and System Settings go through, so the value read here is
/// the same one the system shows. It is loaded with `dlopen` rather than linked:
/// a private framework that moves or loses a symbol should cost one feature, not
/// stop the app from launching.
enum SystemBrightness {

    private typealias Getter = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Setter = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let symbols: (get: Getter, set: Setter)? = {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_NOW),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness")
        else { return nil }
        return (unsafeBitCast(get, to: Getter.self), unsafeBitCast(set, to: Setter.self))
    }()

    /// 0…1, or nil when the system does not own this panel's backlight — which
    /// is the answer for every third-party monitor.
    static func get(_ displayID: CGDirectDisplayID) -> Double? {
        guard let symbols else { return nil }
        var value: Float = 0
        guard symbols.get(displayID, &value) == 0 else { return nil }
        return Double(value)
    }

    @discardableResult
    static func set(_ displayID: CGDirectDisplayID, _ value: Double) -> Bool {
        guard let symbols else { return false }
        return symbols.set(displayID, Float(min(max(value, 0), 1))) == 0
    }
}
