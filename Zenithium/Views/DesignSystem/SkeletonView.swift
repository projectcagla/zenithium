import SwiftUI

/// Loading preserves the screen's composition without inventing a measurement.
enum SkeletonLayout: Sendable { case scored, cards, chart }

struct SkeletonView: View {
    var layout: SkeletonLayout = .cards
    let label: String
    var showsLabel: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.sectionSpacing) {
            switch layout {
            case .scored:
                ZStack {
                    Circle().trim(from: 0, to: 0.75)
                        .stroke(ghost, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(135))
                    block(height: 40, width: 74)
                }
                .frame(width: 180, height: 180)
                .frame(maxWidth: .infinity)
                ribbon
                block(height: 112)
            case .chart:
                block(height: 11, width: 104)
                block(height: 60, width: 138)
                Canvas { context, size in
                    for row in 0..<4 {
                        for column in 0..<17 {
                            let x = CGFloat(column) * size.width / 16
                            let y = CGFloat(row) * (size.height - 8) / 3 + 4
                            context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(ghost))
                        }
                    }
                }
                .frame(height: 180)
                ribbon
            case .cards:
                ForEach(0..<4, id: \.self) { _ in
                    HStack {
                        VStack(alignment: .leading, spacing: 12) {
                            block(height: 14, width: 128)
                            block(height: 10, width: 92)
                        }
                        Spacer()
                        block(height: 26, width: 60)
                    }
                }
            }
            if showsLabel {
                HStack(spacing: 8) {
                    Image(systemName: "circle.dotted")
                    Text(label)
                }
                .zenithiumCaption()
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, ZenithiumSpacing.l)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var ghost: Color { ZenithiumColor.textPrimary.opacity(0.06) }

    private func block(height: CGFloat, width: CGFloat? = nil) -> some View {
        RoundedRectangle(cornerRadius: height > 80 ? ZenithiumRadius.card : 4, style: .continuous)
            .fill(ghost).frame(width: width, height: height)
    }

    private var ribbon: some View {
        HStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    block(height: 9)
                    block(height: 24)
                    block(height: 2)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
