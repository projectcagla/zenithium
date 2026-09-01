//
//  ZenithiumColor.swift
//  Zenithium
//
//  Anodize titanyum paleti. Tasarım yönü v1 (docs/design-direction.html).
//
//  İsimden türetilmiş bir palet: titanyum anodize edildiğinde açıya göre indigodan
//  menekşeye, magentadan kehribara kayar. Bu, "OLED siyahı + tek neon vurgu" varsayılanından
//  bilinçli bir kaçış — o kombinasyon her sağlık uygulamasında var.
//
//  Kritik ayrım (ASSUMPTION DESIGN-1): **spektrum büyük ambiyans yüzeylerinde, semantik renk
//  küçük kesin göstergelerde.** İyi bir aletin ekranı güzeldir, göstergesi kesindir. Bant
//  rengi asla ambiyansa karışmaz, çünkü ambiyans bir okuma değildir.
//
//  Siyah zemine karşı ölçülmüş kontrast oranları — hepsi §10'un 4.5:1 eşiğinin üstünde:
//      hazır  #3FCF8E → 10.5:1        orta   #F0B23F → 11.1:1
//      düşük  #EF5560 →  6.1:1        teal   #3ED0BE → 10.9:1
//      birincil metin #E9EDF5 → 17.8:1    ikincil metin #8C96AB → 7.2:1
//

import SwiftUI

enum ZenithiumColor {

    /// A colour from the asset catalog, resolved against the appearance in force when it is
    /// drawn.
    ///
    /// Every name below goes through here rather than holding a literal. That is what lets
    /// these stay `static` properties while still following the appearance: a static property
    /// has no environment to read, and a catalog colour does not need one.
    /// Yol haritası v4, B6.
    private static func asset(_ asset: ZenithiumColorAsset) -> Color { asset.color }

    // MARK: - Zemin

    /// Mavi eğilimli near-black. Saf siyah değil — seçilmiş bir nötr, miras alınmış değil.
    /// OLED'de pikselleri hâlâ neredeyse tamamen kapatır.
    static var background: Color { asset(.background) }

    static var surface: Color { asset(.surface) }
    static var surfaceElevated: Color { asset(.surfaceElevated) }

    static var hairline: Color { asset(.hairline) }
    static var hairlineSoft: Color { asset(.hairlineSoft) }

    // MARK: - Anodize spektrum

    /// Derin indigo — spektrumun en soğuk ucu.
    static var spectrumIndigo: Color { asset(.spectrumIndigo) }

    static var spectrumViolet: Color { asset(.spectrumViolet) }
    static var spectrumMagenta: Color { asset(.spectrumMagenta) }
    static var spectrumAmber: Color { asset(.spectrumAmber) }
    static var spectrumTeal: Color { asset(.spectrumTeal) }

    /// Etkileşim vurgusu. Spektrumun teal ucundan, biraz daha parlak.
    static var accent: Color { asset(.accent) }

    /// Ambiyans katmanının mesh noktalarına beslenen sıra.
    static var spectrumRamp: [Color] {
        [spectrumIndigo, spectrumViolet, spectrumMagenta, spectrumAmber, spectrumTeal]
    }

    // MARK: - Metin

    static var textPrimary: Color { asset(.textPrimary) }
    static var textSecondary: Color { asset(.textSecondary) }
    static var textTertiary: Color { asset(.textTertiary) }

    // MARK: - Semantik

    /// Mineral yeşil. iOS sistem yeşilinden daha soğuk, palete ait.
    static var green: Color { asset(.green) }

    static var yellow: Color { asset(.yellow) }
    static var red: Color { asset(.red) }

    // MARK: - Eşleştirmeler

    static func color(for band: RecoveryBand) -> Color {
        switch band {
        case .green: return green
        case .yellow: return yellow
        case .red: return red
        }
    }

    /// Yayın dolmamış kısmı: hairline üstünde, bant renginin çok soluk bir izi.
    static func trackColor(for band: RecoveryBand) -> Color {
        color(for: band).opacity(0.14)
    }

    /// Yayın süpürdüğü gradyan.
    ///
    /// Spektrumun soğuk ucundan bandın kendi rengine gider — yani yay boyunca *ilerleme*
    /// hissi verir ama vardığı yer semantik olarak doğru rengi taşır. Kırmızıdan yeşile
    /// süpüren bir gradyan, sayının sahip olmadığı bir ölçeği ima ederdi.
    static func arcGradient(for band: RecoveryBand) -> Gradient {
        Gradient(colors: [
            spectrumIndigo.opacity(0.55),
            spectrumViolet.opacity(0.75),
            color(for: band),
            color(for: band)
        ])
    }

    /// Zorlanma yayı — bantlı değil, o yüzden spektrumun kendi rampasını kullanır.
    static var strainGradient: Gradient { Gradient(colors: [
        spectrumIndigo.opacity(0.55),
        spectrumViolet.opacity(0.7),
        spectrumTeal,
        accent
    ]) }

    /// Uyku yayı — gecenin rengi, magentaya doğru.
    static var sleepGradient: Gradient { Gradient(colors: [
        spectrumIndigo.opacity(0.55),
        spectrumViolet,
        spectrumMagenta
    ]) }

    /// Bir personanın ambiyans tonu. Mercek değiştiğinde uygulamanın ışığı da değişir.
    static func ambientTint(for lens: TrainingLens) -> Color {
        switch lens {
        case .endurance: return spectrumViolet
        case .hybrid: return spectrumMagenta
        case .strength: return spectrumAmber
        case .health: return spectrumIndigo
        }
    }

    static func color(for zone: HeartRateZone) -> Color {
        switch zone {
        case .zone1: return asset(.zoneOne)
        case .zone2: return spectrumTeal
        case .zone3: return green
        case .zone4: return yellow
        case .zone5: return spectrumAmber
        case .zone6: return red
        }
    }

    /// The band a live session is in.
    ///
    /// Here rather than beside either drawing, because three surfaces render it — the watch
    /// screen, the Dynamic Island and the Lock Screen card — and until v0.1 there were two
    /// copies of this switch: one private to `WatchLiveSessionView`, one in the widget's
    /// `LiveSessionStyle`, whose own comment said it existed so the island and the Lock
    /// Screen would agree. They agreed with each other and nothing made them agree with the
    /// watch. This file is already compiled by all three targets, so one copy reaches all
    /// three.
    static func color(for band: LiveSessionBand) -> Color {
        switch band {
        case .building: return accent
        case .nearing: return yellow
        case .beyond: return red
        case .unbounded: return textSecondary
        }
    }

    static func color(for stage: SleepStage) -> Color {
        switch stage {
        case .asleepDeep: return spectrumIndigo
        case .asleepREM: return spectrumViolet
        case .asleepCore, .asleepUnspecified: return asset(.coreSleep)
        case .awake: return spectrumAmber
        case .inBed: return hairline
        }
    }
}
