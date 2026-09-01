//
//  JournalWidget.swift
//  ZenithiumWidgets
//
//  The interactive journal widget. Faz 22.
//
//  ## Why this one is worth building
//
//  The journal's correlation engine needs entries on most days to say anything, and the
//  thing that stops people logging is not effort — it is opening the app. Four buttons on
//  the home screen is the difference between a log that fills in and one that does not, and
//  the correlations are only as good as the log.
//
//  ## Why it writes to its own file
//
//  A widget cannot open the SwiftData store: the app may hold it, and two writers on one
//  container is how a database gets corrupted. So a tap appends to a small pending-entry
//  file in the App Group, and the app drains it into SwiftData on its next foreground. The
//  widget's write is append-only and its reader is the single owner of the real store.
//

import AppIntents
import SwiftUI
import WidgetKit

struct JournalWidget: Widget {

    nonisolated static let kind = "com.zenithium.app.widget.journal"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: JournalTimelineProvider()) { entry in
            JournalWidgetView(entry: entry)
                .containerBackground(ZenithiumColor.background, for: .widget)
        }
        .configurationDisplayName("Günlük")
        .description("Bugünün davranışlarını tek dokunuşla kaydet.")
        .supportedFamilies([.systemMedium])
    }
}

struct JournalWidgetEntry: TimelineEntry {
    let date: Date
    /// Behaviours already logged today, so a tapped chip stays lit.
    let logged: Set<JournalBehavior>
}

struct JournalTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> JournalWidgetEntry {
        JournalWidgetEntry(date: Date(), logged: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (JournalWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JournalWidgetEntry>) -> Void) {
        // One entry, refreshed at the next day boundary. The widget's own taps reload it
        // through `reloadTimelines`, so there is nothing to poll for in between.
        var calendar = Calendar.current
        calendar.timeZone = .current
        let tomorrow = calendar.startOfDay(for: Date().addingTimeInterval(86_400))
        completion(Timeline(entries: [entry()], policy: .after(tomorrow)))
    }

    private func entry() -> JournalWidgetEntry {
        JournalWidgetEntry(date: Date(), logged: PendingJournalStore.loggedToday())
    }
}

struct JournalWidgetView: View {

    let entry: JournalWidgetEntry

    /// The four offered on the widget.
    ///
    /// Not all twelve: a medium widget fits four chips at a legible size, and these are the
    /// four whose correlations turn up most often. The list lives in
    /// `JournalBehaviorWidgetSet` so the drain on the app side reads the same one — a widget
    /// offering a behaviour the drain does not know about would have its taps dropped.
    static var featured: [JournalBehavior] { JournalBehaviorWidgetSet.featured }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
            Text("Bugün")
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textTertiary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: ZenithiumSpacing.s), count: 2), spacing: ZenithiumSpacing.s) {
                ForEach(Self.featured, id: \.self) { behavior in
                    Button(intent: LogBehaviorIntent(behavior: behavior)) {
                        HStack(spacing: ZenithiumSpacing.s) {
                            Image(systemName: behavior.symbolName)
                                .font(.system(size: 12))
                            Text(behavior.displayName)
                                .font(ZenithiumFont.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, ZenithiumSpacing.s)
                        .padding(.vertical, ZenithiumSpacing.s)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: ZenithiumRadius.medium, style: .continuous)
                                .fill(
                                    entry.logged.contains(behavior)
                                        ? ZenithiumColor.accent.opacity(0.22)
                                        : ZenithiumColor.surfaceElevated
                                )
                        )
                        .foregroundStyle(
                            entry.logged.contains(behavior)
                                ? ZenithiumColor.accent
                                : ZenithiumColor.textSecondary
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(behavior.displayName)
                    .accessibilityAddTraits(entry.logged.contains(behavior) ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .padding(ZenithiumSpacing.xxs)
    }
}

/// Records one behaviour for today.
struct LogBehaviorIntent: AppIntent {

    static let title: LocalizedStringResource = "Davranış kaydet"

    @Parameter(title: "Davranış")
    var behaviorRawValue: String

    init() {
        self.behaviorRawValue = ""
    }

    init(behavior: JournalBehavior) {
        self.behaviorRawValue = behavior.rawValue
    }

    func perform() async throws -> some IntentResult {
        guard let behavior = JournalBehavior(rawValue: behaviorRawValue) else { return .result() }
        PendingJournalStore.toggle(behavior)
        WidgetCenter.shared.reloadTimelines(ofKind: JournalWidget.kind)
        return .result()
    }
}
