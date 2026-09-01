//
//  ArcGauge.swift
//  Zenithium
//
//  İmza bileşen: açık yay ve işaretli zirve.
//
//  ASSUMPTION DESIGN-3: kapalı halka yerine 200 derecelik açık yay.
//  Gerekçe isimden geliyor — zenith bir yayın en yüksek noktasıdır, ve uygulamanın ölçtüğü
//  her şey zaten bir yaydır: sirkadiyen eğri yükselip alçalır, zorlanma gün boyunca tırmanır,
//  uyku bir gecelik kavistir. Kapalı halka ayrıca herkesin: Apple Activity, Whoop, Garmin.
//  Alttaki 160 derecelik açıklık aynı zamanda işlevsel — sayı yayın kucağına oturur, halkanın
//  içine sıkışmaz, ve AX5 boyutunda kırpılmak yerine aşağı doğru genişler.
//
//  Erişilebilirlik değişmedi: yay tek bir öğe, etiketi ve değeri var, bant sözle söyleniyor.
//

import SwiftUI

/// Yayın geometrisi. Tek yerde tanımlı, böylece her yay aynı yayın üstünde durur.
enum ArcGeometry {

    /// Yayın başladığı açı. 170° sol-alt, saat yönünde tepeden geçer.
    static let startDegrees: Double = 170

    /// Toplam süpürme. 200° → altta 160°'lik açıklık kalır.
    static let sweepDegrees: Double = 200

    /// 0…1 ilerleme için mutlak açı.
    static func degrees(atProgress progress: Double) -> Double {
        startDegrees + sweepDegrees * MathSupport.clamp(progress, 0, 1)
    }

    /// Açının yay üstündeki noktası.
    static func point(atDegrees degrees: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(
            x: center.x + radius * cos(radians),
            y: center.y + radius * sin(radians)
        )
    }
}

/// Yayın üstüne konabilecek sabit bir işaret — zorlanma tavanı gibi.
struct ArcMarker: Equatable {

    /// 0…1 yay boyunca konum.
    let progress: Double

    let color: Color

    /// Erişilebilirlik değerine eklenecek açıklama.
    let label: String
}

struct ArcGauge<Center: View>: View {

    /// 0…1. Üstündeki değerler tam yay olarak çizilir; başlık bunu söyler.
    let progress: Double

    let gradient: Gradient
    let trackColor: Color

    /// Yayın ucundaki zirve işareti — "buraya kadar geldin".
    var apexColor: Color?

    /// Yay üstündeki sabit işaretler.
    var markers: [ArcMarker] = []

    let accessibilityLabel: String
    let accessibilityValue: String

    @ViewBuilder let center: () -> Center

    @ScaledMetric(relativeTo: .largeTitle) private var strokeWidth: CGFloat = 16
    @ScaledMetric(relativeTo: .largeTitle) private var diameter: CGFloat = 232

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether the arc has finished its entrance.
    ///
    /// The arc used to appear already full, which threw away the one moment where the shape
    /// can say what it is: a value climbing a curve. It now writes itself in from zero on
    /// first appearance, once, and then only moves when the number moves. Yol haritası v4, B3.
    @State private var hasAppeared = false

    /// What the arc actually draws — zero until the entrance runs.
    private var drawnProgress: Double {
        guard !reduceMotion else { return MathSupport.clamp(progress, 0, 1) }
        return hasAppeared ? MathSupport.clamp(progress, 0, 1) : 0
    }

