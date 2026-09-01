//
//  ZenithiumFont.swift
//  Zenithium
//
//  Tipografi. Tasarım yönü v1.
//
//  ASSUMPTION DESIGN-2: sayılar SF Pro **genişletilmiş** genişlikte, yuvarlatılmış değil.
//  Yuvarlak biçimler sıcak ve tüketici ürünü okunur — Whoop'un ve her fitness uygulamasının
//  dili. Genişletilmiş genişlik enstrüman okunur: bir uçuş göstergesinin ya da iyi bir saatin
//  kadranı gibi. Aynı aile, farklı eksen; sistem yazı tipinden çıkmadan karakter değişiyor.
//
//  Gövde metni yuvarlatılmış kalıyor: uzun paragraflarda genişletilmiş genişlik yorucudur.
//  Ayrım kasıtlı — sayılar alet, cümleler insan.
//

import SwiftUI

enum ZenithiumFont {

    // MARK: - Başlıklar

    static let title = Font.system(.largeTitle, design: .rounded, weight: .semibold)
    static let sectionTitle = Font.system(.headline, design: .rounded, weight: .semibold)

    // MARK: - Gövde

    static let body = Font.system(.body, design: .rounded)
    static let callout = Font.system(.callout, design: .rounded)
    static let label = Font.system(.subheadline, design: .rounded, weight: .medium)
    static let caption = Font.system(.caption, design: .rounded)

    /// Bir satırın kendi başlığı — kart başlığından küçük, gövdeden ağır.
    static let headline = Font.system(.headline, design: .rounded, weight: .medium)

    /// Bir alanın altındaki açıklama.
    static let footnote = Font.system(.footnote, design: .rounded)

    /// Rozet ve kaynak satırı gibi en küçük yardımcı metin.
    static let caption2 = Font.system(.caption2, design: .rounded)

    /// Ekranın hüküm cümlesi. Reçetenin üstündeki tek satır.
    static let verdict = Font.system(.title3, design: .rounded, weight: .semibold)

    // MARK: - Sayılar

    /// Bir kartın içindeki değer.
    static let metricValue = Font.system(.title2, weight: .semibold)
        .width(.expanded)
        .monospacedDigit()

    /// Tek başına duran büyük sayı.
    static let displayValue = Font.system(.largeTitle, weight: .bold)
        .width(.expanded)
        .monospacedDigit()

    /// Yayın içindeki ana okuma. Boyut çağıran tarafından ölçeklenir.
    static func arcValue(size: CGFloat) -> Font {
        .system(size: size, weight: .bold)
            .width(.expanded)
            .monospacedDigit()
    }

    /// Değerin ardındaki birim.
    static let unit = Font.system(.footnote, design: .rounded, weight: .medium)

    /// Veri satırlarındaki sayı — dar sütunlarda hizalanması için tabular.
    static let dataValue = Font.system(.callout, design: .rounded, weight: .medium)
        .monospacedDigit()

    /// Küçük büyük harfli etiket — bölüm başlıkları, persona göstergeleri.
    static let eyebrow = Font.system(.caption2, design: .rounded, weight: .semibold)
}

extension View {

    func zenithiumBody() -> some View {
        font(ZenithiumFont.body)
            .foregroundStyle(ZenithiumColor.textPrimary)
    }

    func zenithiumSecondary() -> some View {
        font(ZenithiumFont.callout)
            .foregroundStyle(ZenithiumColor.textSecondary)
    }

    /// Bölüm üstü etiketi: küçük, harf aralıklı, vurgu renginde.
    func zenithiumEyebrow() -> some View {
        font(ZenithiumFont.eyebrow)
            .textCase(.uppercase)
            .kerning(1.6)
            .foregroundStyle(ZenithiumColor.accent)
    }
}

/// Sayı biçimlendirme. Hiçbir görünüm kendi biçimini uydurmaz.
enum ZenithiumFormat {

    static func score(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    static func strain(_ value: Double) -> String {
        decimal(value, digits: 1)
    }

    static func metric(_ value: Double, digits: Int) -> String {
        decimal(value, digits: digits)
    }

    /// A decimal number, written the way Turkish writes one.
    ///
    /// `String(format:)` is C's formatter: it always writes a period, whatever the device
    /// locale is set to. So every number in the app read `12.3` — in an interface that types
    /// `12,4` in its own copy, and whose lab parser was written specifically to accept the
    /// comma form because that is what Turkish laboratory reports print.
    ///
    /// Done by substitution rather than by `NumberFormatter` on purpose: the result is
    /// deterministic, it does not vary with the device's region while the interface is
    /// Turkish either way, and it costs no formatter allocation on a path that runs for
    /// every tile on every screen.
    ///
    /// Non-finite values become the app's own empty marker instead of `nan` or `inf`, which
    /// is what `String(format:)` would have printed on screen. `pace` already guarded for
    /// this; the other two did not.
    private static func decimal(_ value: Double, digits: Int) -> String {
        guard value.isFinite else { return "—" }
        return String(format: "%.\(max(0, digits))f", value)
            .replacingOccurrences(of: ".", with: ",")
    }

    static func duration(seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours == 0 { return "\(minutes)dk" }
        return "\(hours)sa \(minutes)dk"
    }

    /// Dakika:saniye — koşu splitleri ve roxzone için.
    static func clock(seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Saat:dakika:saniye — bir saati aşabilen süreler için. `clock` bir maratonu
    /// "162:04" diye yazardı; bu ayrım bunun için var.
    static func longClock(seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        if hours == 0 {
            return String(format: "%d:%02d", (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d:%02d", hours, (total % 3600) / 60, total % 60)
    }

    /// Tempo, dakika:saniye/km.
    static func pace(secondsPerKilometre: Double) -> String {
        guard secondsPerKilometre.isFinite, secondsPerKilometre > 0 else { return "—" }
        let total = Int(secondsPerKilometre.rounded())
        return String(format: "%d:%02d/km", total / 60, total % 60)
    }

    static func spokenDuration(seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        // Türkçede çoğul eki sayıdan sonra gelmez, bu yüzden tekil/çoğul ayrımı yok.
        switch (hours, minutes) {
        case (0, let m): return "\(m) dakika"
        case (let h, 0): return "\(h) saat"
        case (let h, let m): return "\(h) saat \(m) dakika"
        }
    }

    /// A percentage, sign kept.
    ///
    /// Turkish writes the sign before the number: %34, not 34%. This wrote it after until
    /// v0.1's release scan, which put an English-ordered number in the middle of sixteen
    /// Turkish sentences — `percentTR` right beside it had the note explaining the rule.
    static func percent(_ fraction: Double) -> String {
        "%\(Int((fraction * 100).rounded()))"
    }

    /// A percentage as a magnitude, sign dropped.
    ///
    /// The difference from `percent` is the sign, not the writing order — both write %34.
    /// Callers use this where the direction is already in the sentence ("önceki en iyisinin
    /// %5 üstünde"), so a signed number would read "%-5 üstünde".
    static func percentTR(_ fraction: Double) -> String {
        "%\(Int((abs(fraction) * 100).rounded()))"
    }

    static func signed(_ value: Double, digits: Int) -> String {
        guard value.isFinite else { return "—" }
        let formatted = decimal(abs(value), digits: digits)
        if value > 0 { return "+\(formatted)" }
        if value < 0 { return "−\(formatted)" }
        return formatted
    }
}
