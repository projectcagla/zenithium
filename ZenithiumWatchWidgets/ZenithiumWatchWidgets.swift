import SwiftUI
import WidgetKit

struct WatchDecisionEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct WatchDecisionProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchDecisionEntry { WatchDecisionEntry(date: Date(), snapshot: .placeholder) }
    func getSnapshot(in context: Context, completion: @escaping (WatchDecisionEntry) -> Void) {
        completion(WatchDecisionEntry(date: Date(), snapshot: WidgetSnapshotStore.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchDecisionEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore.read()
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(3600)
        let expires = min(midnight, now.addingTimeInterval(3600))
        completion(Timeline(entries: [WatchDecisionEntry(date: now, snapshot: snapshot),
                                     WatchDecisionEntry(date: expires, snapshot: snapshot)], policy: .after(expires)))
    }
}

@main
struct ZenithiumWatchWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.zenithium.watch.decision", provider: WatchDecisionProvider()) { entry in
            WatchDecisionAccessory(entry: entry).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Toparlanma ve karar")
        .description("Telefondaki son günlük karar. Yeni günün verisi yoksa yenileme beklediğini gösterir.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct WatchDecisionAccessory: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchDecisionEntry
    private var isCurrent: Bool { Calendar.current.isDate(entry.snapshot.generatedAt, inSameDayAs: entry.date) }
    private var score: String { isCurrent ? entry.snapshot.recoveryScore.map(ZenithiumFormat.score) ?? "—" : "—" }
    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: isCurrent ? (entry.snapshot.recoveryScore ?? 0) / 100 : 0) {
                    Image(systemName: "heart")
                } currentValueLabel: { Text(score).monospacedDigit() }
                .gaugeStyle(.accessoryCircular)
            case .accessoryInline:
                Label("Toparlanma \(score)", systemImage: "heart")
            default:
                VStack(alignment: .leading, spacing: 3) {
                    Text("Toparlanma \(score)").font(.headline)
                    Text(isCurrent ? entry.snapshot.prescriptionLine ?? "Veri birikiyor" : "Telefondan güncelleme bekleniyor")
                        .font(.caption).lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Toparlanma")
        .accessibilityValue(isCurrent && entry.snapshot.recoveryScore != nil ? "100 üzerinden \(score). \(entry.snapshot.prescriptionLine ?? "")" : "Bugünün ölçümü henüz eşitlenmedi")
    }
}