    var body: some View {
        ZStack {
            AnimatableArc(
                progress: drawnProgress,
                gradient: gradient,
                trackColor: trackColor,
                apexColor: apexColor,
                markers: markers,
                strokeWidth: strokeWidth
            )
            .frame(width: diameter, height: diameter)

            // Sayı yayın kucağına oturur — merkezden biraz aşağıda, açıklığın hizasında.
            center()
                .frame(maxWidth: diameter - strokeWidth * 2.4)
                .multilineTextAlignment(.center)
                .offset(y: diameter * 0.06)
        }
        .frame(width: diameter, height: diameter)
        .animation(
            reduceMotion ? nil : .spring(response: 0.72, dampingFraction: 0.82),
            value: drawnProgress
        )
        .onAppear { hasAppeared = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(fullAccessibilityValue)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var fullAccessibilityValue: String {
        guard !markers.isEmpty else { return accessibilityValue }
        let markerText = markers.map(\.label).joined(separator: ", ")
        return "\(accessibilityValue). \(markerText)"
    }
}

/// Çizilen yay. `Canvas`'ın kendi animasyon verisi olmadığı için `Animatable` ayrı bir
/// görünümde taşınıyor — yoksa yay zıplayarak değer değiştirir, yaylanmaz.
private struct AnimatableArc: View, Animatable {

    var progress: Double
    let gradient: Gradient
    let trackColor: Color
    let apexColor: Color?
    let markers: [ArcMarker]
    let strokeWidth: CGFloat

    /// `View` `@MainActor`, `Animatable.animatableData` ise nonisolated bir gereksinim.
    /// Erişimciler yalnızca bu değer tipinin kendi `Sendable` alanlarına dokunuyor.
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let inset = strokeWidth / 2 + 2
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            guard rect.width > 0, rect.height > 0 else { return }

            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2
            let style = StrokeStyle(lineWidth: strokeWidth, lineCap: .round)

            let start = Angle.degrees(ArcGeometry.startDegrees)
            let end = Angle.degrees(ArcGeometry.startDegrees + ArcGeometry.sweepDegrees)

            // Yol — dolmamış kısım.
            var track = Path()
            track.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
            context.stroke(track, with: .color(trackColor), style: style)

            // Sabit işaretler yayın *altında* çizilir ki dolgu üstlerinden geçebilsin.
            for marker in markers {
                let degrees = ArcGeometry.degrees(atProgress: marker.progress)
                let position = ArcGeometry.point(atDegrees: degrees, center: center, radius: radius)
                var tick = Path()
                let inner = ArcGeometry.point(
                    atDegrees: degrees, center: center, radius: radius - strokeWidth * 0.85
                )
                let outer = ArcGeometry.point(
                    atDegrees: degrees, center: center, radius: radius + strokeWidth * 0.85
                )
                tick.move(to: inner)
                tick.addLine(to: outer)
                context.stroke(
                    tick,
                    with: .color(marker.color),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                _ = position
            }

            guard progress > 0 else { return }

            // Dolgu.
            let filledEnd = Angle.degrees(ArcGeometry.degrees(atProgress: progress))
            var filled = Path()
            filled.addArc(center: center, radius: radius, startAngle: start, endAngle: filledEnd, clockwise: false)
            context.stroke(
                filled,
                with: .conicGradient(gradient, center: center, angle: start),
                style: style
            )

            // Zirve işareti — yayın ulaştığı en yüksek nokta.
            if let apexColor {
                let apex = ArcGeometry.point(
                    atDegrees: ArcGeometry.degrees(atProgress: progress),
                    center: center,
                    radius: radius
                )
                let dotRadius = strokeWidth * 0.42
                let ring = Path(ellipseIn: CGRect(
                    x: apex.x - dotRadius, y: apex.y - dotRadius,
                    width: dotRadius * 2, height: dotRadius * 2
                ))
                context.fill(ring, with: .color(ZenithiumColor.background))
                context.stroke(ring, with: .color(apexColor), lineWidth: 2.5)
            }
        }
    }
}

// MARK: - Hazır yaylar

/// Toparlanma yayı.
struct RecoveryArc: View {

    let score: Double
    let band: RecoveryBand
    let confidence: Double

    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 62

