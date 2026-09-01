//
//  LensMark.swift
//  Zenithium
//
//  The four lenses, drawn rather than borrowed. Yol haritası v4, B9.
//
//  ## Why not SF Symbols
//
//  The lens picker used `figure.run`, `figure.mixed.cardio` and friends. They are good
//  symbols and they are also on every fitness app in the store, which means the one screen
//  where Zenithium asks somebody what kind of athlete they are looked like every other app's
//  onboarding.
//
//  ## Why not a custom SF Symbol either
//
//  A custom symbol would inherit weight matching and Dynamic Type for free, which is a real
//  advantage. It also has to be an SVG conforming to Apple's template, with guides in exact
//  positions, authored in the SF Symbols app and verified by eye — and a symbol whose guides
//  are wrong renders misaligned rather than failing loudly. This file cannot be verified that
//  way here, so it takes the route the app already uses for the body map: geometry in code,
//  which the compiler checks and which scales the same on every surface.
//
//  ## The marks
//
//  Each is one idea, drawn from the measurement the lens is built on:
//
//  * **Endurance** — a single line, climbing then steady. A critical-speed curve.
//  * **Hybrid** — a line broken into segments with gaps. Run, station, run, station.
//  * **Strength** — a bar with weight at both ends, drawn as a barbell's silhouette.
//  * **Health** — a closed loop, because the health lens is the one that does not end at a
//    finish line.
//
//  They share a stroke weight and a 24×24 box, so they sit together and beside SF Symbols
//  without one looking heavier than the rest.
//

import SwiftUI

/// A drawn mark for a training lens.
struct LensMark: View {

    let lens: TrainingLens

    /// Matches the optical weight of an SF Symbol at `.medium`, so a row mixing the two does
    /// not look like two different sets.
    var lineWidth: CGFloat = 1.8

    /// Scales with the surrounding text, which is what an SF Symbol would have done.
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 22

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(
                dx: lineWidth, dy: lineWidth
            )
            guard rect.width > 0, rect.height > 0 else { return }

            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            for path in LensMarkGeometry.paths(for: lens, in: rect) {
                context.stroke(path, with: .color(.primary), style: style)
            }
        }
        .frame(width: side, height: side)
        // The mark carries no meaning the label beside it does not already carry.
        .accessibilityHidden(true)
    }
}

/// The marks' geometry, apart from the view so it can be tested without rendering.
enum LensMarkGeometry {

    /// The strokes making up a lens's mark, in `rect`.
    static func paths(for lens: TrainingLens, in rect: CGRect) -> [Path] {
        switch lens {
        case .endurance: return [enduranceCurve(in: rect)]
        case .hybrid: return hybridSegments(in: rect)
        case .strength: return strengthBar(in: rect)
        case .health: return [healthLoop(in: rect)]
        }
    }

    /// A speed–duration curve: steep, then flattening towards an asymptote.
    private static func enduranceCurve(in rect: CGRect) -> Path {
        var path = Path()
        let samples = 24
        for index in 0...samples {
            let t = Double(index) / Double(samples)
            // A decaying exponential settling above the floor — the shape of critical speed
            // against duration, which is the measurement this lens is built on.
            let y = 0.12 + 0.72 * exp(-3.1 * t)
            let point = CGPoint(
                x: rect.minX + rect.width * t,
                y: rect.minY + rect.height * y
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    /// Run, station, run, station — one line cut into four, with the gaps carrying the idea.
    private static func hybridSegments(in rect: CGRect) -> [Path] {
        // Alternating long and short runs, at alternating heights: the compromised-running
        // pattern the hybrid screen analyses.
        let spans: [(start: Double, end: Double, y: Double)] = [
            (0.00, 0.26, 0.76),
            (0.34, 0.50, 0.26),
            (0.58, 0.84, 0.76),
            (0.92, 1.00, 0.26)
        ]
        return spans.map { span in
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + rect.width * span.start, y: rect.minY + rect.height * span.y))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * span.end, y: rect.minY + rect.height * span.y))
            return path
        }
    }

    /// A barbell seen end-on: the shaft, and a plate at each end.
    private static func strengthBar(in rect: CGRect) -> [Path] {
        let midY = rect.midY
        var shaft = Path()
        shaft.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: midY))
        shaft.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: midY))

        // Plates as vertical strokes rather than rectangles, so the mark stays one weight
        // throughout instead of gaining a filled mass at each end.
        let plateHalf = rect.height * 0.30
        let innerHalf = rect.height * 0.17

        var plates = Path()
        for x in [rect.minX + rect.width * 0.10, rect.maxX - rect.width * 0.10] {
            plates.move(to: CGPoint(x: x, y: midY - plateHalf))
            plates.addLine(to: CGPoint(x: x, y: midY + plateHalf))
        }
        for x in [rect.minX + rect.width * 0.26, rect.maxX - rect.width * 0.26] {
            plates.move(to: CGPoint(x: x, y: midY - innerHalf))
            plates.addLine(to: CGPoint(x: x, y: midY + innerHalf))
        }
        return [shaft, plates]
    }

    /// A closed loop. The health lens is the one with no finish line.
    ///
    /// Deliberately not a heart: a heart glyph reads as cardiology, and this lens is about
    /// everything the watch measures rather than about one organ.
    private static func healthLoop(in rect: CGRect) -> Path {
        var path = Path()
        let samples = 48
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radiusX = rect.width * 0.42
        let radiusY = rect.height * 0.42

        for index in 0...samples {
            let angle = Double(index) / Double(samples) * 2 * .pi
            // A gentle three-lobed modulation, so the loop reads as a rhythm rather than as
            // a plain circle — a circle beside three drawn marks looks like a placeholder.
            let modulation = 1 + 0.10 * cos(3 * angle)
            let point = CGPoint(
                x: centre.x + radiusX * modulation * cos(angle - .pi / 2),
                y: centre.y + radiusY * modulation * sin(angle - .pi / 2)
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
