//
//  ZenithiumWidgetBundle.swift
//  ZenithiumWidgets
//
//  The widget extension's entry point. Spec §10.
//
//  Every widget the extension defines has to be listed here. `JournalWidget` and
//  `RecoveryControlWidget` were written in Faz 22 and never added, which meant neither could
//  appear on a device however correct its code was — a widget that is not in the bundle does
//  not exist. Both are registered now, along with the two Lock Screen families added in
//  Yol haritası v4, C10.
//

import WidgetKit
import SwiftUI

@main
struct ZenithiumWidgetBundle: WidgetBundle {

    var body: some Widget {
        // Home Screen.
        RecoveryStrainWidget()
        ThreeDayTrendWidget()
        JournalWidget()

        // Lock Screen. Three families, three questions — see `LockScreenWidgets`.
        RecoveryCircularWidget()
        RecoveryRectangularWidget()
        RecoveryInlineWidget()

        // Control Centre and the Action button.
        RecoveryControlWidget()

        // The Lock Screen and Dynamic Island card for a session running on the watch.
        // Yol haritası v4, C10.
        #if canImport(ActivityKit)
        LiveSessionActivity()
        #endif
    }
}
