//
//  SkeletonView.swift
//  Zenithium
//
//  The first-load placeholder. Yol haritası v4, B5.
//
//  Every screen used to open on a centred spinner and a line of text. That is honest about
//  waiting and silent about what is coming, so the moment the data lands the layout jumps —
//  a spinner occupies nothing like the space a scored arc and three cards occupy.
//
//  A skeleton says the shape of the answer before the answer exists. The screen is already
//  laid out when the numbers arrive; only the contents change. It also reads as faster than
//  a spinner at identical timings, because there is something to look at that resembles the
//  destination.
//
//  ## The shimmer
//
//  A slow highlight travelling across the blocks, masked to the blocks themselves, and
//  nothing else. It is the only ambient motion in the app, and it earns its place by being
//  the signal that the screen is still working — a completely static skeleton reads as a
//  screen that has failed. Under Reduce Motion it holds still.
//

import SwiftUI

/// What the loading screen is standing in for.
enum SkeletonLayout: Sendable {

    /// A scored screen: a large arc, a row of tiles, a card.
    case scored

    /// A list of cards — journal, documents, sessions.
    case cards

    /// A card with a chart in it, then a row of tiles.
    case chart
}

/// One grey block standing in for content.
private struct SkeletonBlock: View {

    var height: CGFloat

    /// A fixed width, or `nil` to fill the available space.
    var width: CGFloat?

    var cornerRadius: CGFloat = ZenithiumRadius.medium

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(ZenithiumColor.surfaceElevated)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : width, alignment: .leading)
    }
}

/// The placeholder shown while a screen's first read is in flight.
struct SkeletonView: View {

    var layout: SkeletonLayout = .cards

    /// Spoken instead of the blocks, which carry no meaning of their own.
    let label: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerPhase: CGFloat = -1

    var body: some View {
        blocks
            .overlay { shimmer.mask { blocks } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.updatesFrequently)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    shimmerPhase = 1.4
                }
            }
    }

    // MARK: - Layouts

    @ViewBuilder
    private var blocks: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.l) {
            switch layout {
            case .scored:
                scored
            case .cards:
                cards
            case .chart:
                chart
            }
        }
        .padding(.horizontal, ZenithiumSpacing.l)
        .padding(.top, ZenithiumSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scored: some View {
        VStack(spacing: ZenithiumSpacing.xl) {
            Circle()
                .fill(ZenithiumColor.surfaceElevated)
                .frame(width: 232, height: 232)
                .frame(maxWidth: .infinity)

            HStack(spacing: ZenithiumSpacing.m) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonBlock(height: 72, cornerRadius: ZenithiumRadius.large)
                }
            }
            SkeletonBlock(height: 120, cornerRadius: ZenithiumRadius.xLarge)
        }
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
            ForEach(0..<4, id: \.self) { index in
                VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                    SkeletonBlock(
                        height: 13,
                        width: index.isMultiple(of: 2) ? 132 : 176,
                        cornerRadius: ZenithiumRadius.small
                    )
                    SkeletonBlock(height: 62, cornerRadius: ZenithiumRadius.large)
                }
            }
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.l) {
            SkeletonBlock(height: 13, width: 120, cornerRadius: ZenithiumRadius.small)
            SkeletonBlock(height: 180, cornerRadius: ZenithiumRadius.xLarge)
            HStack(spacing: ZenithiumSpacing.m) {
                ForEach(0..<2, id: \.self) { _ in
                    SkeletonBlock(height: 72, cornerRadius: ZenithiumRadius.large)
                }
            }
        }
    }

    // MARK: - Shimmer

    @ViewBuilder
    private var shimmer: some View {
        if reduceMotion {
            Color.clear
        } else {
            GeometryReader { proxy in
                LinearGradient(
                    colors: [
                        .clear,
                        ZenithiumColor.textPrimary.opacity(0.07),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: proxy.size.width * 0.55)
                .offset(x: shimmerPhase * proxy.size.width)
            }
            .allowsHitTesting(false)
        }
    }
}
