//
//  NumberFormattingTests.swift
//  ZenithiumTests
//
//  How the app writes a number, pinned.
//
//  Until v0.1's release scan it wrote `12.3`. `String(format:)` is C's formatter and always
//  emits a period, whatever the device's region is set to — so every decimal in a Turkish
//  interface came out in English notation, in an app whose own copy types `12,4` and whose
//  lab parser was written specifically to accept the comma form because that is what Turkish
//  laboratory reports print.
//
//  The percent sign had the mirror of the same problem: `34%` where Turkish writes `%34`,
//  with a second function right beside it carrying the note that explains the rule.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Sayı yazımı")
struct NumberFormattingTests {

    // MARK: - Ondalık ayırıcı

    @Test("Ondalık ayırıcı virgül", arguments: [
        (12.34, 1, "12,3"),
        (0.5, 2, "0,50"),
        (-3.75, 1, "-3,8"),
        (100.0, 0, "100"),
        (7.0, 1, "7,0")
    ])
    func decimalsUseAComma(value: Double, digits: Int, expected: String) {
        #expect(ZenithiumFormat.metric(value, digits: digits) == expected)
    }

    @Test("Zorlanma tek ondalıkla ve virgülle yazılıyor")
    func strainIsWrittenWithAComma() {
        #expect(ZenithiumFormat.strain(12.34) == "12,3")
        #expect(ZenithiumFormat.strain(0) == "0,0")
        #expect(ZenithiumFormat.strain(21) == "21,0")
    }

    /// Nothing in the app should ever put a period in a decimal, which is the single check
    /// that would have caught the original bug wherever it appeared.
    @Test("Hiçbir ondalık nokta içermiyor", arguments: [0.0, 1.5, 12.34, 99.99, 1234.5, -0.25])
    func noDecimalContainsAPeriod(value: Double) {
        for digits in 0...3 {
            #expect(!ZenithiumFormat.metric(value, digits: digits).contains("."), "\(value)/\(digits)")
        }
        #expect(!ZenithiumFormat.strain(value).contains("."))
        #expect(!ZenithiumFormat.signed(value, digits: 2).contains("."))
    }

    // MARK: - İşaretli değerler

    @Test("İşaretli değer yönünü gösteriyor")
    func signedValuesCarryTheirDirection() {
        #expect(ZenithiumFormat.signed(0.25, digits: 2) == "+0,25")
        #expect(ZenithiumFormat.signed(-0.25, digits: 2) == "−0,25")
        #expect(ZenithiumFormat.signed(0, digits: 2) == "0,00")
    }

    // MARK: - Sonlu olmayan değerler

    /// `String(format:)` prints `nan` and `inf`. Both were reachable — a ratio over an empty
    /// window is one division away — and both would have gone on screen as those words.
    @Test("Sonlu olmayan değerler boş göstergeye düşüyor")
    func nonFiniteValuesFallBackToTheEmptyMarker() {
        for value in [Double.nan, .infinity, -.infinity] {
            #expect(ZenithiumFormat.metric(value, digits: 1) == "—")
            #expect(ZenithiumFormat.strain(value) == "—")
            #expect(ZenithiumFormat.signed(value, digits: 1) == "—")
        }
        #expect(ZenithiumFormat.pace(secondsPerKilometre: .nan) == "—")
    }

    // MARK: - Yüzde

    @Test("Yüzde işareti sayının önünde")
    func thePercentSignComesFirst() {
        #expect(ZenithiumFormat.percent(0.34) == "%34")
        #expect(ZenithiumFormat.percent(1) == "%100")
        #expect(ZenithiumFormat.percent(0) == "%0")
    }

    /// The two percent helpers differ by sign, not by writing order — which is what their
    /// names failed to say when one of them wrote `34%`.
    @Test("İki yüzde yardımcısı yalnızca işarette ayrılıyor")
    func theTwoPercentHelpersDifferOnlyInSign() {
        #expect(ZenithiumFormat.percent(0.34) == ZenithiumFormat.percentTR(0.34))
        #expect(ZenithiumFormat.percent(-0.34) == "%-34")
        #expect(ZenithiumFormat.percentTR(-0.34) == "%34")
    }

    // MARK: - Süreler

    /// Durations are not decimals and must not pick up a comma from the change above.
    @Test("Saat biçimleri iki nokta üst üste ile yazılmayı sürdürüyor")
    func clockFormatsKeepTheirColon() {
        #expect(ZenithiumFormat.clock(seconds: 305) == "5:05")
        #expect(ZenithiumFormat.longClock(seconds: 3_725) == "1:02:05")
        #expect(ZenithiumFormat.pace(secondsPerKilometre: 285) == "4:45/km")
        #expect(ZenithiumFormat.duration(seconds: 3_900) == "1sa 5dk")
        #expect(ZenithiumFormat.duration(seconds: 600) == "10dk")
    }

    @Test("Sesli süre Türkçede çoğul eki almıyor")
    func spokenDurationsDoNotPluralize() {
        #expect(ZenithiumFormat.spokenDuration(seconds: 60) == "1 dakika")
        #expect(ZenithiumFormat.spokenDuration(seconds: 7_200) == "2 saat")
        #expect(ZenithiumFormat.spokenDuration(seconds: 3_900) == "1 saat 5 dakika")
    }
}
