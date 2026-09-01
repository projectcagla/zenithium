//
//  JournalBehavior.swift
//  Zenithium
//
//  Günlüğe kaydedilen davranışlar.
//
//  Bu, uygulamanın üç personaya da aynı gün değer katan tek özelliği: hiç antrenman
//  yapmayan biri için uygulamanın *tek* sebebi bile olabilir. Tamamen cihaz içi istatistik —
//  ağ gerektirmiyor.
//

import Foundation

/// Bir gece boyunca toparlanmayı etkileyebilecek, kullanıcının kaydettiği davranış.
///
/// Liste kasıtlı olarak kısa. Otuz seçenek sunmak, kullanıcının hiçbirini düzenli
/// kaydetmemesiyle sonuçlanır — ve düzenli kayıt olmadan korelasyon motorunun söyleyecek
/// hiçbir şeyi olmaz.
enum JournalBehavior: String, Sendable, Codable, CaseIterable, Hashable, Identifiable {
    case alcohol
    case lateCaffeine
    case lateMeal
    case screenBeforeBed
    case highStress
    case illness
    case travel
    case sauna
    case coldExposure
    case meditation
    case socialEvening
    case medication

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .alcohol: return "Alkol"
        case .lateCaffeine: return "Geç kafein"
        case .lateMeal: return "Geç yemek"
        case .screenBeforeBed: return "Yatmadan önce ekran"
        case .highStress: return "Yoğun stres"
        case .illness: return "Hastalık"
        case .travel: return "Yolculuk"
        case .sauna: return "Sauna"
        case .coldExposure: return "Soğuk maruziyeti"
        case .meditation: return "Meditasyon"
        case .socialEvening: return "Sosyal akşam"
        case .medication: return "İlaç"
        }
    }

    var symbolName: String {
        switch self {
        case .alcohol: return "wineglass"
        case .lateCaffeine: return "cup.and.saucer"
        case .lateMeal: return "fork.knife"
        case .screenBeforeBed: return "iphone"
        case .highStress: return "bolt.trianglebadge.exclamationmark"
        case .illness: return "thermometer.medium"
        case .travel: return "airplane"
        case .sauna: return "flame"
        case .coldExposure: return "snowflake"
        case .meditation: return "figure.mind.and.body"
        case .socialEvening: return "person.2"
        case .medication: return "pills"
        }
    }

    /// Kaydın hangi gece için geçerli olduğu — hepsi o geceyi etkiler, bir sonrakini değil.
    var accessibilityName: String {
        displayName
    }
}

/// Kullanıcının kendi bildirdiği ruh hâli.
///
/// ASSUMPTION JOURNAL-1: kendi kaydımızı tutuyoruz, iOS 18'in `HKStateOfMind` verisini
/// okumuyoruz — henüz. Sebep pratik: uygulamanın derlenip çalıştığı doğrulandı ve
/// doğrulayamadığım bir API'yi araya sokmak o durumu riske atardı. `stateOfMind` okuması
/// tek bir mapper fonksiyonu olarak sonradan eklenecek; bu tip o zaman da aynı kalır.
enum MoodRating: Int, Sendable, Codable, CaseIterable, Hashable, Identifiable {
    case veryLow = 1
    case low = 2
    case neutral = 3
    case good = 4
    case veryGood = 5

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .veryLow: return "Çok kötü"
        case .low: return "Kötü"
        case .neutral: return "Normal"
        case .good: return "İyi"
        case .veryGood: return "Çok iyi"
        }
    }

    var symbolName: String {
        switch self {
        case .veryLow: return "cloud.heavyrain"
        case .low: return "cloud"
        case .neutral: return "cloud.sun"
        case .good: return "sun.max"
        case .veryGood: return "sparkles"
        }
    }
}

/// Bir günün günlük kaydı, değer tipi olarak.
struct JournalDay: Sendable, Equatable, Hashable, Identifiable, Codable {

    /// Kaydın ait olduğu günün yerel gece yarısı.
    let dayStart: Date

    let behaviors: Set<JournalBehavior>
    let mood: MoodRating?
    let note: String

    var id: Date { dayStart }

    var isEmpty: Bool {
        behaviors.isEmpty && mood == nil && note.isEmpty
    }

    static func empty(dayStart: Date) -> JournalDay {
        JournalDay(dayStart: dayStart, behaviors: [], mood: nil, note: "")
    }
}
