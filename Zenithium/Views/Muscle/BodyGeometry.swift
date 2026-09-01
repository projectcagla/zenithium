//
//  BodyGeometry.swift
//  Zenithium
//
//  The body map's geometry. Faz 25.
//
//  The first version drew each muscle as a rounded box or an ellipse. It was honest about
//  where a group sat and dishonest about everything else — a column of blocks under a
//  circle, which made the map read as a placeholder for a real one.
//
//  This version builds each muscle from a **spine and a width profile** rather than from a
//  hand-traced outline. A spine is the line the muscle runs along, bent by one control
//  point; the profile says how thick it is at each point along that line. The outline is
//  then generated: sample the spine, step out perpendicular by the half-width on each side,
//  and run a closed Catmull–Rom spline through the resulting ring.
//
//  That choice buys three things a traced outline would not:
//
//  * **It tapers correctly.** A quadriceps is broad at the hip and narrow at the knee
//    because its profile says so, not because someone drew it that way.
//  * **It is tunable.** Moving an insertion is two numbers, not thirty control points.
//  * **It cannot come out jagged.** Every contour is a spline through generated samples, so
//    there is no hand-drawn wobble to notice at AX5.
//
//  ASSUMPTION UI-1 still holds: drawn from a table rather than from image assets, so the map
//  is asset-free, scales cleanly, and lets each region carry its own accessibility element.
//
//  ## Units, and the bug that makes them matter
//
//  Positions are normalised to a 0…1 box, x across and y down. But the box is drawn far
//  taller than wide, so one unit of x is *not* one unit of y on screen. A normal computed
//  naively in that space makes a horizontal muscle about three times too thick — which is
//  what the first draft of this file did, and it is why the pectorals came out looking like
//  shoulder pads.
//
//  So `halfWidth` is expressed in **figure-height units**, and the perpendicular is taken in
//  aspect-corrected space: x is scaled by `aspectRatio` before the tangent, and the
//  resulting offset is divided back out. A half-width of 0.03 is then 3% of the figure's
//  height whichever direction the muscle runs in.
//
//  Proportions follow the classical eight-head figure: chin at 0.13, nipple line at 0.22,
//  navel at 0.30, pubis at 0.47, knee at 0.72, ankle at 0.95. Only the left half of a
//  bilateral group is written down; the right is mirrored about x = 0.5. The figure faces
//  the viewer, so the drawing's left is the body's right — which does not matter for a
//  readiness map, where both sides always carry the same value.
//

import SwiftUI

/// A point in the normalised body box.
struct BodyPoint: Sendable, Equatable, Hashable {

    let x: Double
    let y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    /// The same point on the other side of the figure.
    var mirrored: BodyPoint { BodyPoint(1 - x, y) }

    func resolved(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }
}

/// How thick a muscle is at one point along its spine, in figure-height units.
struct BodyWidthStop: Sendable, Equatable, Hashable {

    /// Position along the spine, 0 at the start, 1 at the end.
    let t: Double

    /// Half the muscle's thickness there, as a fraction of the figure's height.
    let halfWidth: Double

    init(_ t: Double, _ halfWidth: Double) {
        self.t = t
        self.halfWidth = halfWidth
    }
}

/// One muscle belly: the line it runs along, and how thick it is along that line.
struct MuscleSpine: Sendable, Equatable, Hashable {

    /// Proximal attachment.
    let start: BodyPoint

    /// The quadratic control point that bends the spine. A muscle is never a straight line.
    let bend: BodyPoint

    /// Distal attachment.
    let end: BodyPoint

    /// Thickness along the spine, in ascending `t`. At least two stops.
    let profile: [BodyWidthStop]

    init(start: BodyPoint, bend: BodyPoint, end: BodyPoint, profile: [BodyWidthStop]) {
        self.start = start
        self.bend = bend
        self.end = end
        self.profile = profile
    }

    /// The same belly on the other side.
    var mirrored: MuscleSpine {
        MuscleSpine(start: start.mirrored, bend: bend.mirrored, end: end.mirrored, profile: profile)
    }

    /// The point on the spine at `t`, on a quadratic Bézier.
    func point(at t: Double) -> BodyPoint {
        let u = 1 - t
        let x = u * u * start.x + 2 * u * t * bend.x + t * t * end.x
        let y = u * u * start.y + 2 * u * t * bend.y + t * t * end.y
        return BodyPoint(x, y)
    }

