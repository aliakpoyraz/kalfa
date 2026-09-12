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

        print("Klapa — ekran dökümü")
        print("Dizilim anahtarı: \(DisplaySetKey(screens))")
        print("Kapak kapalı: \(screens.contains(where: \.isBuiltIn) ? "hayır" : "evet")")
        print("")

        for screen in screens {
            print("\(screen.name)")
            print("  displayID   \(screen.displayID)")
            print("  uuid        \(screen.uuid)")
            print("  dahili      \(screen.isBuiltIn ? "evet" : "hayır")")
            print("  ana ekran   \(screen.isMain ? "evet" : "hayır")")
            print("  vendor/model 0x\(String(screen.vendorID, radix: 16))/0x\(String(screen.modelID, radix: 16))")

            if let current = ModeService.current(for: screen.displayID) {
                print("  aktif mod   \(describe(current))")
                if !current.isNativeTiming {
                    print("  !! aktif mod EDID yerel zamanlaması değil — macOS türetti")
                }
            }
            if let native = ModeService.nativeMode(for: screen.displayID) {
                print("  yerel mod   \(describe(native))")
            }

            if screen.supportsDDC {
                print("  DDC         \(ddc[screen.displayID] ?? "yanıt yok")")
            }

            let modes = ModeService.modes(for: screen.displayID)
            print("  \(modes.count) mod:")
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
                    parts.append("parlaklık \(brightness.percent)% (\(brightness.current)/\(brightness.max))")
                }
                if let contrast {
                    parts.append("kontrast \(contrast.percent)% (\(contrast.current)/\(contrast.max))")
                }
                box.value = parts.isEmpty ? "yanıt yok" : parts.joined(separator: ", ")
                semaphore.signal()
            }

            if semaphore.wait(timeout: .now() + 5) == .timedOut {
                result[displayID] = "zaman aşımı"
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
        private var storage = "yanıt yok"

        var value: String {
            get { lock.lock(); defer { lock.unlock() }; return storage }
            set { lock.lock(); storage = newValue; lock.unlock() }
        }
    }

    private static func describe(_ mode: ScreenMode) -> String {
        var flags: [String] = []
        if mode.isHiDPI { flags.append("HiDPI") }
        if mode.isNativeTiming { flags.append("yerel") }
        if mode.isHidden { flags.append("gösterilmez") }
        if mode.isExtended { flags.append("yalnız-SkyLight") }
        if mode.isStretched { flags.append("gerilmiş") }
        if !mode.isSafe { flags.append("güvensiz") }

        let size = "\(mode.resolutionLabel) (\(mode.pixelLabel) px)".padding(
            toLength: 34, withPad: " ", startingAt: 0
        )
        let rate = mode.refreshLabel.padding(toLength: 8, withPad: " ", startingAt: 0)
        return "\(size) \(rate) [\(flags.joined(separator: ","))] id=\(mode.id)"
    }
}
