//
//  LabInsightEngineTests.swift
//  ZenithiumTests
//
//  §12 is a product rule, so it gets tests like one. The load-bearing assertion in this
//  file is that an out-of-range value produces exactly one kind of output — the clinician
//  prompt — and never anything that reads as a cause or a remedy.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Lab insight engine")
struct LabInsightEngineTests {

    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9)) ?? Date()
    }

    private func marker(
        _ key: String,
        _ value: Double,
        unit: String,
        drawnAt: Date,
        reference: MarkerRange = .unbounded,
        optimal: MarkerRange = .unbounded
    ) -> BloodMarkerSnapshot {
        BloodMarkerSnapshot(
            id: UUID(),
            marker: .standard(key),
            value: value,
            unitSymbol: unit,
            referenceRange: reference,
            optimalRange: optimal,
            drawnAt: drawnAt,
            note: ""
        )
    }

    // MARK: - §12

    @Test("Referans dışı değer yalnızca hekime yönlendirir")
    func outOfRangeRoutesToClinician() throws {
        let now = day(2026, 6, 1)
        let observations = LabInsightEngine.observations(
            markers: [marker("ferritin", 12, unit: "ng/mL", drawnAt: day(2026, 5, 20))],
            sex: .male,
            now: now,
            calendar: calendar
        )
        let reference = try #require(observations.first { $0.kind == .outsideReference(isAbove: false) })
        #expect(reference.requiresClinician)
        // Cümle bir sebep ileri sürmemeli, bir çözüm önermemeli.
        #expect(SafetyFilter.isSafe(reference.message))
        #expect(!reference.message.lowercased().contains("demir eksikliği"))
    }

    @Test("Aralık içindeki değer hekim uyarısı üretmez")
    func inRangeDoesNotPrompt() {
        let observations = LabInsightEngine.observations(
            markers: [marker("ferritin", 90, unit: "ng/mL", drawnAt: day(2026, 5, 20))],
            sex: .male,
            now: day(2026, 6, 1),
            calendar: calendar
        )
        #expect(!observations.contains { $0.requiresClinician })
    }

    @Test("Her gözlem güvenlik süzgecinden geçer")
    func everyMessageIsSafe() {
        let markers = [
            marker("ferritin", 12, unit: "ng/mL", drawnAt: day(2026, 5, 20)),
            marker("vitaminD", 18, unit: "ng/mL", drawnAt: day(2025, 1, 10)),
            marker("creatineKinase", 900, unit: "U/L", drawnAt: day(2026, 5, 20)),
            marker("tsh", 2.1, unit: "mIU/L", drawnAt: day(2026, 5, 20))
        ]
        let observations = LabInsightEngine.observations(
            markers: markers,
            sex: .male,
            now: day(2026, 6, 1),
            calendar: calendar
        )
        #expect(!observations.isEmpty)
        for observation in observations {
            #expect(SafetyFilter.isSafe(observation.message), "güvensiz: \(observation.message)")
        }
    }

    // MARK: - Sex-specific bands

    /// Ferritin 20 ng/mL is inside a female reference band and below a male one. Showing one
    /// band to everybody was the bug this replaced.
    @Test("Referans bandı cinsiyete göre değişir")
    func usesSexSpecificBand() {
        let sample = [marker("ferritin", 20, unit: "ng/mL", drawnAt: day(2026, 5, 20))]
        let male = LabInsightEngine.observations(markers: sample, sex: .male, now: day(2026, 6, 1), calendar: calendar)
        let female = LabInsightEngine.observations(markers: sample, sex: .female, now: day(2026, 6, 1), calendar: calendar)
        #expect(male.contains { $0.requiresClinician })
        #expect(!female.contains { $0.requiresClinician })
    }

    @Test("Cinsiyet bilinmiyorsa geniş band kullanılır")
    func unknownSexUsesWiderBand() {
        let sample = [marker("ferritin", 20, unit: "ng/mL", drawnAt: day(2026, 5, 20))]
        let unknown = LabInsightEngine.observations(markers: sample, sex: .notSet, now: day(2026, 6, 1), calendar: calendar)
        // Geniş band 15–400; 20 içeride kalır, yani bilinmeyen cinsiyette kimse boş yere
        // hekime yönlendirilmez.
        #expect(!unknown.contains { $0.requiresClinician })
    }

    // MARK: - Movement, age, timing

    @Test("İki ölçüm arasındaki hareket bildirilir")
    func reportsMovement() throws {
        let observations = LabInsightEngine.observations(
            markers: [
                marker("vitaminD", 32, unit: "ng/mL", drawnAt: day(2026, 1, 10)),
                marker("vitaminD", 46, unit: "ng/mL", drawnAt: day(2026, 5, 10))
            ],
            sex: .male,
            now: day(2026, 6, 1),
            calendar: calendar
        )
        let movement = try #require(observations.first { if case .movement = $0.kind { return true } else { return false } })
        guard case .movement(let delta, let days) = movement.kind else {
            Issue.record("hareket gözlemi beklenmişti")
            return
        }
        #expect(delta == 14)
        #expect(days == 120)
    }

    @Test("Yeniden test aralığını geçen değerin yaşı söylenir")
    func reportsAge() {
        let observations = LabInsightEngine.observations(
            markers: [marker("ferritin", 90, unit: "ng/mL", drawnAt: day(2024, 6, 1))],
            sex: .male,
            now: day(2026, 6, 1),
            calendar: calendar
        )
        #expect(observations.contains { if case .aging = $0.kind { return true } else { return false } })
    }

    /// CK moves for days after a hard session, so a draw taken inside that window cannot be
    /// compared with one taken rested. Saying so is a statement about the measurement.
    @Test("Antrenmandan hemen sonraki ölçüm için zamanlama uyarısı")
    func flagsTimingForTrainingSensitiveMarkers() throws {
        let drawn = day(2026, 5, 20)
        let session = drawn.addingTimeInterval(-24 * 3600)
        let observations = LabInsightEngine.observations(
            markers: [marker("creatineKinase", 260, unit: "U/L", drawnAt: drawn)],
            sex: .male,
            sessionDates: [session],
            now: day(2026, 6, 1),
            calendar: calendar
        )
        let caveat = try #require(observations.first { if case .timingCaveat = $0.kind { return true } else { return false } })
        guard case .timingCaveat(let hours) = caveat.kind else {
            Issue.record("zamanlama uyarısı beklenmişti")
            return
        }
        #expect(hours == 24)
    }

    @Test("Zamanlamaya duyarlı olmayan belirteçte uyarı çıkmaz")
    func noTimingCaveatForStableMarkers() {
        let drawn = day(2026, 5, 20)
        let observations = LabInsightEngine.observations(
            markers: [marker("vitaminD", 44, unit: "ng/mL", drawnAt: drawn)],
            sex: .male,
            sessionDates: [drawn.addingTimeInterval(-3600)],
            now: day(2026, 6, 1),
            calendar: calendar
        )
        #expect(!observations.contains { if case .timingCaveat = $0.kind { return true } else { return false } })
    }

    // MARK: - Panels

    @Test("Eksik panel ortağı bildirilir")
    func reportsPanelGap() throws {
        let observations = LabInsightEngine.observations(
            markers: [marker("ferritin", 90, unit: "ng/mL", drawnAt: day(2026, 5, 20))],
            sex: .male,
            now: day(2026, 6, 1),
            calendar: calendar
        )
        let gap = try #require(observations.first { if case .panelGap = $0.kind { return true } else { return false } })
        #expect(gap.message.contains("Transferrin"))
    }

    @Test("Panel tamamsa boşluk bildirilmez")
    func noGapWhenPanelComplete() {
        let observations = LabInsightEngine.observations(
            markers: [
                marker("ferritin", 90, unit: "ng/mL", drawnAt: day(2026, 5, 20)),
                marker("transferrinSaturation", 30, unit: "%", drawnAt: day(2026, 5, 20)),
                marker("serumIron", 100, unit: "µg/dL", drawnAt: day(2026, 5, 20))
            ],
            sex: .male,
            now: day(2026, 6, 1),
            calendar: calendar
        )
        #expect(!observations.contains { if case .panelGap = $0.kind { return true } else { return false } })
    }
}
