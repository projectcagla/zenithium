//
//  TrainingPlan.swift
//  Zenithium
//
//  Goal events and the phases leading to them. Faz 20.
//
//  A plan here is deliberately thin: a date, what it is, and where today sits on the way to
//  it. Zenithium does not write a week-by-week programme — that is a coach's job and an app
//  that pretends otherwise is guessing at somebody's life. What it *can* do honestly is name
//  the phase, say what the phase is for, and let the prescription engine bias itself
//  accordingly.
//
//  The one piece of real arithmetic is the taper, because it is the part where the fitness /
//  fatigue split earns its keep: fatigue sheds on a seven-day constant and fitness on a
//  forty-two-day one, so the same load reduction leaves form higher the closer it sits to
//  the event.
//

import Foundation

/// What the user is working towards.
enum GoalEventKind: String, Sendable, Codable, Hashable, CaseIterable, Identifiable {
    case race
    case hyrox
    case strengthTest
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .race: return "Yarış"
        case .hyrox: return "Hyrox"
        case .strengthTest: return "Kuvvet testi"
        case .other: return "Etkinlik"
        }
    }

    var symbolName: String {
        switch self {
        case .race: return "flag.checkered"
        case .hyrox: return "figure.mixed.cardio"
        case .strengthTest: return "dumbbell.fill"
        case .other: return "star"
        }
    }

    /// How long the taper runs, in days.
    ///
    /// Longer for the events that accumulate the most fatigue. A strength test needs days,
    /// not weeks — maximal strength returns quickly and detrains slowly.
    var taperDays: Int {
        switch self {
        case .race: return 14
        case .hyrox: return 10
        case .strengthTest: return 5
        case .other: return 7
        }
    }
}

/// A phase of the run-up.
enum PlanPhase: String, Sendable, Hashable, CaseIterable, Identifiable {
    case base
    case build
    case sharpen
    case taper
    case event
    case recovery

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .base: return "Baz"
        case .build: return "Yapı"
        case .sharpen: return "Keskinleşme"
        case .taper: return "Tapering"
        case .event: return "Etkinlik"
        case .recovery: return "Toparlanma"
        }
    }

    var purpose: String {
        switch self {
        case .base: return "Hacim ve dayanıklılık. Sertlik değil, süreklilik."
        case .build: return "Hacim korunurken şiddet artar; haftanın en zor bloğu burada."
        case .sharpen: return "Hacim düşer, şiddet kalır. Yarış temposu bu fazda oturur."
        case .taper: return "Yük azalır, kondisyon kalır. Yorgunluk kondisyondan altı kat hızlı iner."
        case .event: return "Gün geldi."
        case .recovery: return "Etkinlik sonrası. Yorgunluk inene kadar yükü geri koyma."
        }
    }

    /// How the prescription engine should bias itself in this phase.
    ///
    /// A multiplier on prescribed duration, not on intensity. Reducing intensity in a taper
    /// is the classic mistake — it is volume that comes down while the sharp sessions stay,
    /// which is what keeps the adaptations that were paid for.
    var volumeMultiplier: Double {
        switch self {
        case .base: return 1.0
        case .build: return 1.1
        case .sharpen: return 0.9
        case .taper: return 0.6
        case .event: return 0.0
        case .recovery: return 0.5
        }
    }
}

/// A goal the user entered.
struct GoalEvent: Sendable, Equatable, Hashable, Identifiable, Codable {

    let id: UUID
    let kind: GoalEventKind
    let name: String

    /// Local day of the event.
    let date: Date

    init(id: UUID = UUID(), kind: GoalEventKind, name: String, date: Date) {
        self.id = id
        self.kind = kind
        self.name = name
        self.date = date
    }
}

/// Where today sits relative to a goal.
struct PlanPosition: Sendable, Equatable, Hashable {

    let event: GoalEvent
    let phase: PlanPhase

    /// Days until the event. Negative after it.
    let daysRemaining: Int

    /// How many weeks of run-up there are in total, for the progress read-out.
    let totalWeeks: Int

    var isPast: Bool { daysRemaining < 0 }

    /// The sentence shown on the plan card.
    var summary: String {
        if daysRemaining < 0 {
            return "\(event.name) geçti — \(-daysRemaining) gün önce."
        }
        if daysRemaining == 0 {
            return "\(event.name) bugün."
        }
        return "\(event.name)'e \(daysRemaining) gün — \(phase.displayName.lowercased()) fazı."
    }
}
