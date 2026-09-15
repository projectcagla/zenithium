import SwiftUI

enum ZenithiumFont {

    // MARK: - 11 Tipografi Token'ı (Şartname Yasa 3 Açık Punto Rampası)

    /// Kahraman sayı: 68pt, .bold, rounded, tracking -1.5, tabular (relativeTo: .largeTitle)
    static let heroNumeral = Font.system(size: 68, weight: .bold, design: .rounded)
        .monospacedDigit()

    /// Kahraman birim: 20pt, .medium, ikincil renk (relativeTo: .headline)
    static let heroUnit = Font.system(size: 20, weight: .medium, design: .default)

    /// Ekran başlığı: 28pt, .bold, tracking -0.5 (relativeTo: .title)
    static let screenTitle = Font.system(size: 28, weight: .bold, design: .default)

    /// Bölüm başlığı: 22pt, .semibold (relativeTo: .headline)
    static let sectionTitle = Font.system(size: 22, weight: .semibold, design: .default)

    /// Metrik sayısı: 30pt, .semibold, tracking -0.5, tabular (relativeTo: .title2)
    static let metricNumeral = Font.system(size: 30, weight: .semibold, design: .rounded)
        .monospacedDigit()

    /// Metrik birimi: 12pt, .medium, üçüncül renk (relativeTo: .caption)
    static let metricUnit = Font.system(size: 12, weight: .medium, design: .default)

    /// Gövde metni: 16pt, .regular (relativeTo: .body)
    static let body = Font.system(size: 16, weight: .regular, design: .default)

    /// İkincil metin: 14pt, .regular, ikincil renk (relativeTo: .subheadline)
    static let secondary = Font.system(size: 14, weight: .regular, design: .default)

    /// Etiket: 12pt, .medium (relativeTo: .caption)
    static let label = Font.system(size: 12, weight: .medium, design: .default)

    /// Bölüm üstü teknik etiket (eyebrow): 11pt, .bold, BÜYÜK HARF, tracking +1.2, ikincil (relativeTo: .caption2)
    static let eyebrow = Font.system(size: 11, weight: .bold, design: .default)

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
        .system(size: size, weight: .bold, design: .rounded)
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
        modifier(ZenithiumFont.Scaled(size: 68, relativeTo: .largeTitle, weight: .bold, design: .rounded))
            .tracking(-1.5)
            .monospacedDigit()
    }

    func heroUnit() -> some View {
        modifier(ZenithiumFont.Scaled(size: 20, relativeTo: .headline, weight: .medium, design: .default))
            .foregroundStyle(ZenithiumColor.textSecondary)
    }

    func screenTitle() -> some View {
        modifier(ZenithiumFont.Scaled(size: 28, relativeTo: .title, weight: .bold, design: .default))
            .tracking(-0.5)
    }

    func sectionTitle() -> some View {
        modifier(ZenithiumFont.Scaled(size: 22, relativeTo: .headline, weight: .semibold, design: .default))
            .foregroundStyle(ZenithiumColor.textPrimary)
    }

    func metricNumeral() -> some View {
        modifier(ZenithiumFont.Scaled(size: 30, relativeTo: .title2, weight: .semibold, design: .rounded))
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
        modifier(ZenithiumFont.Scaled(size: 11, relativeTo: .caption2, weight: .bold, design: .default))
            .textCase(.uppercase)
            .environment(\.locale, Locale(identifier: "tr_TR"))
            .tracking(1.2)
            .foregroundStyle(ZenithiumColor.textSecondary)
    }

    func zenithiumCaption() -> some View {
        modifier(ZenithiumFont.Scaled(size: 12, relativeTo: .caption, weight: .regular, design: .default))
            .foregroundStyle(ZenithiumColor.textTertiary)
    }
}
