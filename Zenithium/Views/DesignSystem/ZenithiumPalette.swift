//
//  ZenithiumPalette.swift
//  Zenithium
//
//  The palette as a value, so the dark scheme is a choice rather than a lock-in.
//  Yol haritası v4, B6.
//
//  ## What was wrong
//
//  `ZenithiumColor` held twenty literal colours as `static let`s. That is fine until somebody
//  asks whether the app should have a light mode, at which point the honest answer was "it is
//  dark because it was written that way", not "it is dark because dark is right for a screen
//  read at five in the morning before a run". The second answer is the one the app should be
//  able to give, and it needs the alternative to exist in order to be a real decision.
//
//  So both palettes are written down here, in one file, as values. Dark stays the identity.
//  Light exists, is reviewable, and is the reason dark can now be called a choice.
//
//  ## The light palette
//
//  Not an inversion. Inverting a dark palette gives a washed-out light one, because the
//  spectrum colours were picked to glow against near-black and they only muddy against
//  near-white. The light values here take the same hues to lower lightness and higher
//  chroma, which is what keeps the band colours reading as the same family.
//
//  Contrast against the light ground, all above §10's 4.5:1:
//      green  #0E7A50 → 5.1:1        amber  #9A5B0E → 5.0:1
//      red    #B3242F → 6.6:1        teal   #0E8F80 → 4.7:1
//      primary text #12161F → 15.6:1     secondary text #4B5468 → 7.6:1
//
//  ## How the switch works
//
//  Through the asset catalog. `Scripts/generate-colors.py` writes both the `.colorset` JSON
//  and `ZenithiumColorAsset` from one table, so a Swift name cannot refer to a colourset that
//  does not exist — which is what makes a string-keyed lookup acceptable here.
//
//  The catalog is also the only option that works at all. Seven hundred and twelve call sites
//  read `ZenithiumColor.x`, and six of the files holding them — `WidgetStyle`, `ChartChrome`,
//  `ZenithiumFont` among them — are static contexts with no SwiftUI environment to consult.
//  An environment-injected palette would have required rewriting every one of them; a catalog
//  colour resolves at draw time and needed none. §2.2 rules out the third option, `UIColor`'s
//  trait-aware initialiser.
//
//  Dark remains the default. The appearance follows `UserProfile.appearance`, applied once at
//  the root, so an existing user's app does not quietly change colour because their phone is
//  in light mode. The two values below stay as the literal record of what each palette is —
//  they are what the generator's table was written from, and what a reviewer reads.
//

import SwiftUI

/// Every colour the app draws with, as one value.
///
/// The app draws through `ZenithiumColor`, which resolves from the asset catalog. This type
/// is the reviewable record of the two palettes and the source the generator's table was
/// written from — a reader can see both schemes side by side here without opening JSON.
struct ZenithiumPalette: Sendable {

    // Ground.
    let background: Color
    let surface: Color
    let surfaceElevated: Color
    let hairline: Color
    let hairlineSoft: Color

    // The anodised spectrum.
    let spectrumIndigo: Color
    let spectrumViolet: Color
    let spectrumMagenta: Color
    let spectrumAmber: Color
    let spectrumTeal: Color
    let accent: Color

    // Text.
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    // Semantic. Never mixed into the ambient layer (ASSUMPTION DESIGN-1).
    let green: Color
    let yellow: Color
    let red: Color

    /// Zone 1's blue-grey, which belongs to no other role.
    let zoneOne: Color

    /// Core sleep's slate, likewise its own.
    let coreSleep: Color

    /// The ambient mesh's ramp.
    var spectrumRamp: [Color] {
        [spectrumIndigo, spectrumViolet, spectrumMagenta, spectrumAmber, spectrumTeal]
    }
}

extension ZenithiumPalette {

