//
//  HyroxStation.swift
//  Zenithium
//
//  Hyrox'un sekiz istasyonu, yarış sırasıyla.
//
//  Yarış yapısı: 8 tur, her turda 1 km koşu + bir istasyon. Zorluk ne koşuda ne istasyonda —
//  **yorgunken koşmakta.** Bu dosyanın var olma sebebi o: istasyonları isimlendirmeden
//  "istasyon sonrası koşu" ölçülemez.
//

import Foundation

enum HyroxStation: String, Sendable, Codable, CaseIterable, Hashable, Identifiable {
    case skiErg
    case sledPush
    case sledPull
    case burpeeBroadJump
    case rowing
    case farmersCarry
    case sandbagLunges
    case wallBalls

    var id: String { rawValue }

    /// Yarıştaki sırası, 1'den 8'e.
    var order: Int {
        switch self {
        case .skiErg: return 1
        case .sledPush: return 2
        case .sledPull: return 3
        case .burpeeBroadJump: return 4
        case .rowing: return 5
        case .farmersCarry: return 6
        case .sandbagLunges: return 7
        case .wallBalls: return 8
        }
    }

    var displayName: String {
        switch self {
        case .skiErg: return "SkiErg"
        case .sledPush: return "Sled Push"
        case .sledPull: return "Sled Pull"
        case .burpeeBroadJump: return "Burpee Broad Jump"
        case .rowing: return "Rowing"
        case .farmersCarry: return "Farmers Carry"
        case .sandbagLunges: return "Sandbag Lunges"
        case .wallBalls: return "Wall Balls"
        }
    }

    var shortName: String {
        switch self {
        case .skiErg: return "Ski"
        case .sledPush: return "Push"
        case .sledPull: return "Pull"
        case .burpeeBroadJump: return "Burpee"
        case .rowing: return "Row"
        case .farmersCarry: return "Carry"
        case .sandbagLunges: return "Lunge"
        case .wallBalls: return "Wall Ball"
        }
    }

    /// Yarış standardı — açık kategori.
    var specification: String {
        switch self {
        case .skiErg: return "1000 m"
        case .sledPush: return "50 m"
        case .sledPull: return "50 m"
        case .burpeeBroadJump: return "80 m"
        case .rowing: return "1000 m"
        case .farmersCarry: return "200 m"
        case .sandbagLunges: return "100 m"
        case .wallBalls: return "75–100 tekrar"
        }
    }

    var symbolName: String {
        switch self {
        case .skiErg: return "figure.skiing.crosscountry"
        case .sledPush: return "arrow.right.to.line"
        case .sledPull: return "arrow.left.to.line"
        case .burpeeBroadJump: return "figure.jumprope"
        case .rowing: return "figure.rower"
        case .farmersCarry: return "bag.fill"
        case .sandbagLunges: return "figure.strengthtraining.functional"
        case .wallBalls: return "basketball"
        }
    }

    /// İstasyonun ağırlıklı olarak kas dayanıklılığı mı yoksa kardiyovasküler mi olduğu.
    ///
    /// Dengesizlik tespiti için: bir sporcunun bütün zayıf istasyonları aynı sınıftaysa,
    /// sorun tek tek istasyonlarda değil o kapasitededir.
    var dominantSystem: HybridSystem {
        switch self {
        case .skiErg, .rowing: return .cardiovascular
        case .sledPush, .sledPull, .farmersCarry, .sandbagLunges: return .muscular
        case .burpeeBroadJump, .wallBalls: return .mixed
        }
    }
}

/// Bir yükün ağırlıklı olarak hangi sistemi zorladığı.
enum HybridSystem: String, Sendable, Codable, CaseIterable, Hashable {
    case cardiovascular
    case muscular
    case mixed

    var displayName: String {
        switch self {
        case .cardiovascular: return "Kardiyovasküler"
        case .muscular: return "Kas dayanıklılığı"
        case .mixed: return "Karma"
        }
    }
}

/// Bir hibrit seansın tek bir parçası.
struct HybridSegment: Sendable, Equatable, Hashable, Identifiable, Codable {

    enum Kind: Sendable, Equatable, Hashable, Codable {
        /// Koşu bölümü. `roundIndex` 1'den başlar; ilk koşu referans kabul edilir.
        case run(distanceMeters: Double, roundIndex: Int)
        case station(HyroxStation)
        /// Roxzone — koşu ile istasyon arasındaki geçiş.
        case transition
    }

    let id: UUID
    let kind: Kind
    let interval: DateInterval
    let averageHeartRate: Double?
    let peakHeartRate: Double?

    var duration: TimeInterval { interval.duration }

    var station: HyroxStation? {
        if case .station(let station) = kind { return station }
        return nil
    }

    var runRound: Int? {
        if case .run(_, let index) = kind { return index }
        return nil
    }

    var runDistance: Double? {
        if case .run(let distance, _) = kind { return distance }
        return nil
    }

    /// Koşunun temposu, saniye/km.
    var paceSecondsPerKilometre: Double? {
        guard let distance = runDistance, distance > 0, duration > 0 else { return nil }
        return duration / (distance / 1000)
    }
}