    /// The spine's direction at `t`, with x scaled into height units so the perpendicular
    /// taken from it is a true perpendicular on screen.
    func tangent(at t: Double, aspectRatio: Double) -> (dx: Double, dy: Double) {
        let dx = 2 * (1 - t) * (bend.x - start.x) + 2 * t * (end.x - bend.x)
        let dy = 2 * (1 - t) * (bend.y - start.y) + 2 * t * (end.y - bend.y)
        return (dx * aspectRatio, dy)
    }

    /// Half-thickness at `t`, smoothly interpolated between the profile's stops.
    ///
    /// Smoothstep rather than linear: a linear blend leaves a visible crease at every stop,
    /// which is exactly the hand-drawn look this model exists to avoid.
    func halfWidth(at t: Double) -> Double {
        guard let first = profile.first, let last = profile.last else { return 0 }
        if t <= first.t { return first.halfWidth }
        if t >= last.t { return last.halfWidth }

        for index in 1..<profile.count {
            let lower = profile[index - 1]
            let upper = profile[index]
            guard t <= upper.t else { continue }
            let span = upper.t - lower.t
            guard span > 0 else { return upper.halfWidth }
            let local = (t - lower.t) / span
            let eased = local * local * (3 - 2 * local)
            return lower.halfWidth + (upper.halfWidth - lower.halfWidth) * eased
        }
        return last.halfWidth
    }

    /// How many samples the outline is generated from. Enough that the spline through them
    /// is smooth; few enough that a sixteen-region map is cheap to redraw during animation.
    static let sampleCount = 20

    /// The closed outline, as a ring of points in normalised space.
    func outline(aspectRatio: Double = Double(BodyGeometry.aspectRatio)) -> [BodyPoint] {
        var leadingEdge: [BodyPoint] = []
        var trailingEdge: [BodyPoint] = []
        leadingEdge.reserveCapacity(Self.sampleCount + 1)
        trailingEdge.reserveCapacity(Self.sampleCount + 1)

        for step in 0...Self.sampleCount {
            let t = Double(step) / Double(Self.sampleCount)
            let centre = point(at: t)
            let width = halfWidth(at: t)
            let direction = tangent(at: t, aspectRatio: aspectRatio)
            let length = (direction.dx * direction.dx + direction.dy * direction.dy).squareRoot()
            guard length > 0 else { continue }

            // Unit normal in height units, then divided back out on x so the offset lands
            // in normalised coordinates again.
            let normalX = -direction.dy / length
            let normalY = direction.dx / length
            let offsetX = normalX * width / aspectRatio
            let offsetY = normalY * width

            leadingEdge.append(BodyPoint(centre.x + offsetX, centre.y + offsetY))
            trailingEdge.append(BodyPoint(centre.x - offsetX, centre.y - offsetY))
        }

        return leadingEdge + trailingEdge.reversed()
    }
}

/// One drawable region of the body map.
struct BodyRegion: Identifiable, Sendable {

    let muscle: MuscleGroup
    let side: BodySide

    /// The bellies making up the region. Bilateral groups have two.
    let spines: [MuscleSpine]

    /// Each belly's outline, generated once at construction.
    ///
    /// An outline is a ring of points in the normalised box, so it does not depend on the
    /// rectangle the map is eventually drawn into — only on the spine and its width profile,
    /// both of which are constants. Generating it per frame meant re-running twenty tangent
    /// and normal computations per belly on every redraw, for a result that could never
    /// differ. The regions are `static let`, so this cost is paid once for the whole app.
    let outlines: [[BodyPoint]]

    init(muscle: MuscleGroup, side: BodySide, spines: [MuscleSpine]) {
        self.muscle = muscle
        self.side = side
        self.spines = spines
        self.outlines = spines.map { $0.outline() }
    }

    var id: String { "\(side.rawValue)-\(muscle.rawValue)" }

    /// The region's path in a concrete rectangle.
    ///
    /// Callers that draw the same region more than once per layout pass — the canvas fill,
    /// the hit-test overlay and its `contentShape` all want the same shape — should resolve
    /// through `BodyPathCache` rather than calling this repeatedly.
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for outline in outlines {
            path.addPath(BodyGeometry.closedSpline(through: outline, in: rect))
        }
        return path
    }

    /// The direction heat should run in, so a gradient follows the muscle rather than the
    /// screen. Taken from the first belly's own spine.
    func gradientAxis(in rect: CGRect) -> (start: CGPoint, end: CGPoint) {
        guard let spine = spines.first else {
            return (CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.midX, y: rect.maxY))
        }
        return (spine.start.resolved(in: rect), spine.end.resolved(in: rect))
    }

    /// The point a label or tap target centres on.
    func center(in rect: CGRect) -> CGPoint {
        let bounds = path(in: rect).boundingRect
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }
}

