//
//  WatchJournalView.swift
//  ZenithiumWatch
//
//  The third page: log something. Faz 21.
//
//  The only thing the watch writes, and it writes to the same append-only outbox the home
//  screen widget uses — never to SwiftData, which the phone owns. A tap here shows up in the
//  journal the next time the phone comes forward.
//

import SwiftUI
import WatchKit

struct WatchJournalView: View {

    @State private var logged: Set<JournalBehavior> = PendingJournalStore.loggedToday()

    var body: some View {
        ScrollView {
            VStack(spacing: ZenithiumSpacing.s) {
                Text("Bugün")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(JournalBehaviorWidgetSet.featured, id: \.self) { behavior in
                    Button {
                        PendingJournalStore.toggle(behavior)
                        logged = PendingJournalStore.loggedToday()
                        // A journal entry has no visible consequence on the wrist, so the
                        // haptic is the confirmation. Without it a tap feels ignored.
                        WKInterfaceDevice.current().play(.click)
                    } label: {
                        HStack(spacing: ZenithiumSpacing.s) {
                            Image(systemName: behavior.symbolName)
                                .font(.system(size: 13))
                                .frame(width: 18)
                            Text(behavior.displayName)
                                .font(.system(size: 14))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                            if logged.contains(behavior) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .padding(.vertical, ZenithiumSpacing.xs)
                    }
                    .buttonStyle(.bordered)
                    .tint(logged.contains(behavior) ? ZenithiumColor.accent : .gray)
                    .accessibilityLabel(behavior.displayName)
                    .accessibilityAddTraits(logged.contains(behavior) ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, ZenithiumSpacing.xxs)
        }
        .containerBackground(ZenithiumColor.spectrumViolet.gradient.opacity(0.22), for: .tabView)
    }
}
