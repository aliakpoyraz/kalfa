import SwiftUI
import AppKit

struct AboutTab: View {
    @EnvironmentObject var l10n: L10n
    @State private var engineVersion = "…"

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text(T("Kalfa · DPI", "Kalfa · DPI")).font(.system(size: 22, weight: .semibold))
                    Text(T("Sürüm \(version)", "Version \(version)"))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(T("Engellenen siteleri açan, kendi kendine açılıp kapanan bölüm.",
                           "The half that opens blocked sites and turns itself on and off."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.bottom, 14)

            Form {
                Section {
                    LabeledContent(T("Kaynak kodu", "Source code")) {
                        Link("github.com/aliakpoyraz/klapa",
                             destination: URL(string: "https://github.com/aliakpoyraz/klapa")!)
                    }
                    LabeledContent(T("Sorun bildir", "Report an issue")) {
                        Link(T("GitHub Issues", "GitHub Issues"),
                             destination: URL(string: "https://github.com/aliakpoyraz/klapa/issues")!)
                    }
                    LabeledContent(T("Geliştirici", "Developer")) {
                        Link("aliakpoyraz.com", destination: URL(string: "https://aliakpoyraz.com")!)
                    }
                }

                Section {
                    LabeledContent(T("Motor", "Engine")) { Text(engineVersion) }
                    LabeledContent(T("Lisans", "License")) { Text("Apache-2.0") }
                    Link("github.com/xvzc/SpoofDPI",
                         destination: URL(string: "https://github.com/xvzc/SpoofDPI")!)
                    Text(T("Bağlantıyı açan motor spoofdpi. Kalfa onu paketler, kurallarla yönetir ve arayüz sağlar.",
                           "The underlying engine is spoofdpi. Kalfa bundles it, drives it with rules and adds the interface."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text(T("Kullanılan bileşen", "Bundled component"))
                }

                Section {
                    Button(T("Ayar klasörünü aç", "Open settings folder")) {
                        NSWorkspace.shared.selectFile(Paths.config.path,
                                                      inFileViewerRootedAtPath: Paths.support.path)
                    }
                    Button(T("Kayıt klasörünü aç", "Open log folder")) {
                        NSWorkspace.shared.selectFile(Paths.appLog.path,
                                                      inFileViewerRootedAtPath: Paths.logs.path)
                    }
                } header: {
                    Text(T("Dosyalar", "Files"))
                }
            }
            .formStyle(.grouped)
        }
        .padding(4)
        .task { engineVersion = Self.readEngineVersion() }
    }

    /// Gömülü motorun sürümünü ikilinin kendisinden sorar.
    private static func readEngineVersion() -> String {
        guard let binary = Paths.bundledEngine else { return "—" }
        let result = Shell.run(binary.path, ["--version"], timeout: 5)
        let first = result.stdout.split(separator: "\n").first.map(String.init) ?? ""
        return first.isEmpty ? "—" : first
    }
}
