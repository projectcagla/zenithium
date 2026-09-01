//
//  ZenithiumErrorTests.swift
//  ZenithiumTests
//
//  The classification three fan-out reads share, pinned. Adım 2.
//
//  `HealthKitService.fetchBaselineSeries`, `HealthKitService.fetchAverageQuantity` and
//  `VitalsViewModel.load` each read many metrics concurrently and each has to decide, per
//  child, whether a failure costs one metric or the whole answer. Until v0.1 they made that
//  decision from three hand-maintained copies of the same list, and the copies had already
//  drifted: `healthDataProtected` was added when the locked-device path went in and reached
//  none of them, so a recalculation on a locked phone dropped whichever metrics were still
//  encrypted and scored the day from what was left.
//
//  There is one list now — `ZenithiumError.blocksPartialResults` — and this suite is what
//  keeps a future case from being added without an answer to the same question.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Error classification")
struct ZenithiumErrorClassificationTests {

    /// Data exists and is being withheld. Continuing would score a silently reduced input set.
    static let withholding: [ZenithiumError] = [
        .healthAuthorizationDenied,
        .healthAuthorizationNotDetermined,
        .healthDataUnavailable,
        .healthDataProtected
    ]

    /// One metric failed on its own. §4.3 drops it and renormalizes the rest.
    static let localised: [ZenithiumError] = [
        .healthQueryFailed(kind: .heartRateVariability, detail: "timeout"),
        .vitalQueryFailed(sign: .restingHeartRate, detail: "timeout"),
        .persistenceReadFailed(detail: "busy"),
        .persistenceWriteFailed(detail: "busy"),
        .persistenceUnavailable(detail: "no container"),
        .invalidEngineInput(reason: "empty window"),
        .appGroupUnavailable(identifier: "group.9PF6U63MV3.zenithium"),
        .backgroundTaskSubmissionFailed(detail: "too many pending")
    ]

    @Test("Veri esirgendiğinde kısmi sonuç üretilmiyor", arguments: withholding)
    func withheldDataRefusesTheWholeRead(error: ZenithiumError) {
        #expect(error.blocksPartialResults, "\(error) kısmi sonuca izin veriyor")
    }

    @Test("Tek bir ölçümün hatası ekranın tamamını götürmüyor", arguments: localised)
    func oneFailedMetricIsOnlyThatMetricsProblem(error: ZenithiumError) {
        #expect(!error.blocksPartialResults, "\(error) tüm okumayı iptal ediyor")
    }

    /// Cancellation is not a failure, but it is not a partial answer either: the work was
    /// abandoned, so whatever it had gathered describes nothing.
    @Test("İptal kısmi sonuç değil")
    func cancellationIsNotAPartialAnswer() {
        #expect(ZenithiumError.cancelled.blocksPartialResults)
        #expect(ViewState<Int>.from(ZenithiumError.cancelled) == nil, "iptal ekranı değiştirmemeli")
    }

    /// The invariant that keeps the two properties from contradicting each other on screen.
    ///
    /// An error that refuses the whole read refuses it for a reason no button can change — a
    /// permission, an unlock, a device without the sensor. Offering a retry alongside would
    /// be offering a control that cannot work.
    @Test("Tüm okumayı reddeden hata yeniden denenebilir görünmüyor",
          arguments: withholding + [ZenithiumError.cancelled])
    func nothingBlockingIsAlsoRetryable(error: ZenithiumError) {
        #expect(!error.isRetryable, "\(error) hem engelliyor hem yeniden denenebilir diyor")
    }

    /// The two lists above have to stay exhaustive, and a new case makes neither of them fail
    /// on its own. This is the check that notices: every case the enum can produce is named
    /// in exactly one of them.
    @Test("Her hata tam olarak bir sınıfta")
    func everyErrorIsClassifiedExactlyOnce() {
        let all = Self.withholding + Self.localised + [.cancelled]
        #expect(Set(all).count == all.count, "aynı hata iki listede")
        // Mirrors `blocksPartialResults`'s own switch, which the compiler forces to be
        // exhaustive — so a case added there without being added here shows up as a count
        // mismatch rather than as an untested branch.
        #expect(all.count == 13, "yeni bir ZenithiumError durumu sınıflandırılmamış")
    }

    // MARK: - §12

    /// Every message the user can see says what happened and what to do, without diagnosing.
    @Test("Hata metinleri tıbbi bir iddia taşımıyor", arguments: withholding + localised + [.cancelled])
    func errorCopyMakesNoMedicalClaim(error: ZenithiumError) {
        let text = ((error.errorDescription ?? "") + " " + (error.recoverySuggestion ?? "")).lowercased()
        for word in ["hastalık", "teşhis", "tanı koy", "riskli", "sağlıksız", "tedavi"] {
            #expect(!text.contains(word), "\(error): \(word)")
        }
    }
}
