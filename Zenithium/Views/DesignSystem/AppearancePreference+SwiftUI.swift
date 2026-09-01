//
//  AppearancePreference+SwiftUI.swift
//  Zenithium
//
//  The preference, as SwiftUI understands it. Yol haritası v4, B6.
//
//  Kept out of `Domain` so that layer stays on Foundation alone. `ColorScheme` is a SwiftUI
//  type and the preference itself is not — a setting is a setting whether or not anything is
//  being drawn.
//

import SwiftUI

extension AppearancePreference {

    /// What SwiftUI should be told. `nil` follows the phone.
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}
