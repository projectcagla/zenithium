//
//  HubView.swift
//  Zenithium
//
//  Everything outside the daily loop, on one page. Faz 14.
//
//  This exists because a tab bar stopped being able to hold the app. Handing iOS fourteen
//  tabs gets a "More" list it builds itself: system order, system styling, and one line per
//  row with no room to say what anything is. A hub costs one extra tap and buys grouping,
//  ordering and a sentence under every destination — which matters most for the screens a
//  user opens rarely and has to be reminded exist.
//
//  The lens decides what appears. A health-lens user has no reason to see a strain ceiling
//  or a Hyrox screen, and hiding them is not a downgrade — it is the lens doing its job.
//

import SwiftUI

/// A destination reachable from the hub.
enum HubDestination: String, Sendable, Hashable, CaseIterable, Identifiable {
    case strain
    case load
    case endurance
    case racePlan
    case strength
    case muscles
    case plan
    case vitals
    case hybrid
    case trends
    case bloodwork
    case report
    case documents
    case dataTransfer
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strain: return "Zorlanma"
        case .load: return "Yük"
        case .endurance: return "Koşu"
        case .racePlan: return "Yarış temposu"
        case .strength: return "Kuvvet"
        case .muscles: return "Kaslar"
        case .plan: return "Plan"
        case .vitals: return "Sağlık"
        case .hybrid: return "Hibrit"
        case .trends: return "Trendler"
        case .bloodwork: return "Kan değerleri"
        case .report: return "Hekim raporu"
        case .documents: return "Belgeler"
        case .dataTransfer: return "Veri taşıma"
        case .settings: return "Ayarlar"
        }
    }

    /// One line saying what the screen answers. Not a category label — the point of the hub
    /// is that a rarely-opened screen gets to explain itself.
    var subtitle: String {
        switch self {
        case .strain: return "Bugün ne kadar zorlandın, tavanın neresi"
        case .load: return "Son hafta son ayına göre nerede"
        case .endurance: return "Kritik hız, tempo bölgeleri, yarış tahmini"
        case .racePlan: return "Parkurun eğimine göre kilometre hedefleri"
        case .strength: return "Haftalık hacim, denge, tahmini 1TM"
        case .muscles: return "Hangi grup toparlandı, hangisi hâlâ yük taşıyor"
        case .plan: return "Hedef etkinlik ve hangi fazdasın"
        case .vitals: return "Saatinin ölçtüğü ama kimsenin toplamadığı sinyaller"
        case .hybrid: return "İstasyon ve kompanse koşu analizi"
        case .trends: return "Her ölçümün zaman içindeki seyri"
        case .bloodwork: return "Tahlil sonuçların ve panelin"
        case .report: return "12 haftalık özet, doktoruna göstermek için"
        case .documents: return "EKG, görüntüleme, hekim notu — cihazında, aranabilir"
        case .dataTransfer: return "Her şeyi tek dosyaya yaz, yeni telefonda oku"
        case .settings: return "Profil, mercek, izinler"
        }
    }

    var symbolName: String {
        switch self {
        case .strain: return "flame.fill"
        case .load: return "chart.bar.fill"
        case .endurance: return "figure.run"
        case .racePlan: return "flag.checkered"
        case .strength: return "dumbbell.fill"
        case .muscles: return "figure.strengthtraining.traditional"
        case .plan: return "calendar"
        case .vitals: return "waveform.path.ecg"
        case .hybrid: return "figure.mixed.cardio"
        case .trends: return "chart.line.uptrend.xyaxis"
        case .bloodwork: return "drop.fill"
        case .report: return "doc.text"
        case .documents: return "folder"
        case .dataTransfer: return "arrow.up.arrow.down.square"
        case .settings: return "gearshape.fill"
        }
    }

    /// Which group the row sits in.
    var group: HubGroup {
        switch self {
        case .strain, .load, .endurance, .racePlan, .strength, .muscles, .plan, .hybrid: return .training
        case .vitals, .trends, .bloodwork, .report, .documents: return .health
        case .dataTransfer, .settings: return .app
        }
    }

    /// Whether a lens shows this destination at all.
    ///
    /// The second tab is excluded here rather than duplicated: a destination already sitting
    /// on the tab bar does not need a second entrance.
    func isVisible(for lens: TrainingLens) -> Bool {
        switch self {
        case .strain: return lens.showsStrainCeiling && lens.secondaryTab != .load
        case .load: return lens.showsStrainCeiling && lens.secondaryTab != .load
        case .muscles: return lens != .health && lens.secondaryTab != .muscles
        case .vitals: return lens.secondaryTab != .vitals
        case .endurance: return lens == .endurance || lens == .hybrid
        // Only the running lens plans a course; a Hyrox athlete does not pace a GPX.
        case .racePlan: return lens == .endurance
        case .strength: return lens == .strength || lens == .hybrid
        case .hybrid: return lens == .hybrid
        case .plan: return lens != .health
        case .trends, .bloodwork, .report, .documents, .dataTransfer, .settings: return true
        }
    }
}

enum HubGroup: String, Sendable, Hashable, CaseIterable {
    case training
    case health
    case app

    var displayName: String {
        switch self {
        case .training: return "Antrenman"
        case .health: return "Sağlık"
        case .app: return "Uygulama"
        }
    }
}

struct HubView<Destination: View>: View {

    let lens: TrainingLens

    @ViewBuilder let destination: (HubDestination) -> Destination

    var body: some View {
        NavigationStack {
            List {
                ForEach(HubGroup.allCases, id: \.self) { group in
                    let rows = HubDestination.allCases.filter {
                        $0.group == group && $0.isVisible(for: lens)
                    }
                    if !rows.isEmpty {
                        Section(group.displayName) {
                            ForEach(rows) { item in
                                NavigationLink {
                                    destination(item)
                                } label: {
                                    HubRow(item: item)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(ZenithiumColor.background.ignoresSafeArea())
            .navigationTitle("Daha fazla")
            .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
        }
        .tint(ZenithiumColor.accent)
    }
}

private struct HubRow: View {

    let item: HubDestination

    var body: some View {
        HStack(spacing: ZenithiumSpacing.l) {
            Image(systemName: item.symbolName)
                .font(.system(size: 15))
                .foregroundStyle(ZenithiumColor.accent)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: ZenithiumRadius.medium, style: .continuous)
                        .fill(ZenithiumColor.accent.opacity(0.14))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                Text(item.title)
                    .font(ZenithiumFont.headline)
                    .foregroundStyle(ZenithiumColor.textPrimary)
                Text(item.subtitle)
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, ZenithiumSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}
