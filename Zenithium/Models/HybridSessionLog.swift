//
//  HybridSessionLog.swift
//  Zenithium
//
//  Kaydedilmiş bir hibrit seans — tam yarış, yarım simülasyon ya da bir istasyon bloğu.
//

import Foundation
import SwiftData

/// Seansın türü. Karşılaştırmanın doğru olması için gerekli: yarım simülasyonu tam yarışla
/// yan yana koymak, sporcuya yanlış bir gerileme gösterirdi.
enum HybridSessionKind: String, Sendable, Codable, CaseIterable, Hashable, Identifiable {
    case fullRace
    case halfSimulation
    case stationBlock
    case compromisedRunBlock

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fullRace: return "Tam yarış"
        case .halfSimulation: return "Yarım simülasyon"
        case .stationBlock: return "İstasyon bloğu"
        case .compromisedRunBlock: return "Kompanse koşu bloğu"
        }
    }

    var subtitle: String {
        switch self {
        case .fullRace: return "8 koşu + 8 istasyon"
        case .halfSimulation: return "4 koşu + 4 istasyon"
        case .stationBlock: return "Yalnızca istasyonlar"
        case .compromisedRunBlock: return "İstasyon–koşu tekrarları"
        }
    }
}

@Model
final class HybridSessionLog {

    @Attribute(.unique) var id: UUID

    var performedAt: Date
    var timeZoneIdentifier: String
    var kindRawValue: String

    /// Seansın parçaları — koşular, istasyonlar, geçişler.
    var segments: [HybridSegment]

    /// Analiz sırasında kullanılan taze tempo referansı, saniye/km.
    var freshPaceSecondsPerKilometre: Double?

    /// Kaydedildiği anda hesaplanan özet değerler. Motor her zaman yeniden çalıştırılabilir;
    /// bunlar liste ekranının her satır için motoru çağırmaması içindir.
    var totalDurationSeconds: Double
    var roxzoneSeconds: Double
    var compromisedPenalty: Double?
    var sessionLoad: Double

    var note: String
    var engineVersion: Int
    var createdAt: Date

    init(
        id: UUID,
        performedAt: Date,
        timeZoneIdentifier: String,
        kind: HybridSessionKind,
        segments: [HybridSegment],
        freshPaceSecondsPerKilometre: Double?,
        totalDurationSeconds: Double,
        roxzoneSeconds: Double,
        compromisedPenalty: Double?,
        sessionLoad: Double,
        note: String,
        engineVersion: Int,
        createdAt: Date
    ) {
        self.id = id
        self.performedAt = performedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.kindRawValue = kind.rawValue
        self.segments = segments
        self.freshPaceSecondsPerKilometre = freshPaceSecondsPerKilometre
        self.totalDurationSeconds = totalDurationSeconds
        self.roxzoneSeconds = roxzoneSeconds
        self.compromisedPenalty = compromisedPenalty
        self.sessionLoad = sessionLoad
        self.note = note
        self.engineVersion = engineVersion
        self.createdAt = createdAt
    }

    var kind: HybridSessionKind? {
        HybridSessionKind(rawValue: kindRawValue)
    }
}

/// Değer tipi karşılığı — mağaza sınırını bu geçer (ASSUMPTION STORE-1).
struct HybridSessionSnapshot: Sendable, Equatable, Identifiable, Hashable, Codable {
    let id: UUID
    let performedAt: Date
    let timeZoneIdentifier: String
    let kind: HybridSessionKind
    let segments: [HybridSegment]
    let freshPaceSecondsPerKilometre: Double?
    let totalDurationSeconds: Double
    let roxzoneSeconds: Double
    let compromisedPenalty: Double?
    let sessionLoad: Double
    let note: String

    /// Motoru yeniden çalıştırmak için gereken girdi.
    func input(restingHeartRate: Double, maxHeartRate: Double) -> HybridSessionInput {
        HybridSessionInput(
            segments: segments,
            freshPaceSecondsPerKilometre: freshPaceSecondsPerKilometre,
            restingHeartRate: restingHeartRate,
            maxHeartRate: maxHeartRate,
            performedAt: performedAt
        )
    }
}
