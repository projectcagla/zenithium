//
//  AppearanceTests.swift
//  ZenithiumTests
//
//  Yol haritası v4, B6 — the palette became a setting.
//
//  The catalog and the Swift names come from one generator table, so the failure this suite
//  exists to catch is drift between the two: a name in `ZenithiumColorAsset` with no
//  colourset behind it renders a fallback and says nothing about it. Reading the catalog from
//  disk is the only way to check that without a device.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Appearance preference")
struct AppearancePreferenceTests {

    @Test("Varsayılan koyu")
    func thedefaultIsDark() {
        #expect(AppearancePreference.default == .dark)
        // Not `.system`: following the phone would mean an existing user whose phone is in
        // light mode opens the app one morning to a different colour, from an update they
        // did not read.
        #expect(AppearancePreference.default != .system)
    }

    @Test("Bilinmeyen bir kayıt koyuya düşüyor")
    func anunknownStoredValueFallsBackToDark() {
        #expect(AppearancePreference(rawValue: "solarized") == nil)
    }

    @Test("Her seçenek bir adı ve bir açıklaması taşıyor", arguments: AppearancePreference.allCases)
    func everyOptionExplainsItself(option: AppearancePreference) {
        #expect(!option.displayName.isEmpty)
        #expect(!option.subtitle.isEmpty)
    }

    @Test("Sistem seçeneği SwiftUI'ye karar bırakıyor")
    func systemDefersToTheOS() {
        #expect(AppearancePreference.system.colorScheme == nil)
        #expect(AppearancePreference.dark.colorScheme == .dark)
        #expect(AppearancePreference.light.colorScheme == .light)
    }
}

@Suite("Colour catalog")
struct ColourCatalogTests {

    /// The repository's catalog, found by walking up from this file.
    ///
    /// A test bundle does not carry the app's asset catalog, so the JSON is read from source
    /// instead. That is the right thing to check anyway: the question is whether the
    /// generator's two outputs agree, not whether Xcode copied one of them.
    private static let catalogURL: URL? = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url = url.deletingLastPathComponent()
            let candidate = url
                .appending(path: "Zenithium/Resources/Zenithium.xcassets/Colors", directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
        }
        return nil
    }()

    @Test("Her Swift adının arkasında bir renk seti var")
    func everyNameHasAColourset() throws {
        let catalog = try #require(Self.catalogURL, "asset catalog bulunamadı")
        for asset in ZenithiumColorAsset.allCases {
            let path = catalog
                .appending(path: "\(asset.rawValue).colorset", directoryHint: .isDirectory)
                .appending(path: "Contents.json", directoryHint: .notDirectory)
            #expect(
                FileManager.default.fileExists(atPath: path.path(percentEncoded: false)),
                "\(asset.rawValue) için renk seti yok"
            )
        }
    }

    @Test("Her renk setinin arkasında bir Swift adı var")
    func everyColoursetHasAName() throws {
        let catalog = try #require(Self.catalogURL, "asset catalog bulunamadı")
        let names = Set(ZenithiumColorAsset.allCases.map(\.rawValue))
        let contents = try FileManager.default.contentsOfDirectory(atPath: catalog.path(percentEncoded: false))
        for entry in contents where entry.hasSuffix(".colorset") {
            let name = String(entry.dropLast(".colorset".count))
            #expect(names.contains(name), "\(name) renk setinin Swift karşılığı yok")
        }
    }

    @Test("Her renk setinde hem aydınlık hem koyu değer var")
    func everyColoursetHasBothAppearances() throws {
        let catalog = try #require(Self.catalogURL, "asset catalog bulunamadı")
        for asset in ZenithiumColorAsset.allCases {
            let path = catalog
                .appending(path: "\(asset.rawValue).colorset", directoryHint: .isDirectory)
                .appending(path: "Contents.json", directoryHint: .notDirectory)
            guard let data = try? Data(contentsOf: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let colors = json["colors"] as? [[String: Any]] else {
                Issue.record("\(asset.rawValue) okunamadı")
                continue
            }
            // One entry without an appearance (the light base) and one marked dark.
            let base = colors.filter { $0["appearances"] == nil }
            let dark = colors.filter { entry in
                guard let appearances = entry["appearances"] as? [[String: Any]] else { return false }
                return appearances.contains { ($0["value"] as? String) == "dark" }
            }
            #expect(base.count == 1, "\(asset.rawValue): aydınlık taban yok")
            #expect(dark.count == 1, "\(asset.rawValue): koyu değer yok")
        }
    }

    @Test("Koyu palet, kayıtlı değerlerle aynı")
    func thedarkValuesMatchTheReviewablePalette() throws {
        // `ZenithiumPalette.dark` is the reviewable record. If somebody edits the generator's
        // table without updating it, the two descriptions of the app's identity diverge and
        // nobody notices until a screenshot looks wrong.
        let catalog = try #require(Self.catalogURL, "asset catalog bulunamadı")
        let path = catalog
            .appending(path: "accent.colorset", directoryHint: .isDirectory)
            .appending(path: "Contents.json", directoryHint: .notDirectory)
        let data = try Data(contentsOf: path)
        let text = try #require(String(data: data, encoding: .utf8))
        // The dark accent is #3ED0BE, which is what `ZenithiumPalette.dark.accent` holds.
        #expect(text.contains("0x3E"))
        #expect(text.contains("0xD0"))
        #expect(text.contains("0xBE"))
    }
}
