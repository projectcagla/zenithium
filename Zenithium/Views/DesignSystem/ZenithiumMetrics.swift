//
//  ZenithiumMetrics.swift
//  Zenithium
//
//  The spacing and radius scale. Yol haritası v4, B1.
//
//  Colour and type were already tokenised; spacing was not. A sweep of the view layer found
//  fifteen distinct `spacing:` literals and nineteen distinct edge-inset literals — 8, 12 and
//  16 carrying most of the weight, and then a long tail of 1, 3, 5, 7, 9, 11, 13, 18, 20 and
//  26 that had accreted one screen at a time. On screen that tail does not read as variety;
//  it reads as things not quite lining up.
//
//  So: one scale, doubling from a 2pt half-step onto a 4pt grid, and everything rounds onto
//  it. Where rounding shifted a value by a couple of points, the old value was the accident
//  and the new one is the decision.
//
//  Named by role rather than by number. `ZenithiumSpacing.s` survives a future change to
//  what "small" measures; `8` does not.
//

import SwiftUI

/// The spacing scale. Every gap and inset in the app comes from here.
enum ZenithiumSpacing {

    /// Flush. Used where a divider or a background does the separating instead.
    static let none: CGFloat = 0

    /// 2pt — between a value and its unit, or a label and the chip around it.
    static let xxs: CGFloat = 2

    /// 4pt — within a single line of related elements.
    static let xs: CGFloat = 4

    /// 8pt — the default gap between stacked elements inside one card.
    static let s: CGFloat = 8

    /// 12pt — between distinct rows in a card, or between cards in a dense list.
    static let m: CGFloat = 12

    /// 16pt — a card's own inset, and the gap between cards.
    static let l: CGFloat = 16

    /// 24pt — between sections of a screen.
    static let xl: CGFloat = 24

    /// 32pt — around a screen's leading and trailing content, and above a first heading.
    static let xxl: CGFloat = 32

    /// 48pt — largest rhythm gap on the 4pt grid.
    static let xxxl: CGFloat = 48

    // MARK: - Şartname Yasa 5 Semantik Boşlukları (4pt Izgarası)
    /// Bölümler arası: 32pt
    static let sectionSpacing: CGFloat = 32
    /// Bölüm başlığı → içerik: 12pt
    static let sectionHeaderToContent: CGFloat = 12
    /// Kart içi dolgu: 20pt
    static let cardPadding: CGFloat = 20
    /// Satırlar arası: 12pt
    static let rowSpacing: CGFloat = 12
    /// Ekran kenarı: 20pt
    static let screenEdge: CGFloat = 20
}

/// The corner-radius scale, sized to sit concentrically inside the spacing scale.
enum ZenithiumRadius {

    /// 4pt — chips, pills and other type-height containers.
    static let small: CGFloat = 4

    /// 8pt — inner containers: a sparkline well, a code block, a progress track.
    static let medium: CGFloat = 8

    /// 12pt — cards.
    static let large: CGFloat = 12

    /// 20pt — sheets and full-bleed panels, where the radius has to survive being large.
    static let xLarge: CGFloat = 20
}
