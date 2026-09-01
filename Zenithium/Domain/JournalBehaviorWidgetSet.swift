//
//  JournalBehaviorWidgetSet.swift
//  Zenithium
//
//  The behaviours the widget and the watch offer. Faz 22.
//
//  In `Domain` rather than beside either surface, and that placement is the point: three
//  targets read this list — the app's drain, the home-screen widget and the watch — and a
//  widget offering a behaviour the drain does not know about would have its taps silently
//  dropped. One list, three readers.
//
//  Four rather than all twelve. A medium widget fits four chips at a legible size, and these
//  are the four whose correlations turn up most often; the rest stay in the app, where there
//  is room for them.
//

import Foundation

enum JournalBehaviorWidgetSet {

    static let featured: [JournalBehavior] = [.alcohol, .lateCaffeine, .highStress, .lateMeal]
}
