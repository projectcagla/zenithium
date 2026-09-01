//
//  BodyPathCache.swift
//  Zenithium
//
//  Resolved body-map paths, memoised by the rectangle they were built for. Yol haritası v4, A1.
//
//  ## The problem this solves
//
//  The map draws each region three times per layout pass: once filled inside the `Canvas`,
//  once as an invisible hit-test shape, and once again as that shape's `contentShape`. With
//  fourteen regions on a side and two bellies in most of them, that is a few dozen closed
//  Catmull–Rom splines rebuilt on every pass — for a figure whose geometry is constant and
//  whose size changes only when the device rotates.
//
//  `BodyRegion` already generates its outlines once, at construction. What is left is the
//  step that depends on the rectangle: turning a ring of normalised points into a `Path`.
//  This type does that once per size and hands the same paths to every caller.
//
//  ## Why a class, and why it is safe to mutate during `body`
//
//  It is held in `@State`, so SwiftUI keeps one instance alive across redraws. Reading
//  through it during `body` mutates only the memo — no observable state, so no view is
//  invalidated and no update loop is possible. It is `@MainActor`, which is where every
//  caller already is, so there is no concurrency to reason about.
//

import SwiftUI

/// The body map's paths for one rectangle.
struct ResolvedBodyPaths {

    /// The silhouette, in draw order.
    let silhouette: [Path]

    /// Each region's path, keyed by `BodyRegion.id`.
    let regions: [String: Path]

    /// The path for a region, or an empty path if it was not resolved.
    func path(for region: BodyRegion) -> Path {
        regions[region.id] ?? Path()
    }
}

/// Memoises `ResolvedBodyPaths` for the last rectangle it was asked about.
@MainActor
final class BodyPathCache {

    private var resolvedSize: CGSize = .zero
    private var resolvedKey: String = ""
    private var resolved: ResolvedBodyPaths?

    /// How many splines this cache has built since it was created.
    ///
    /// Exists so the performance suite can assert on work done rather than on wall-clock
    /// time. A wall-clock assertion flickers under CI load; this one does not, and it fails
    /// for exactly the reason the optimisation exists.
    private(set) var splineBuildCount = 0

    /// The paths for `regions` in `rect`, rebuilding only if the size or the region set
    /// changed since the last call.
    func paths(for regions: [BodyRegion], in rect: CGRect) -> ResolvedBodyPaths {
        let key = regions.first?.side.rawValue ?? ""
        if let resolved, resolvedSize == rect.size, resolvedKey == key {
            return resolved
        }

        let value = ZenithiumSignpost.interval(ZenithiumSignpost.ui, "buildBodyPaths") {
            var built: [String: Path] = [:]
            built.reserveCapacity(regions.count)
            for region in regions {
                var path = Path()
                for outline in region.outlines {
                    path.addPath(BodyGeometry.closedSpline(through: outline, in: rect))
                    splineBuildCount += 1
                }
                built[region.id] = path
            }

            let silhouette = BodyGeometry.silhouetteOutlines.map { outline -> Path in
                splineBuildCount += 1
                return BodyGeometry.closedSpline(through: outline, in: rect)
            }

            return ResolvedBodyPaths(silhouette: silhouette, regions: built)
        }
        resolvedSize = rect.size
        resolvedKey = key
        resolved = value
        return value
    }
}