    var body: some View {
        ArcGauge(
            progress: score / 100,
            gradient: ZenithiumColor.arcGradient(for: band),
            trackColor: ZenithiumColor.trackColor(for: band),
            apexColor: ZenithiumColor.color(for: band),
            accessibilityLabel: "Toparlanma",
            accessibilityValue: accessibilityValue
        ) {
            VStack(spacing: ZenithiumSpacing.none) {
                Text(ZenithiumFormat.score(score))
                    .font(ZenithiumFont.arcValue(size: numeralSize))
                    .foregroundStyle(ZenithiumColor.textPrimary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: score)
                Text("%")
                    .font(ZenithiumFont.unit)
                    .foregroundStyle(ZenithiumColor.textSecondary)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: band)
    }

    private var accessibilityValue: String {
        var value = "yüzde \(ZenithiumFormat.score(score)), \(band.displayName) bandı"
        if confidence < 1 {
            value += ", hâlâ kalibrasyonda, \(ZenithiumFormat.percent(confidence)) güven"
        }
        return value
    }
}

/// Zorlanma yayı, tavan işaretiyle.
struct StrainArc: View {

    let strain: Double
    let ceiling: Double?

    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 62

    /// Yay her zaman 0–21 ölçeğini gösterir; tavan onun üstünde bir işaret olarak durur.
    ///
    /// Tavana göre normalize etmek, tavanı aştığında yayın nereye gideceğini belirsiz
    /// bırakırdı. Sabit ölçek + hareketli işaret hem dürüst hem okunaklı.
    private var progress: Double {
        MathSupport.clamp(strain / EngineConstants.Strain.scaleMax, 0, 1)
    }

    private var markers: [ArcMarker] {
        guard let ceiling, ceiling > 0 else { return [] }
        return [
            ArcMarker(
                progress: MathSupport.clamp(ceiling / EngineConstants.Strain.scaleMax, 0, 1),
                color: ZenithiumColor.yellow,
                label: "Hedef \(ZenithiumFormat.strain(ceiling))"
            )
        ]
    }

    private var hasExceededCeiling: Bool {
        guard let ceiling else { return false }
        return strain > ceiling
    }

    var body: some View {
        ArcGauge(
            progress: progress,
            gradient: ZenithiumColor.strainGradient,
            trackColor: ZenithiumColor.accent.opacity(0.13),
            apexColor: hasExceededCeiling ? ZenithiumColor.yellow : ZenithiumColor.accent,
            markers: markers,
            accessibilityLabel: "Gün zorlanması",
            accessibilityValue: accessibilityValue
        ) {
            VStack(spacing: ZenithiumSpacing.none) {
                Text(ZenithiumFormat.strain(strain))
                    .font(ZenithiumFont.arcValue(size: numeralSize))
                    .foregroundStyle(ZenithiumColor.textPrimary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: strain)
                if let ceiling {
                    Text("hedef \(ZenithiumFormat.strain(ceiling))")
                        .font(ZenithiumFont.unit)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hasExceededCeiling)
    }

    private var accessibilityValue: String {
        guard let ceiling else { return "21 üzerinden \(ZenithiumFormat.strain(strain))" }
        let relation = hasExceededCeiling ? "hedefi aştı" : "hedefi"
        return "\(ZenithiumFormat.strain(strain)), \(ZenithiumFormat.strain(ceiling)) \(relation)"
    }
}

/// Genel amaçlı yay — uyku, kas hazırlığı, herhangi bir 0–100 okuma.
struct ScoreArc: View {

    let score: Double
    let gradient: Gradient
    let tint: Color
    let caption: String?
    let accessibilityLabel: String
    let accessibilityValue: String

    @ScaledMetric(relativeTo: .largeTitle) private var numeralSize: CGFloat = 58

    var body: some View {
        ArcGauge(
            progress: score / 100,
            gradient: gradient,
            trackColor: tint.opacity(0.13),
            apexColor: tint,
            accessibilityLabel: accessibilityLabel,
            accessibilityValue: accessibilityValue
        ) {
            VStack(spacing: ZenithiumSpacing.none) {
                Text(ZenithiumFormat.score(score))
                    .font(ZenithiumFont.arcValue(size: numeralSize))
                    .foregroundStyle(ZenithiumColor.textPrimary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: score)
                if let caption {
                    Text(caption)
                        .font(ZenithiumFont.unit)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }
}
