//
//  SpectralField.swift
//  Zenithium
//
//  Ambiyans katmanı — anodize spektrumun çok yavaş kayan bir mesh gradyanı.
//
//  ASSUMPTION DESIGN-4: bu katman *durumu taşımaz*, ortamı taşır. Bant rengi asla buraya
//  karışmaz; bir okuma değil, bir ışıktır. Fark edilmemeli, yokluğu hissedilmeli.
//
//  iOS 18'in `MeshGradient`'ı kullanılıyor. Hareket 30 saniyelik bir döngüde, genlik çok
//  düşük; `prefers-reduced-motion` açıkken tamamen duruyor.
//

import SwiftUI

struct SpectralField: View {

    /// Merceğin ambiyans tonu — uygulamanın ışığı personaya göre değişir.
    var tint: Color = ZenithiumColor.spectrumViolet

    /// Katmanın genel yoğunluğu. Ana ekranlarda düşük, karşılama ekranlarında yüksek.
    var intensity: Double = 0.55

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 3,
                height: 3,
                points: meshPoints(at: t),
                colors: meshColors
            )
            .opacity(intensity)
            .blur(radius: 28)
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Orta sıradaki üç nokta çok yavaş salınır; köşeler sabit kalır ki alan kaymasın.
    private func meshPoints(at time: TimeInterval) -> [SIMD2<Float>] {
        let period = 30.0
        let angle = time.truncatingRemainder(dividingBy: period) / period * 2 * .pi
        let dx = Float(sin(angle) * 0.055)
        let dy = Float(cos(angle * 0.7) * 0.04)

        return [
            SIMD2(0.0, 0.0), SIMD2(0.5 + dx, 0.0), SIMD2(1.0, 0.0),
            SIMD2(0.0, 0.5 - dy), SIMD2(0.5 - dx, 0.5 + dy), SIMD2(1.0, 0.5 + dy),
            SIMD2(0.0, 1.0), SIMD2(0.5 + dx, 1.0), SIMD2(1.0, 1.0)
        ]
    }

    /// Üstte spektrum, altta zemin — alan yukarıdan aşağı söner, içerik hep okunur kalır.
    private var meshColors: [Color] {
        [
            ZenithiumColor.spectrumIndigo, tint, ZenithiumColor.spectrumIndigo,
            tint.opacity(0.5), ZenithiumColor.spectrumIndigo.opacity(0.45), tint.opacity(0.35),
            ZenithiumColor.background, ZenithiumColor.background, ZenithiumColor.background
        ]
    }
}

/// Ekran zemini: siyah + üstünde spektral alan.
struct ZenithiumBackground: ViewModifier {

    var tint: Color = ZenithiumColor.spectrumViolet
    var intensity: Double = 0.4

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    ZenithiumColor.background
                    SpectralField(tint: tint, intensity: intensity)
                }
                .ignoresSafeArea()
            }
            .tint(ZenithiumColor.accent)
    }
}

extension View {

    /// Uygulamanın standart zemini.
    func zenithiumBackground(
        tint: Color = ZenithiumColor.spectrumViolet,
        intensity: Double = 0.4
    ) -> some View {
        modifier(ZenithiumBackground(tint: tint, intensity: intensity))
    }

    /// Merceğe göre tonlanmış zemin.
    func zenithiumBackground(for lens: TrainingLens) -> some View {
        modifier(ZenithiumBackground(tint: ZenithiumColor.ambientTint(for: lens), intensity: 0.4))
    }
}