enum BodyGeometry {

    /// The aspect ratio the map is laid out in. A standing figure with the arms down is
    /// about a third as wide as it is tall; anything wider leaves the body floating inside
    /// its own box.
    static let aspectRatio: CGFloat = 0.34

    // MARK: - Spline

    /// A closed Catmull–Rom spline through a ring of points, emitted as cubic Béziers.
    ///
    /// The Catmull–Rom tangent at a point is a sixth of the vector between its neighbours;
    /// that is the division below, and it is what makes the curve pass exactly through every
    /// generated sample rather than near it.
    static func closedSpline(through points: [BodyPoint], in rect: CGRect) -> Path {
        guard points.count >= 3 else { return Path() }
        let resolved = points.map { $0.resolved(in: rect) }
        let count = resolved.count

        var path = Path()
        path.move(to: resolved[0])
        for index in 0..<count {
            let previous = resolved[(index - 1 + count) % count]
            let current = resolved[index]
            let next = resolved[(index + 1) % count]
            let following = resolved[(index + 2) % count]

            let control1 = CGPoint(
                x: current.x + (next.x - previous.x) / 6,
                y: current.y + (next.y - previous.y) / 6
            )
            let control2 = CGPoint(
                x: next.x - (following.x - current.x) / 6,
                y: next.y - (following.y - current.y) / 6
            )
            path.addCurve(to: next, control1: control1, control2: control2)
        }
        path.closeSubpath()
        return path
    }

    // MARK: - Silhouette

    /// The body the muscles sit on: head, torso and limbs, drawn behind everything and
    /// never coloured by readiness. Without it the map reads as floating shapes.
    static let silhouette: [MuscleSpine] = {
        let head = MuscleSpine(
            start: BodyPoint(0.500, 0.014),
            bend: BodyPoint(0.500, 0.072),
            end: BodyPoint(0.500, 0.134),
            profile: [BodyWidthStop(0, 0.006), BodyWidthStop(0.1, 0.034), BodyWidthStop(0.38, 0.047), BodyWidthStop(0.7, 0.044), BodyWidthStop(0.88, 0.030), BodyWidthStop(1, 0.009)]
        )
        let neck = MuscleSpine(
            start: BodyPoint(0.500, 0.116),
            bend: BodyPoint(0.500, 0.150),
            end: BodyPoint(0.500, 0.190),
            profile: [BodyWidthStop(0, 0.028), BodyWidthStop(1, 0.035)]
        )
        let torso = MuscleSpine(
            start: BodyPoint(0.500, 0.152),
            bend: BodyPoint(0.500, 0.332),
            end: BodyPoint(0.500, 0.490),
            profile: [BodyWidthStop(0, 0.050), BodyWidthStop(0.13, 0.108), BodyWidthStop(0.26, 0.118), BodyWidthStop(0.42, 0.102), BodyWidthStop(0.62, 0.082), BodyWidthStop(0.86, 0.094), BodyWidthStop(1, 0.094)]
        )
        let upperArm = MuscleSpine(
            start: BodyPoint(0.212, 0.200),
            bend: BodyPoint(0.196, 0.288),
            end: BodyPoint(0.192, 0.376),
            profile: [BodyWidthStop(0, 0.033), BodyWidthStop(0.5, 0.030), BodyWidthStop(1, 0.025)]
        )
        let forearm = MuscleSpine(
            start: BodyPoint(0.190, 0.376),
            bend: BodyPoint(0.182, 0.446),
            end: BodyPoint(0.188, 0.524),
            profile: [BodyWidthStop(0, 0.025), BodyWidthStop(0.6, 0.020), BodyWidthStop(1, 0.016)]
        )
        let hand = MuscleSpine(
            start: BodyPoint(0.188, 0.522),
            bend: BodyPoint(0.186, 0.550),
            end: BodyPoint(0.194, 0.580),
            profile: [BodyWidthStop(0, 0.017), BodyWidthStop(0.5, 0.019), BodyWidthStop(1, 0.009)]
        )
        let thigh = MuscleSpine(
            start: BodyPoint(0.356, 0.462),
            bend: BodyPoint(0.352, 0.592),
            end: BodyPoint(0.376, 0.718),
            profile: [BodyWidthStop(0, 0.057), BodyWidthStop(0.42, 0.051), BodyWidthStop(1, 0.029)]
        )
        let shank = MuscleSpine(
            start: BodyPoint(0.376, 0.716),
            bend: BodyPoint(0.368, 0.812),
            end: BodyPoint(0.382, 0.952),
            profile: [BodyWidthStop(0, 0.030), BodyWidthStop(0.24, 0.034), BodyWidthStop(1, 0.013)]
        )
        let foot = MuscleSpine(
            start: BodyPoint(0.382, 0.948),
            bend: BodyPoint(0.376, 0.978),
            end: BodyPoint(0.346, 0.992),
            profile: [BodyWidthStop(0, 0.012), BodyWidthStop(0.5, 0.014), BodyWidthStop(1, 0.008)]
        )

        let limbs = [upperArm, forearm, hand, thigh, shank, foot]
        return [head, neck, torso] + limbs + limbs.map(\.mirrored)
    }()

