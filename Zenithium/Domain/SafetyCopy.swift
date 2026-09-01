//
//  SafetyCopy.swift
//  Zenithium
//
//  Every user-facing string that touches health, in one auditable table. Spec §12.
//  ASSUMPTION SAFE-1: views may not invent this copy — they read it from here, so compliance
//  is reviewable in a single file.
//
//  Rules encoded here:
//  · Zenithium is a fitness and wellness tool, not a medical device.
//  · It does not diagnose and never suggests ignoring symptoms.
//  · Low recovery is directive about *training*, never about *health status*.
//  · No calorie targets, no weight goals, no restriction prompts, anywhere.
//  · Bloodwork shows reference ranges and trends only — no interpretation, no treatment.
//

import Foundation

/// The app's safety and compliance copy.
enum SafetyCopy {

    // MARK: - Disclaimers

    /// Shown during onboarding and in Settings (§12).
    static let disclaimerTitle = "Tıbbi cihaz değildir"

    static let disclaimerBody = """
    Zenithium bir spor ve iyi yaşam aracıdır. Apple Watch'ının zaten kaydettiği verilerden \
    antrenmana hazırlığını tahmin eder. Tıbbi cihaz değildir, hiçbir şeye teşhis koymaz ve \
    sağlığının yerinde olup olmadığını söyleyemez.

    Bir şikâyetin veya sağlıkla ilgili bir sorun varsa hekimine danış. Zenithium'daki hiçbir \
    şey o konuşmanın yerine geçmez ve hiçbiri onu ertelemek için bir sebep değildir.
    """

    static let disclaimerAcknowledgement = "Anladım"

    /// The one-line version shown as a footer under scores.
    static let disclaimerFooter = "Yalnızca antrenman yönlendirmesi. Tıbbi cihaz değildir."

    // MARK: - Privacy

    static let privacyTitle = "Verin burada kalır"

    static let privacyBody = """
    Zenithium'un hesabı, sunucusu ve ağ izni yok. Okuduğu her şey Apple Sağlık'ta ve bu \
    cihazdaki kendi deposunda kalır.

    Hiçbir şey yüklenmez. Hiçbir şey paylaşılmaz. Uygulamada analitik, çökme raporlama veya \
    üçüncü taraf kod yoktur. Zenithium'u silersen hesapları da onunla gider — Sağlık verin \
    her zaman olduğu yerde kalır.
    """

    static let privacyPoints: [String] = [
        "Hesap yok, giriş yok",
        "Hiçbir türde ağ isteği yok",
        "Analitik yok, izleme yok",
        "Hesaplar tamamen bu cihazda çalışır",
        "Widget'lar kendi uygulama grubundaki bir kopyayı okur"
    ]

    // MARK: - Recovery guidance

    /// Training-directive headline for a recovery band. Never a health statement (§12).
    static func recoveryHeadline(for band: RecoveryBand) -> String {
        switch band {
        case .green: return "Yüksek Adaptasyon Kapasitesi"
        case .yellow: return "Dengeli Antrenman Günü"
        case .red: return "Fizyolojik Toparlanma Önceliği"
        }
    }

    /// Training-directive body copy for a recovery band.
    static func recoveryGuidance(for band: RecoveryBand) -> String {
        switch band {
        case .green:
            return "Biyometrik değerlerin bireysel taban çizginin üzerinde. Yüksek yoğunluklu bir antrenman için otonom sinir sistemin hazır."
        case .yellow:
            return "Biyometrik değerlerin taban çizginle uyumlu. Planlı orta şiddette antrenmanını sürdürebilirsin."
        case .red:
            return "Biyometrik değerlerin taban çizginin altında. Aktif toparlanma, mobilite veya dinlenme önerilir."
        }
    }

    /// The sentence built around the strongest negative driver.
    static func driverSentence(positive: String?, negative: String?) -> String {
        switch (positive, negative) {
        case (let positive?, let negative?):
            return "Ana belirleyici: \(negative); dengeleyici unsur: \(positive)."
        case (let positive?, nil):
            return "Öne çıkan olumlu etken: \(positive)."
        case (nil, let negative?):
            return "Öne çıkan baskılayıcı: \(negative)."
        case (nil, nil):
            return "Biyometrik sinyaller dengeli bir dağılım gösteriyor."
        }
    }

    // MARK: - Strain guidance

