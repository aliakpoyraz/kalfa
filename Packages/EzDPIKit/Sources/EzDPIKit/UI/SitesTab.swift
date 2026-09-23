import SwiftUI

/// Site listesi. Kullanıcı yalnızca adres yazar ve gerekirse üç hazır
/// yöntemden birini seçer; parça boyutu gibi terimler "Gelişmiş" altında.
struct SitesTab: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var supervisor: Supervisor
    @EnvironmentObject var l10n: L10n
    @State private var selection: UUID?
    @State private var newDomain = ""

    private var selectedIndex: Int? {
        guard let selection else { return nil }
        return store.config.groups.firstIndex { $0.id == selection }
    }

    var body: some View {
        HSplitView {
            groupList.frame(minWidth: 180)
            detail.frame(minWidth: 400)
        }
        .onAppear { if selection == nil { selection = store.config.groups.first?.id } }
    }

    private var groupList: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(store.config.groups) { group in
                    HStack {
                        Image(systemName: group.enabled ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(group.enabled ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(group.name)
                            Text(T("\(group.domains.count) adres", "\(group.domains.count) addresses"))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .tag(group.id)
                }
            }
            HStack(spacing: 6) {
                Button { addGroup() } label: { Image(systemName: "plus") }
                Button { removeGroup() } label: { Image(systemName: "minus") }
                    .disabled(selectedIndex == nil)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let index = selectedIndex {
            let binding = $store.config.groups[index]
            Form {
                Section {
                    TextField(T("Liste adı", "List name"), text: binding.name)
                    Toggle(T("Bu liste kullanılsın", "Use this list"), isOn: binding.enabled)
                }

                Section {
                    HStack {
                        TextField(T("engellenen-site.com", "blocked-site.com"), text: $newDomain)
                            .onSubmit { addDomain(to: index) }
                        Button(T("Ekle", "Add")) { addDomain(to: index) }
                            .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ForEach(Array(binding.wrappedValue.domains.enumerated()), id: \.offset) { offset, domain in
                        HStack {
                            Text(domain)
                            Spacer()
                            Button {
                                store.config.groups[index].domains.remove(at: offset)
                                supervisor.applyConfigChange()
                            } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                        }
                    }
                    if binding.wrappedValue.domains.isEmpty {
                        Text(T("Henüz adres yok. Açılmayan sitenin adresini yaz, alt adresleri de kendiliğinden kapsanır.",
                               "No addresses yet. Type the site that will not open; its subdomains are covered too."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(T("Adresler", "Addresses"))
                }

                Section {
                    Picker(T("Yöntem", "Method"), selection: Binding(
                        get: { binding.wrappedValue.preset },
                        set: { newValue in
                            store.config.groups[index].apply(preset: newValue)
                            supervisor.applyConfigChange()
                        }
                    )) {
                        ForEach(BypassPreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    Text(binding.wrappedValue.preset.hint)
                        .font(.caption).foregroundStyle(.secondary)
                    Text(T("Site hâlâ açılmıyorsa sırayla diğer yöntemleri dene, sonra Test sekmesinden kontrol et.",
                           "If the site still will not open, try the other methods in order, then check the Test tab."))
                        .font(.caption).foregroundStyle(.secondary)

                    if store.config.settings.advancedMode {
                        Picker(T("Ad çözümleme", "Name resolution"), selection: binding.dnsMode) {
                            ForEach(DNSMode.allCases) { Text($0.label).tag($0) }
                        }
                        Picker(T("Parçalama", "Fragmentation"), selection: binding.splitMode) {
                            ForEach(SplitMode.selectable) { Text($0.label).tag($0) }
                        }
                        if binding.wrappedValue.splitMode == .chunk {
                            Stepper(T("Parça boyutu: \(binding.wrappedValue.chunkSize)",
                                      "Chunk size: \(binding.wrappedValue.chunkSize)"),
                                    value: binding.chunkSize, in: 1...100)
                        }
                        Button(T("Uygula", "Apply")) {
                            store.config.groups[index].preset = .custom
                            supervisor.applyConfigChange()
                        }
                    }
                } header: {
                    Text(T("Nasıl açılsın", "How to unblock"))
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(T("Bir liste seç", "Select a list"), systemImage: "globe")
        }
    }

    private func addGroup() {
        var group = DomainGroup(name: T("Yeni liste", "New list"),
                                priority: (store.config.groups.map(\.priority).max() ?? 10) + 10)
        group.apply(preset: .standard)
        store.config.groups.append(group)
        selection = group.id
    }

    private func removeGroup() {
        guard let index = selectedIndex else { return }
        store.config.groups.remove(at: index)
        selection = store.config.groups.first?.id
        supervisor.applyConfigChange()
    }

    private func addDomain(to index: Int) {
        let value = newDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return }
        // Kullanıcı tam adres yapıştırırsa şemayı ve yolu at.
        let cleaned = value
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .split(separator: "/").first.map(String.init) ?? value
        guard !store.config.groups[index].domains.contains(cleaned) else {
            newDomain = ""
            return
        }
        store.config.groups[index].domains.append(cleaned)
        newDomain = ""
        supervisor.applyConfigChange()
    }
}
