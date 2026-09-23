import SwiftUI
import UpkeepKit

/// The live monitoring card: what this Mac is spending itself on right now.
///
/// Four meters and two short lists. The lists are the point — a percentage tells
/// you the machine is busy, a name tells you what to close. They answer the
/// question people actually arrive with, which is never "what is my CPU load".
struct MonitorCardView: View {

    @ObservedObject private var monitor = Upkeep.monitor
    @State private var sort: Sort = .cpu

    private enum Sort: String, CaseIterable {
        case cpu, memory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.m) {
            meters
            Divider()
            processes
        }
        .padding(.vertical, KalfaDesign.s)
        // Sampling is tied to this view being on screen: the panel is closed most
        // of the time, and a meter nobody is looking at should cost nothing.
        .onAppear { monitor.retain() }
        .onDisappear { monitor.release() }
    }

    // MARK: Meters

    private var meters: some View {
        VStack(spacing: KalfaDesign.s) {
            MeterRow(
                title: L10n.t("monitor.cpu"),
                value: monitor.sample.cpu.total,
                detail: percent(monitor.sample.cpu.total),
                history: monitor.cpuHistory,
                tint: .blue
            )

            MeterRow(
                title: L10n.t("monitor.memory"),
                value: monitor.sample.memory.usedFraction,
                detail: "\(Upkeep.bytes(monitor.sample.memory.used)) / \(Upkeep.bytes(monitor.sample.memory.total))",
                history: monitor.memoryHistory,
                tint: pressureTint
            )

            if let gpu = monitor.sample.gpu {
                MeterRow(title: L10n.t("monitor.gpu"),
                         value: gpu,
                         detail: percent(gpu),
                         history: [],
                         tint: .purple)
            }

            MeterRow(
                title: L10n.t("monitor.disk"),
                value: monitor.sample.disk.usedFraction,
                detail: L10n.t("monitor.disk.free", Upkeep.bytes(monitor.sample.disk.free)),
                history: [],
                tint: .orange
            )

            HStack(spacing: KalfaDesign.xs) {
                KalfaChip(Upkeep.rate(monitor.sample.network.inPerSecond,
                                      perSecond: L10n.t("monitor.perSecond")),
                          symbol: "arrow.down", tint: .teal)
                KalfaChip(Upkeep.rate(monitor.sample.network.outPerSecond,
                                      perSecond: L10n.t("monitor.perSecond")),
                          symbol: "arrow.up", tint: .teal)
                if let power = monitor.sample.power {
                    KalfaChip("%\(power.percentage)",
                              symbol: power.isPluggedIn ? "bolt.fill" : "battery.50",
                              tint: power.percentage <= 20 && !power.isPluggedIn ? .red : .green)
                }
                Spacer(minLength: 0)
            }

            if monitor.sample.memory.pressure != .normal {
                Label(L10n.t(monitor.sample.memory.pressure == .critical
                             ? "monitor.pressure.critical"
                             : "monitor.pressure.warning"),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(monitor.sample.memory.pressure == .critical ? .red : .orange)
            }
        }
    }

    /// Memory colour follows the kernel's pressure level, not the percentage.
    /// macOS hands unused RAM to the disk cache, so a full-looking bar is normal
    /// and colouring it red would teach people to ignore the one real warning.
    private var pressureTint: Color {
        switch monitor.sample.memory.pressure {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    // MARK: Processes

    private var processes: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.s) {
            Picker("", selection: $sort) {
                Text(L10n.t("monitor.cpu")).tag(Sort.cpu)
                Text(L10n.t("monitor.memory")).tag(Sort.memory)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if rows.isEmpty {
                Text(L10n.t("monitor.measuring"))
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    HStack(spacing: KalfaDesign.s) {
                        Text(row.name)
                            .font(KalfaDesign.bodyFont)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: KalfaDesign.s)
                        Text(sort == .cpu ? percent(row.cpu) : Upkeep.bytes(row.memory))
                            .font(KalfaDesign.captionFont.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var rows: [ProcessRow] {
        sort == .cpu ? monitor.topByCPU() : monitor.topByMemory()
    }

    /// A process can exceed one whole core, so this is not clamped to 100.
    private func percent(_ value: Double) -> String {
        String(format: "%%%.0f", value * 100)
    }
}

// MARK: - Meter

/// One labelled bar with an optional sparkline behind it.
private struct MeterRow: View {
    let title: String
    let value: Double
    let detail: String
    let history: [Double]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: KalfaDesign.xs) {
            HStack {
                Text(title)
                    .font(KalfaDesign.captionFont)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(detail)
                    .font(KalfaDesign.captionFont.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ZStack(alignment: .leading) {
                if history.count > 1 {
                    Sparkline(values: history)
                        .stroke(tint.opacity(0.5), lineWidth: 1)
                        .frame(height: 16)
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(tint)
                            .frame(width: geometry.size.width * min(max(value, 0), 1))
                    }
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 16)
        }
    }
}

/// Plain path rather than Swift Charts: sixty points redrawn every second, and
/// the framework's axis and scale machinery is all cost and no benefit here.
private struct Sparkline: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let step = rect.width / CGFloat(values.count - 1)
        for (index, value) in values.enumerated() {
            let point = CGPoint(x: rect.minX + CGFloat(index) * step,
                                y: rect.maxY - rect.height * CGFloat(min(max(value, 0), 1)))
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }
}