    static func strainGuidance(strain: Double, ceiling: Double?) -> String {
        guard let ceiling, ceiling > 0 else {
            return "Hedef yükü belirlemek için toparlanma skoru gereklidir."
        }
        if strain > ceiling {
            return "Günlük hedef yük sınırına ulaşıldı. Fazladan zorlanma yerine toparlanmaya odaklanın."
        }
        let remaining = ceiling - strain
        if remaining < 1 {
            return "Günlük antrenman hedefindesiniz."
        }
        return "Hedef yük kapasitesine ulaşmak için alanınız bulunuyor."
    }

    // MARK: - Muscle map guidance

    static func muscleGuidance(for readiness: MuscleReadiness) -> String {
        switch readiness.band {
        case .green:
            return "\(readiness.muscle.displayName) tam kapasiteyle antrenmana hazır."
        case .yellow:
            return "\(readiness.muscle.displayName) kısmen toparlandı. Orta şiddette yük veya alternatif hareket kalıpları önerilir."
        case .red:
            return "\(readiness.muscle.displayName) belirgin yorgunluk taşıyor. Bu kas grubunu dinlendirmeniz önerilir."
        }
    }

    // MARK: - Bloodwork

    /// Shown at the top of the bloodwork screen. §12: ranges and trends only.
    static let bloodworkDisclaimer = """
    Zenithium, laboratuvar raporunda yazanı saklar ve zaman içindeki seyrini çizer. Sonuçları \
    yorumlamaz, değerleri işaretlemez ve haklarında bir şey önermez. Bunu hekimin yapar.
    """

    static let bloodworkRangeCaption = "Tipik bir laboratuvar raporunda basıldığı hâliyle referans aralığı."

    static let bloodworkOptimalCaption = "Literatürde sık anılan daha dar bir bant. Bağlam, hedef değil."

    /// Attached to every observation about a value outside its reference band, and to
    /// nothing else. §12: this is the only response Zenithium is permitted to have to an
    /// out-of-range result — it never names a cause and never suggests a remedy.
    static let clinicianPrompt = "Bu değeri hekimine göster. Zenithium ne anlama geldiğini söyleyemez."

    // MARK: - Clinician report (Faz 27)

    /// Printed at the top of every exported report.
    ///
    /// A clinician opening this needs to know within one line what produced it and what it
    /// is not. It says where the numbers came from, that nothing in the document is
    /// interpreted, and that the ranges shown are the ones the user's own laboratory printed.
    static let reportDisclaimer = """
    Bu belge Zenithium tarafından, kullanıcının Apple Watch verilerinden ve kendi girdiği laboratuvar sonuçlarından oluşturulmuştur. Zenithium tıbbi cihaz değildir; bu belgede hiçbir değer yorumlanmamış, işaretlenmemiş veya bir sonuca bağlanmamıştır. Gösterilen referans aralıkları kullanıcının kendi raporundan ya da yaygın laboratuvar aralıklarından alınmıştır. Tüm veriler cihaz üzerinde hesaplanmıştır.
    """

    // MARK: - Empty and calibrating states

    static let calibratingTitle = "Kalibrasyon"

    static func calibratingBody(daysCollected: Int, daysRequired: Int) -> String {
        let remaining = max(0, daysRequired - daysCollected)
        if remaining == 1 {
            return "Kişisel taban çizgisinin tamamlanması için son 1 gecelik veri bekleniyor."
        }
        return "Kişisel taban çizgisinin tamamlanması için \(remaining) gecelik veri bekleniyor."
    }

    static let noOvernightDataTitle = "Gece Biyometrisi Bulunamadı"

    static let noOvernightDataBody = """
    Dün geceye ait biyometrik kayıt bulunamadı. Saatinizi uyku modunda takarak uyuduğunuzda toparlanma analiziniz oluşturulacaktır.
    """

    // MARK: - Authorization

    static let authorizationTitle = "Zenithium'un Sağlık erişimine ihtiyacı var"

    static let authorizationBody = """
    Zenithium uyku, nabız, HRV, istirahat nabzı, solunum hızı, bilek sıcaklığı ve antrenman \
    verilerini okur. Bunları bu cihazda okur ve geri hiçbir şey yazmaz.
    """

    static let authorizationDeniedBody = """
    Sağlık erişimi şu anda kapalı. Ayarlar › Sağlık › Veri Erişimi ve Cihazlar › Zenithium \
    yolunu izleyip paylaşmak istediğin kategorileri aç. Zenithium neye izin verirsen onunla çalışır.
    """

    static let openSettingsAction = "Ayarları aç"
}
