import CoreGraphics
import Foundation

/// Text dump of the current display state, for `--dump`.
///
/// Deliberately prints the IOKit flags: when a monitor "looks wrong" after a
/// reconfiguration the cause is almost always an active mode that is not the
/// panel's native timing, and that is invisible in System Settings.
enum Diagnostics {

    static func dump() {
        let screens = ScreenInfo.online()
        // DDC is the part most likely to be silently broken on a given machine,
        // so the dump probes it rather than only describing what should happen.
        let ddc = probeDDC(screens)

        print("Kalfa — display dump")
        print("Layout key: \(DisplaySetKey(screens))")
        print("Lid closed: \(screens.contains(where: \.isBuiltIn) ? "no" : "yes")")
        print("")

        for screen in screens {
            print("\(screen.name)")
            print("  displayID   \(screen.displayID)")
            print("  uuid        \(screen.uuid)")
            print("  built-in    \(screen.isBuiltIn ? "yes" : "no")")
            print("  main        \(screen.isMain ? "yes" : "no")")
            print("  vendor/model 0x\(String(screen.vendorID, radix: 16))/0x\(String(screen.modelID, radix: 16))")

            if let current = ModeService.current(for: screen.displayID) {
                print("  active mode \(describe(current))")
                if !current.isNativeTiming {
                    print("  !! active mode is not the panel's native timing — macOS synthesized it")
                }
            }
            if let native = ModeService.nativeMode(for: screen.displayID) {
                print("  native mode \(describe(native))")
            }

            if screen.supportsDDC {
                print("  DDC         \(ddc[screen.displayID] ?? "no response")")
            }

            let setKey = DisplaySetKey(screens)
            if let link = LinkInfo.link(for: screen.uuid, in: setKey) {
                print("  link        \(link.label)")
            }
            if let bits = LinkInfo.framebufferBitsPerChannel(for: screen.displayID) {
                print("  framebuffer \(bits)-bit per channel")
            }

            let modes = ModeService.modes(for: screen.displayID)
            print("  \(modes.count) modes:")
            for mode in modes {
                print("    \(describe(mode))")
            }
            print("")
        }
    }

    /// Blocks on each DDC round trip deliberately: `--dump` is a one-shot command
    /// with no run loop to await on.
    private static func probeDDC(_ screens: [ScreenInfo]) -> [CGDirectDisplayID: String] {
        guard DDCService.shared.isSupported else { return [:] }

        var result: [CGDirectDisplayID: String] = [:]

        for screen in screens where screen.supportsDDC {
            let box = Box()
            let semaphore = DispatchSemaphore(value: 0)
            let displayID = screen.displayID

            Task.detached {
                let brightness = await DDCService.shared.read(.brightness, from: displayID)
                let contrast = await DDCService.shared.read(.contrast, from: displayID)

                var parts: [String] = []
                if let brightness {
                    parts.append("brightness \(brightness.percent)% (\(brightness.current)/\(brightness.max))")
                }
                if let contrast {
                    parts.append("contrast \(contrast.percent)% (\(contrast.current)/\(contrast.max))")
                }
                box.value = parts.isEmpty ? "no response" : parts.joined(separator: ", ")
                semaphore.signal()
            }

            if semaphore.wait(timeout: .now() + 5) == .timedOut {
                result[displayID] = "timed out"
            } else {
                result[displayID] = box.value
            }
        }

        return result
    }

    /// Carries one string across the async boundary without tripping the
    /// concurrency checker.
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = "no response"

        var value: String {
            get { lock.lock(); defer { lock.unlock() }; return storage }
            set { lock.lock(); storage = newValue; lock.unlock() }
        }
    }

    private static func describe(_ mode: ScreenMode) -> String {
        var flags: [String] = []
        if mode.isHiDPI { flags.append("HiDPI") }
        if mode.isNativeTiming { flags.append("native") }
        if mode.isHidden { flags.append("hidden") }
        if mode.isExtended { flags.append("skylight-only") }
        if mode.isStretched { flags.append("stretched") }
        if !mode.isSafe { flags.append("unverified") }

        let size = "\(mode.resolutionLabel) (\(mode.pixelLabel) px)".padding(
            toLength: 34, withPad: " ", startingAt: 0
        )
        let rate = mode.refreshLabel.padding(toLength: 8, withPad: " ", startingAt: 0)
        return "\(size) \(rate) [\(flags.joined(separator: ","))] id=\(mode.id)"
    }
}