    /// The silhouette's outlines, generated once for the same reason the regions' are.
    static let silhouetteOutlines: [[BodyPoint]] = silhouette.map { $0.outline() }

    // MARK: - Regions

    /// The regions on a given side of the figure.
    static func regions(for side: BodySide) -> [BodyRegion] {
        switch side {
        case .anterior: return anterior
        case .posterior: return posterior
        }
    }

    /// A bilateral group, written once and mirrored.
    private static func paired(_ muscle: MuscleGroup, _ side: BodySide, _ spine: MuscleSpine) -> BodyRegion {
        BodyRegion(muscle: muscle, side: side, spines: [spine, spine.mirrored])
    }

    /// A group that sits on the midline and is drawn once.
    private static func central(_ muscle: MuscleGroup, _ side: BodySide, _ spine: MuscleSpine) -> BodyRegion {
        BodyRegion(muscle: muscle, side: side, spines: [spine])
    }

    // MARK: - Anterior
    //
    // Declaration order is draw order, and it is load-bearing: the adductors are laid over
    // the quadriceps' medial edge, because those two overlap on a real thigh and the inner
    // one is the smaller of the pair.

    private static let anterior: [BodyRegion] = [
        central(.neck, .anterior, MuscleSpine(
                start: BodyPoint(0.500, 0.128),
                bend: BodyPoint(0.500, 0.154),
                end: BodyPoint(0.500, 0.186),
                profile: [BodyWidthStop(0, 0.022), BodyWidthStop(1, 0.029)]
            )),
        paired(.shoulders, .anterior, MuscleSpine(
                start: BodyPoint(0.336, 0.182),
                bend: BodyPoint(0.226, 0.202),
                end: BodyPoint(0.250, 0.266),
                profile: [BodyWidthStop(0, 0.017), BodyWidthStop(0.42, 0.028), BodyWidthStop(1, 0.020)]
            )),
        paired(.chest, .anterior, MuscleSpine(
                start: BodyPoint(0.500, 0.198),
                bend: BodyPoint(0.398, 0.232),
                end: BodyPoint(0.298, 0.226),
                profile: [BodyWidthStop(0, 0.024), BodyWidthStop(0.38, 0.030), BodyWidthStop(1, 0.014)]
            )),
        paired(.biceps, .anterior, MuscleSpine(
                start: BodyPoint(0.238, 0.266),
                bend: BodyPoint(0.208, 0.320),
                end: BodyPoint(0.196, 0.374),
                profile: [BodyWidthStop(0, 0.020), BodyWidthStop(0.42, 0.025), BodyWidthStop(1, 0.017)]
            )),
        paired(.forearms, .anterior, MuscleSpine(
                start: BodyPoint(0.192, 0.380),
                bend: BodyPoint(0.184, 0.440),
                end: BodyPoint(0.190, 0.506),
                profile: [BodyWidthStop(0, 0.022), BodyWidthStop(0.26, 0.023), BodyWidthStop(1, 0.011)]
            )),
        central(.core, .anterior, MuscleSpine(
                start: BodyPoint(0.500, 0.256),
                bend: BodyPoint(0.500, 0.350),
                end: BodyPoint(0.500, 0.452),
                profile: [BodyWidthStop(0, 0.052), BodyWidthStop(0.4, 0.050), BodyWidthStop(0.78, 0.042), BodyWidthStop(1, 0.020)]
            )),
        paired(.quads, .anterior, MuscleSpine(
                start: BodyPoint(0.330, 0.486),
                bend: BodyPoint(0.334, 0.594),
                end: BodyPoint(0.362, 0.698),
                profile: [BodyWidthStop(0, 0.038), BodyWidthStop(0.3, 0.041), BodyWidthStop(0.74, 0.032), BodyWidthStop(1, 0.018)]
            )),
        paired(.adductors, .anterior, MuscleSpine(
                start: BodyPoint(0.448, 0.482),
                bend: BodyPoint(0.438, 0.548),
                end: BodyPoint(0.434, 0.628),
                profile: [BodyWidthStop(0, 0.013), BodyWidthStop(0.4, 0.015), BodyWidthStop(1, 0.006)]
            )),
        paired(.calves, .anterior, MuscleSpine(
                start: BodyPoint(0.376, 0.734),
                bend: BodyPoint(0.376, 0.822),
                end: BodyPoint(0.380, 0.928),
                profile: [BodyWidthStop(0, 0.023), BodyWidthStop(0.28, 0.024), BodyWidthStop(0.7, 0.016), BodyWidthStop(1, 0.006)]
            ))
    ]

