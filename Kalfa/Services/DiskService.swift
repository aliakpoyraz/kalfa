import AppKit
import Foundation

/// Ejecting external volumes.
@MainActor
enum DiskService {

    struct Volume: Identifiable, Hashable {
        let url: URL
        let name: String
        var id: URL { url }
    }

    /// Removable and external volumes only — never the startup disk, and never a
    /// network share, which "eject" would drop mid-copy.
    static func ejectable() -> [Volume] {
        let keys: [URLResourceKey] = [
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeIsInternalKey,
            .volumeIsLocalKey,
            .volumeNameKey,
        ]
        let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        return mounted.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsLocal == true,
                  values.volumeIsInternal != true,
                  values.volumeIsRemovable == true || values.volumeIsEjectable == true
            else { return nil }
            return Volume(url: url, name: values.volumeName ?? url.lastPathComponent)
        }
    }

    /// Returns the volumes that refused to go — almost always because something
    /// still has a file open on them, which is exactly what the user needs told.
    @discardableResult
    static func ejectAll() -> [String] {
        var failed: [String] = []
        for volume in ejectable() {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
            } catch {
                failed.append(volume.name)
                Log.display.notice("eject refused: \(volume.name, privacy: .public)")
            }
        }
        return failed
    }
}
