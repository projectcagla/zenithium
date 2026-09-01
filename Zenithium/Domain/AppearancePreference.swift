//
//  AppearancePreference.swift
//  Zenithium
//
//  Which palette the app draws in. Yol haritası v4, B6.
//
//  Dark is the default and stays the app's identity — a screen read at five in the morning
//  before a run, and a spectrum built to glow against near-black. What changed is that it is
//  now a setting rather than the only possibility.
//
//  The default is `.dark` rather than `.system` on purpose. Following the system would mean
//  every existing user whose phone is in light mode opens the app one morning to find it a
//  different colour, which is a change nobody asked for delivered by an update they did not
//  read. Somebody who wants light can choose it.
//

import Foundation

/// The appearance the app draws in.
enum AppearancePreference: String, Sendable, Codable, CaseIterable, Hashable, Identifiable {

    /// The app's own dark palette, whatever the phone is set to. The default.
    case dark

    /// The light palette.
    case light

    /// Follow the phone.
    case system

    var id: String { rawValue }

    /// The default for a new install and for a profile written before this existed.
    static let `default` = AppearancePreference.dark

    var displayName: String {
        switch self {
        case .dark: return "Koyu"
        case .light: return "Aydınlık"
        case .system: return "Sistem"
        }
    }

    var subtitle: String {
        switch self {
        case .dark: return "Uygulamanın kendi paleti"
        case .light: return "Gün ışığı için"
        case .system: return "Telefonun ayarını izler"
        }
    }
}
