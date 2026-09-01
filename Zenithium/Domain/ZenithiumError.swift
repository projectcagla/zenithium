//
//  ZenithiumError.swift
//  Zenithium
//
//  The single typed error surface. Spec §2.5 (Result-free `throws` with a typed enum),
//  ASSUMPTION NAME-1 (renamed from the specification's `ApexError`).
//

import Foundation

/// Every failure Zenithium can surface, with copy that stays inside the §12 safety rules:
/// nothing here describes a health status, only a data or system condition.
enum ZenithiumError: Error, Sendable, Equatable, Hashable {

    /// HealthKit is not present on this device (iPad, Simulator without health support).
    case healthDataUnavailable

    /// The user has been asked and declined, or has revoked, read access.
    case healthAuthorizationDenied

    /// The user has not yet been asked. The caller should present the onboarding gate.
    case healthAuthorizationNotDetermined

    /// The HealthKit database is encrypted because the device is locked.
    ///
    /// Distinct from every other health failure and the distinction is the point: nothing is
    /// wrong, nothing needs the user's permission, and retrying now cannot succeed. The work
    /// has to wait for an unlock, which is what `ProtectedDataGuard` arranges. Folding this
    /// into `healthQueryFailed` produced a retry that was guaranteed to fail and an error
    /// message telling the user to open the Health app while their phone was on a nightstand.
    case healthDataProtected

    /// A HealthKit query failed. `detail` is the underlying error's description, never a value.
    case healthQueryFailed(kind: HealthDataKind, detail: String)

    /// A vital-sign read failed. Separate from `healthQueryFailed` because a vital sign is
    /// not a `HealthDataKind` — it is a signal Zenithium shows rather than scores with, and
    /// forcing it into that enum only to name an error would blur a distinction the rest of
    /// the app depends on.
    case vitalQueryFailed(sign: VitalSign, detail: String)

    /// The persistent container could not be created.
    case persistenceUnavailable(detail: String)

    /// A read against the persistent store failed.
    case persistenceReadFailed(detail: String)

    /// A write against the persistent store failed.
    case persistenceWriteFailed(detail: String)

    /// An engine was handed input it cannot score. Engines never trap; they throw or return
    /// an unavailable output. This case is for callers that assemble malformed input.
    case invalidEngineInput(reason: String)

    /// The App Group container is not reachable, so the widget snapshot cannot be shared.
    case appGroupUnavailable(identifier: String)

    /// `BGTaskScheduler` refused the submission.
    case backgroundTaskSubmissionFailed(detail: String)

    /// The operation was cancelled cooperatively. Never surfaced as a failure state in the UI.
    case cancelled
}

