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

    // MARK: - 11 Tipografi Token'ı (Şartname Yasa 3 Açık Punto Rampası)

    /// Kahraman sayı: 64pt, .semibold, tracking -1.5, tabular (relativeTo: .largeTitle)
    static let heroNumeral = Font.system(size: 64, weight: .semibold, design: .default)
        .monospacedDigit()

    /// Kahraman birim: 17pt, .medium, ikincil renk (relativeTo: .headline)
    static let heroUnit = Font.system(size: 17, weight: .medium, design: .default)

    /// Ekran başlığı: 28pt, .bold, tracking -0.5 (relativeTo: .title)
    static let screenTitle = Font.system(size: 28, weight: .bold, design: .default)

    /// Bölüm başlığı: 17pt, .semibold (relativeTo: .headline)
    static let sectionTitle = Font.system(size: 17, weight: .semibold, design: .default)

    /// Metrik sayısı: 30pt, .medium, tracking -0.5, tabular (relativeTo: .title2)
    static let metricNumeral = Font.system(size: 30, weight: .medium, design: .default)
        .monospacedDigit()

    /// Metrik birimi: 12pt, .medium, üçüncül renk (relativeTo: .caption)
    static let metricUnit = Font.system(size: 12, weight: .medium, design: .default)

    /// Gövde metni: 16pt, .regular (relativeTo: .body)
    static let body = Font.system(size: 16, weight: .regular, design: .default)

    /// İkincil metin: 14pt, .regular, ikincil renk (relativeTo: .subheadline)
    static let secondary = Font.system(size: 14, weight: .regular, design: .default)

    /// Etiket: 12pt, .medium (relativeTo: .caption)
    static let label = Font.system(size: 12, weight: .medium, design: .default)

    /// Bölüm üstü teknik etiket (eyebrow): 11pt, .semibold, BÜYÜK HARF, tracking +0.8, monospaced, üçüncül (relativeTo: .caption2)
    static let eyebrow = Font.system(size: 11, weight: .semibold, design: .monospaced)

    /// Açıklama ve dipnot metni: 12pt, .regular, üçüncül renk (relativeTo: .caption)
    static let caption = Font.system(size: 12, weight: .regular, design: .default)

    // MARK: - Eski İsimlerle Geriye Dönük Uyumluluk Takma Adları

    static let title = screenTitle
    static let verdict = sectionTitle
    static let headline = sectionTitle
    static let callout = secondary
    static let footnote = caption
    static let displayValue = heroNumeral
    static let metricValue = metricNumeral
    static let dataValue = Font.system(size: 14, weight: .semibold, design: .default).monospacedDigit()
    static let unit = metricUnit
    static let caption2 = label

    /// Yayın içindeki ana okuma sayısı.
    static func arcValue(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .default)
            .monospacedDigit()
    }

    // MARK: - Dynamic Type Ölçekleme Yardımcısı (ViewModifier)

    struct Scaled: ViewModifier {
        @ScaledMetric var size: CGFloat
        let weight: Font.Weight
        let design: Font.Design

        init(size: CGFloat, relativeTo: Font.TextStyle, weight: Font.Weight = .regular, design: Font.Design = .default) {
            self._size = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
            self.weight = weight
            self.design = design
        }

        func body(content: Content) -> some View {
            content.font(.system(size: size, weight: weight, design: design))
        }
    }
}

extension View {

    func heroNumeral() -> some View {
        modifier(ZenithiumFont.Scaled(size: 64, relativeTo: .largeTitle, weight: .semibold, design: .default))
            .tracking(-1.5)
            .monospacedDigit()
    }

    func heroUnit() -> some View {
        modifier(ZenithiumFont.Scaled(size: 17, relativeTo: .headline, weight: .medium, design: .default))
            .foregroundStyle(ZenithiumColor.textSecondary)
    }

    func screenTitle() -> some View {
        modifier(ZenithiumFont.Scaled(size: 28, relativeTo: .title, weight: .bold, design: .default))
            .tracking(-0.5)
    }

    func sectionTitle() -> some View {
        modifier(ZenithiumFont.Scaled(size: 17, relativeTo: .headline, weight: .semibold, design: .default))
            .foregroundStyle(ZenithiumColor.textPrimary)
    }

    func metricNumeral() -> some View {
        modifier(ZenithiumFont.Scaled(size: 30, relativeTo: .title2, weight: .medium, design: .default))
            .tracking(-0.5)
            .monospacedDigit()
    }

    func metricUnit() -> some View {
        modifier(ZenithiumFont.Scaled(size: 12, relativeTo: .caption, weight: .medium, design: .default))
            .foregroundStyle(ZenithiumColor.textTertiary)
    }

    func zenithiumBody() -> some View {
        modifier(ZenithiumFont.Scaled(size: 16, relativeTo: .body, weight: .regular, design: .default))
            .foregroundStyle(ZenithiumColor.textPrimary)
    }

    func zenithiumSecondary() -> some View {
        modifier(ZenithiumFont.Scaled(size: 14, relativeTo: .subheadline, weight: .regular, design: .default))
            .foregroundStyle(ZenithiumColor.textSecondary)
    }

    func zenithiumLabel() -> some View {
        modifier(ZenithiumFont.Scaled(size: 12, relativeTo: .caption, weight: .medium, design: .default))
            .foregroundStyle(ZenithiumColor.textSecondary)
    }

    func zenithiumCallout() -> some View {
        modifier(ZenithiumFont.Scaled(size: 15, relativeTo: .callout, weight: .regular, design: .default))
            .foregroundStyle(ZenithiumColor.textSecondary)
    }

    func zenithiumEyebrow() -> some View {
        modifier(ZenithiumFont.Scaled(size: 11, relativeTo: .caption2, weight: .semibold, design: .monospaced))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(ZenithiumColor.textTertiary)
    }

    func zenithiumCaption() -> some View {
        modifier(ZenithiumFont.Scaled(size: 12, relativeTo: .caption, weight: .regular, design: .default))
            .foregroundStyle(ZenithiumColor.textTertiary)
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
