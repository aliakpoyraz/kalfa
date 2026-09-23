import SwiftUI
import AppKit

/// "Ne zaman açılsın" sekmesi. Kural kavramı kullanıcıya cümle olarak
/// sunuluyor: bir uygulama açıkken, bir ağdayken ya da belirli saatlerde.
struct WhenTab: View {
    @EnvironmentObject var store: ConfigStore
    @EnvironmentObject var supervisor: Supervisor
    @EnvironmentObject var l10n: L10n
    @State private var selection: UUID?

    private var selectedIndex: Int? {
        guard let selection else { return nil }
        return store.config.rules.firstIndex { $0.id == selection }
    }

    var body: some View {
        HSplitView {
            list.frame(minWidth: 210)
            detail.frame(minWidth: 370)
        }
        .onAppear { if selection == nil { selection = store.config.rules.first?.id } }
    }

    private var list: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(store.config.rules) { rule in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Image(systemName: rule.enabled ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(rule.enabled ? .green : .secondary)
                            Text(rule.name)
                        }
                        Text(describe(rule.trigger))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .tag(rule.id)
                }
            }
            HStack(spacing: 6) {
                Menu {
                    Button(T("Bir uygulama açıkken", "While an app is open")) { add(.app(bundleIDs: [])) }
                    Button(T("Belirli bir ağdayken", "On a certain network")) { add(.network(ssids: [], serviceNames: [])) }
                    Button(T("Belirli saatlerde", "During certain hours")) {
                        add(.schedule(days: [], startMinute: 20 * 60, endMinute: 23 * 60))
                    }
                } label: { Image(systemName: "plus") }
                .menuStyle(.borderlessButton)
                .frame(width: 34)

                Button { remove() } label: { Image(systemName: "minus") }
                    .buttonStyle(.borderless)
                    .disabled(selectedIndex == nil)
                Spacer()
            }
            .padding(6)
        }
    }

    private func describe(_ trigger: Trigger) -> String {
        switch trigger {
        case .app(let ids):
            return ids.isEmpty
                ? T("Uygulama seçilmedi", "No app chosen")
                : T("\(ids.count) uygulama", "\(ids.count) app(s)")
        case .network(let ssids, let services):
            let count = ssids.count + services.count
            return count == 0 ? T("Ağ seçilmedi", "No network chosen")
                              : T("\(count) ağ", "\(count) network(s)")
        case .schedule(_, let start, let end):
            return "\(Self.format(start)) – \(Self.format(end))"
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let index = selectedIndex {
            Form {
                Section {
                    TextField(T("Ad", "Name"), text: $store.config.rules[index].name)
                    Toggle(T("Bu kural çalışsın", "Use this rule"), isOn: $store.config.rules[index].enabled)
                }
                triggerEditor(index: index)
            }
            .formStyle(.grouped)
            .onChange(of: store.config.rules) { supervisor.evaluate() }
        } else {
            ContentUnavailableView(
                T("Bir kural seç", "Select a rule"),
                systemImage: "clock",
                description: Text(T("Soldaki artı ile yeni kural ekleyebilirsin.",
                                    "Use the plus button on the left to add one."))
            )
        }
    }

    @ViewBuilder
    private func triggerEditor(index: Int) -> some View {
        switch store.config.rules[index].trigger {
        case .app(let bundleIDs):
            Section {
                ForEach(bundleIDs, id: \.self) { id in
                    HStack {
                        Text(appName(for: id))
                        Spacer()
                        Button { removeBundleID(id, at: index) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
                Button(T("Uygulama seç…", "Choose app…")) { pickApp(at: index) }
                Text(T("Uygulama açılır açılmaz devreye girer, kapanınca kendiliğinden durur.",
                       "Turns on the moment the app opens and off when it closes."))
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text(T("Bu uygulamalar açıkken", "While these apps are open"))
            }

        case .network(let ssids, let services):
            Section {
                ForEach(ssids, id: \.self) { ssid in
                    HStack {
                        Text(ssid)
                        Spacer()
                        Button { setNetwork(at: index, ssids: ssids.filter { $0 != ssid }, services: services) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                if let current = supervisor.currentSSID {
                    Button(T("Şu anki ağı ekle (\(current))", "Add current network (\(current))")) {
                        guard !ssids.contains(current) else { return }
                        setNetwork(at: index, ssids: ssids + [current], services: services)
                    }
                } else {
                    Text(T("Wi-Fi adı okunamıyor. macOS bunun için konum izni istiyor; izin vermezsen aşağıdan bağlantı türünü seçebilirsin.",
                           "Cannot read the Wi-Fi name. macOS requires location permission for it; otherwise pick a connection type below."))
                        .font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text(T("Wi-Fi ağı", "Wi-Fi network"))
            }
            Section {
                ForEach(supervisor.activeServices, id: \.self) { service in
                    Toggle(service, isOn: Binding(
                        get: { services.contains(service) },
                        set: { on in
                            let updated = on ? services + [service] : services.filter { $0 != service }
                            setNetwork(at: index, ssids: ssids, services: updated)
                        }
                    ))
                }
            } header: {
                Text(T("Bağlantı türü", "Connection type"))
            }

        case .schedule(let days, let start, let end):
            Section {
                HStack {
                    ForEach(1...7, id: \.self) { day in
                        Toggle(dayNames[day - 1], isOn: Binding(
                            get: { days.contains(day) },
                            set: { on in
                                var updated = days
                                if on { updated.insert(day) } else { updated.remove(day) }
                                store.config.rules[index].trigger = .schedule(days: updated, startMinute: start, endMinute: end)
                            }
                        ))
                        .toggleStyle(.button)
                    }
                }
                Text(T("Hiç gün seçmezsen her gün geçerli olur.",
                       "If you pick no days, it applies every day."))
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text(T("Günler", "Days"))
            }
            Section {
                Stepper(T("Başlangıç: \(Self.format(start))", "Start: \(Self.format(start))"), value: Binding(
                    get: { start },
                    set: { store.config.rules[index].trigger = .schedule(days: days, startMinute: $0, endMinute: end) }
                ), in: 0...1439, step: 15)
                Stepper(T("Bitiş: \(Self.format(end))", "End: \(Self.format(end))"), value: Binding(
                    get: { end },
                    set: { store.config.rules[index].trigger = .schedule(days: days, startMinute: start, endMinute: $0) }
                ), in: 0...1439, step: 15)
                Text(T("Bitiş saati başlangıçtan küçükse aralık gece yarısını aşar.",
                       "If the end is earlier than the start, the range crosses midnight."))
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text(T("Saat aralığı", "Hours"))
            }
        }
    }

    private var dayNames: [String] {
        l10n.isTurkish
            ? ["Paz", "Pzt", "Sal", "Çar", "Per", "Cum", "Cmt"]
            : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    }

    private static func format(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    /// Paket kimliği yerine kullanıcının bildiği adı göster.
    private func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private func add(_ trigger: Trigger) {
        let rule = AutomationRule(name: T("Yeni kural", "New rule"), trigger: trigger)
        store.config.rules.append(rule)
        selection = rule.id
    }

    private func remove() {
        guard let index = selectedIndex else { return }
        store.config.rules.remove(at: index)
        selection = store.config.rules.first?.id
        supervisor.evaluate()
    }

    private func setNetwork(at index: Int, ssids: [String], services: [String]) {
        store.config.rules[index].trigger = .network(ssids: ssids, serviceNames: services)
    }

    private func removeBundleID(_ id: String, at index: Int) {
        guard case .app(let ids) = store.config.rules[index].trigger else { return }
        store.config.rules[index].trigger = .app(bundleIDs: ids.filter { $0 != id })
    }

    /// Uygulamayı kullanıcı seçer, paket kimliğini biz okuruz. Kimliği elle
    /// yazdırmak hata kaynağı (com.hnc.Discord gibi tahmin edilemez).
    private func pickApp(at index: Int) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier,
              case .app(let ids) = store.config.rules[index].trigger,
              !ids.contains(bundleID) else { return }
        store.config.rules[index].trigger = .app(bundleIDs: ids + [bundleID])
        let appTitle = url.deletingPathExtension().lastPathComponent
        if store.config.rules[index].name == T("Yeni kural", "New rule") {
            store.config.rules[index].name = T("\(appTitle) açıkken", "While \(appTitle) is open")
        }
    }
}
