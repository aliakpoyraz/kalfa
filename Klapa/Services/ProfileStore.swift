import Foundation
import Observation

/// Persists profiles to `~/Library/Application Support/Klapa/profiles.json`.
///
/// Plain JSON on purpose: these records are worth inspecting by hand when a
/// display setup misbehaves, and worth copying between machines.
@MainActor
@Observable
final class ProfileStore {

    private(set) var profiles: [Profile] = []

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    // MARK: Queries

    /// Profiles that match a connected set of displays, newest first.
    func profiles(for setKey: DisplaySetKey) -> [Profile] {
        profiles
            .filter { $0.setKey == setKey }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// The profile that should fire automatically for this arrangement, if any.
    func autoApplyProfile(for setKey: DisplaySetKey) -> Profile? {
        profiles(for: setKey).first { $0.autoApply }
    }

    // MARK: Mutation

    func add(_ profile: Profile) {
        profiles.append(profile)
        normalizeAutoApply(around: profile)
        save()
    }

    func update(_ profile: Profile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        normalizeAutoApply(around: profile)
        save()
    }

    func remove(_ profile: Profile) {
        profiles.removeAll { $0.id == profile.id }
        save()
    }

    func rename(_ profile: Profile, to name: String) {
        var copy = profile
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !copy.name.isEmpty else { return }
        update(copy)
    }

    /// At most one auto-applying profile per arrangement, otherwise two profiles
    /// would fight over the same reconfiguration event.
    private func normalizeAutoApply(around profile: Profile) {
        guard profile.autoApply else { return }
        for index in profiles.indices
        where profiles[index].setKey == profile.setKey && profiles[index].id != profile.id {
            profiles[index].autoApply = false
        }
    }

    // MARK: Storage

    private static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
        return base
            .appendingPathComponent("Klapa", isDirectory: true)
            .appendingPathComponent("profiles.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            profiles = try decoder.decode([Profile].self, from: data)
        } catch {
            Log.profile.error("profiles.json unreadable: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        let snapshot = profiles
        let url = fileURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(to: url, options: .atomic)
        } catch {
            Log.profile.error("profiles.json unwritable: \(error.localizedDescription, privacy: .public)")
        }
    }
}