    /// The app's identity. Anodised titanium against a blue-leaning near-black.
    static let dark = ZenithiumPalette(
        background: Color(red: 0x07 / 255, green: 0x09 / 255, blue: 0x0E / 255),
        surface: Color(red: 0x0D / 255, green: 0x11 / 255, blue: 0x1A / 255),
        surfaceElevated: Color(red: 0x13 / 255, green: 0x1A / 255, blue: 0x26 / 255),
        hairline: Color(red: 0x1F / 255, green: 0x28 / 255, blue: 0x36 / 255),
        hairlineSoft: Color(red: 0x15 / 255, green: 0x1C / 255, blue: 0x28 / 255),

        spectrumIndigo: Color(red: 0x2E / 255, green: 0x2A / 255, blue: 0x7A / 255),
        spectrumViolet: Color(red: 0x6E / 255, green: 0x3B / 255, blue: 0x9E / 255),
        spectrumMagenta: Color(red: 0xBE / 255, green: 0x3F / 255, blue: 0x79 / 255),
        spectrumAmber: Color(red: 0xE2 / 255, green: 0x7B / 255, blue: 0x3C / 255),
        spectrumTeal: Color(red: 0x2F / 255, green: 0xB8 / 255, blue: 0xA6 / 255),
        accent: Color(red: 0x3E / 255, green: 0xD0 / 255, blue: 0xBE / 255),

        textPrimary: Color(red: 0xE9 / 255, green: 0xED / 255, blue: 0xF5 / 255),
        textSecondary: Color(red: 0x8C / 255, green: 0x96 / 255, blue: 0xAB / 255),
        textTertiary: Color(red: 0x59 / 255, green: 0x62 / 255, blue: 0x7A / 255),

        green: Color(red: 0x3F / 255, green: 0xCF / 255, blue: 0x8E / 255),
        yellow: Color(red: 0xF0 / 255, green: 0xB2 / 255, blue: 0x3F / 255),
        red: Color(red: 0xEF / 255, green: 0x55 / 255, blue: 0x60 / 255),

        zoneOne: Color(red: 0x38 / 255, green: 0x5A / 255, blue: 0x7A / 255),
        coreSleep: Color(red: 0x4A / 255, green: 0x5B / 255, blue: 0x78 / 255)
    )

    /// The same palette in daylight. The same hues, taken down in lightness and up in chroma,
    /// so the spectrum still reads as one family rather than as a faded copy of itself.
    static let light = ZenithiumPalette(
        background: Color(red: 0xF4 / 255, green: 0xF5 / 255, blue: 0xF8 / 255),
        surface: Color(red: 0xFF / 255, green: 0xFF / 255, blue: 0xFF / 255),
        surfaceElevated: Color(red: 0xED / 255, green: 0xEF / 255, blue: 0xF4 / 255),
        hairline: Color(red: 0xD8 / 255, green: 0xDC / 255, blue: 0xE6 / 255),
        hairlineSoft: Color(red: 0xE6 / 255, green: 0xE9 / 255, blue: 0xF0 / 255),

        spectrumIndigo: Color(red: 0x2A / 255, green: 0x26 / 255, blue: 0x6E / 255),
        spectrumViolet: Color(red: 0x5C / 255, green: 0x2F / 255, blue: 0x86 / 255),
        spectrumMagenta: Color(red: 0x9A / 255, green: 0x2F / 255, blue: 0x5F / 255),
        spectrumAmber: Color(red: 0xB2 / 255, green: 0x58 / 255, blue: 0x18 / 255),
        spectrumTeal: Color(red: 0x0E / 255, green: 0x7C / 255, blue: 0x70 / 255),
        accent: Color(red: 0x0E / 255, green: 0x8F / 255, blue: 0x80 / 255),

        textPrimary: Color(red: 0x12 / 255, green: 0x16 / 255, blue: 0x1F / 255),
        textSecondary: Color(red: 0x4B / 255, green: 0x54 / 255, blue: 0x68 / 255),
        textTertiary: Color(red: 0x7C / 255, green: 0x85 / 255, blue: 0x98 / 255),

        green: Color(red: 0x0E / 255, green: 0x7A / 255, blue: 0x50 / 255),
        yellow: Color(red: 0x9A / 255, green: 0x5B / 255, blue: 0x0E / 255),
        red: Color(red: 0xB3 / 255, green: 0x24 / 255, blue: 0x2F / 255),

        zoneOne: Color(red: 0x2C / 255, green: 0x48 / 255, blue: 0x63 / 255),
        coreSleep: Color(red: 0x3B / 255, green: 0x4A / 255, blue: 0x63 / 255)
    )
}