    // MARK: - Posterior

    private static let posterior: [BodyRegion] = [
        central(.traps, .posterior, MuscleSpine(
                start: BodyPoint(0.500, 0.150),
                bend: BodyPoint(0.500, 0.196),
                end: BodyPoint(0.500, 0.252),
                profile: [BodyWidthStop(0, 0.018), BodyWidthStop(0.36, 0.062), BodyWidthStop(0.72, 0.050), BodyWidthStop(1, 0.030)]
            )),
        central(.upperBack, .posterior, MuscleSpine(
                start: BodyPoint(0.500, 0.274),
                bend: BodyPoint(0.500, 0.312),
                end: BodyPoint(0.500, 0.352),
                profile: [BodyWidthStop(0, 0.056), BodyWidthStop(0.5, 0.053), BodyWidthStop(1, 0.044)]
            )),
        paired(.lats, .posterior, MuscleSpine(
                start: BodyPoint(0.308, 0.258),
                bend: BodyPoint(0.326, 0.330),
                end: BodyPoint(0.444, 0.416),
                profile: [BodyWidthStop(0, 0.023), BodyWidthStop(0.38, 0.034), BodyWidthStop(1, 0.015)]
            )),
        paired(.triceps, .posterior, MuscleSpine(
                start: BodyPoint(0.240, 0.260),
                bend: BodyPoint(0.208, 0.316),
                end: BodyPoint(0.196, 0.374),
                profile: [BodyWidthStop(0, 0.021), BodyWidthStop(0.45, 0.025), BodyWidthStop(1, 0.017)]
            )),
        paired(.forearms, .posterior, MuscleSpine(
                start: BodyPoint(0.192, 0.380),
                bend: BodyPoint(0.184, 0.440),
                end: BodyPoint(0.190, 0.506),
                profile: [BodyWidthStop(0, 0.022), BodyWidthStop(0.26, 0.023), BodyWidthStop(1, 0.011)]
            )),
        central(.lowerBack, .posterior, MuscleSpine(
                start: BodyPoint(0.500, 0.368),
                bend: BodyPoint(0.500, 0.412),
                end: BodyPoint(0.500, 0.460),
                profile: [BodyWidthStop(0, 0.046), BodyWidthStop(0.5, 0.043), BodyWidthStop(1, 0.032)]
            )),
        paired(.glutes, .posterior, MuscleSpine(
                start: BodyPoint(0.386, 0.464),
                bend: BodyPoint(0.360, 0.500),
                end: BodyPoint(0.398, 0.562),
                profile: [BodyWidthStop(0, 0.028), BodyWidthStop(0.45, 0.040), BodyWidthStop(1, 0.024)]
            )),
        paired(.hamstrings, .posterior, MuscleSpine(
                start: BodyPoint(0.366, 0.566),
                bend: BodyPoint(0.362, 0.634),
                end: BodyPoint(0.378, 0.700),
                profile: [BodyWidthStop(0, 0.036), BodyWidthStop(0.4, 0.039), BodyWidthStop(1, 0.026)]
            )),
        paired(.calves, .posterior, MuscleSpine(
                start: BodyPoint(0.374, 0.722),
                bend: BodyPoint(0.364, 0.798),
                end: BodyPoint(0.380, 0.930),
                profile: [BodyWidthStop(0, 0.031), BodyWidthStop(0.26, 0.035), BodyWidthStop(0.66, 0.020), BodyWidthStop(1, 0.006)]
            ))
    ]

    /// Every group, and which view shows it. Used by the list fallback so all sixteen are
    /// reachable even though each drawing only shows nine of them.
    static let allRegions: [BodyRegion] = anterior + posterior
}