extension ZenithiumError: LocalizedError {

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "Bu cihazda Sağlık verisi kullanılamıyor."
        case .healthAuthorizationDenied:
            return "Zenithium'un sağlık verilerini okuma izni yok."
        case .healthAuthorizationNotDetermined:
            return "Zenithium henüz sağlık verilerini okumak için izin istemedi."
        case .healthDataProtected:
            return "Cihaz kilitliyken Sağlık verisi şifreli kalıyor."
        case .vitalQueryFailed(let sign, _):
            return "Sağlık'tan \(sign.displayName) okunamadı."
        case .healthQueryFailed(let kind, _):
            return "Sağlık'tan \(kind.displayName) okunamadı."
        case .persistenceUnavailable:
            return "Zenithium yerel veritabanını açamadı."
        case .persistenceReadFailed:
            return "Zenithium yerel veritabanından okuyamadı."
        case .persistenceWriteFailed:
            return "Zenithium yerel veritabanına kaydedemedi."
        case .invalidEngineInput:
            return "Bunu hesaplamak için yeterli geçerli veri yoktu."
        case .appGroupUnavailable:
            return "Zenithium paylaşılan depoya erişemedi; widget'lar güncel olmayabilir."
        case .backgroundTaskSubmissionFailed:
            return "Zenithium arka plan yenilemesini zamanlayamadı."
        case .cancelled:
            return "Güncelleme iptal edildi."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .healthDataUnavailable:
            return "Zenithium needs an iPhone paired with an Apple Watch that records sleep and heart data."
        case .healthAuthorizationDenied:
            return "Ayarlar › Sağlık › Veri Erişimi ve Cihazlar › Zenithium yolunu izleyip paylaşmak istediğin kategorileri aç."
        case .healthAuthorizationNotDetermined:
            return "Zenithium'un neleri okuduğunu görmek için Devam'a dokun. Hiçbir şey cihazından çıkmaz."
        case .healthDataProtected:
            return "Cihazın kilidi açılınca kaldığım yerden devam edeceğim."
        case .healthQueryFailed, .vitalQueryFailed:
            return "Yenilemek için aşağı çek. Tekrarlarsa Sağlık uygulamasını bir kez açıp eşitlemesini bekle."
        case .persistenceUnavailable, .persistenceReadFailed, .persistenceWriteFailed:
            return "Tekrar dene. Sürerse Zenithium'u yeniden başlatmak yerel dizini yeniden kurar."
        case .invalidEngineInput:
            return "Bir sonraki gecelik veriden sonra tekrar deneyeceğim."
        case .appGroupUnavailable:
            return "Widget'ı kaldırıp yeniden ekleyerek bağlantısını tazele."
        case .backgroundTaskSubmissionFailed:
            return "Zenithium bir sonraki açılışta yenileyecek."
        case .cancelled:
            return nil
        }
    }

    /// Whether the UI should offer a retry affordance for this error.
    var isRetryable: Bool {
        switch self {
        case .healthQueryFailed, .vitalQueryFailed, .persistenceReadFailed, .persistenceWriteFailed,
             .invalidEngineInput, .backgroundTaskSubmissionFailed, .appGroupUnavailable:
            return true
        // `healthDataProtected` is not retryable *now*: the database stays encrypted until
        // the device is unlocked, so a retry button would be a button that cannot work.
        // `ProtectedDataGuard` runs the work at unlock instead.
        case .healthDataUnavailable, .healthAuthorizationDenied,
             .healthAuthorizationNotDetermined, .persistenceUnavailable,
             .healthDataProtected, .cancelled:
            return false
        }
    }

    /// Whether the UI should route the user to the system Settings app.
    var requiresSystemSettings: Bool {
        self == .healthAuthorizationDenied
    }

    /// Whether a fan-out read that hit this error must fail whole rather than answer partially.
    ///
    /// §4.3 lets one unreadable metric be dropped and its weight renormalized — that rule is
    /// about a metric the device genuinely has nothing for, and it is safe precisely because
    /// the absence is real. The errors below are different in kind: the data exists and
    /// is being withheld, so continuing would score somebody against a silently reduced set of
    /// inputs and present the result as if it were complete.
    ///
    /// `healthDataProtected` is the case this property was extracted for. It was added when
    /// the locked-device path went in, but the three fan-out sites that decide whether to
    /// throw were each carrying their own copy of the list and none of them was extended — so
    /// a morning recalculation on a locked phone dropped whichever metrics were still
    /// encrypted and produced a confident, wrong recovery score. One list, three call sites.
    ///
    /// `healthAuthorizationNotDetermined` joins them for the same reason: nothing will be
    /// readable until the sheet has been shown, so a series assembled through it is empty
    /// by construction rather than by measurement.
    var blocksPartialResults: Bool {
        switch self {
        case .cancelled, .healthAuthorizationDenied, .healthAuthorizationNotDetermined,
             .healthDataUnavailable, .healthDataProtected:
            return true
        case .healthQueryFailed, .vitalQueryFailed,
             .persistenceUnavailable, .persistenceReadFailed, .persistenceWriteFailed,
             .invalidEngineInput, .appGroupUnavailable, .backgroundTaskSubmissionFailed:
            return false
        }
    }
}
