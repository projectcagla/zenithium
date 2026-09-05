//
//  SleepStageBarView.swift
//  Zenithium
//
//  The stage breakdown. Spec §3 (asleep = core + deep + REM), §10 (accessibility gate).
//
//  Shares arrive pre-measured on `SleepViewModel.StageSlice` (§9). Stages are named as well
//  as coloured, so the bar is readable in greyscale.
//

import SwiftUI

struct SleepStageBarView: View {

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let stages: [SleepViewModel.StageSlice]

    private var occupied: [SleepViewModel.StageSlice] {
        stages.filter { $0.seconds > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
            stackedBar
            legend
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Uyku evreleri")
    }

    private var stackedBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(occupied) { slice in
                    Rectangle()
                        .fill(ZenithiumColor.color(for: slice.stage))
                        .frame(width: max(proxy.size.width * slice.share, 0))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private var legend: some View {
        let columns = Array(repeating: GridItem(.flexible(), alignment: .leading), count: dynamicTypeSize.isAccessibilitySize ? 2 : 4)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 16) { legendRows }
    }

    @ViewBuilder
    private var legendRows: some View {
        ForEach(stages) { slice in
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: ZenithiumRadius.small, style: .continuous)
                    .fill(ZenithiumColor.color(for: slice.stage))
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ZenithiumSpacing.none) {
                    Text(slice.stage.displayName)
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                    Text(ZenithiumFormat.percent(slice.share))
                        .font(ZenithiumFont.dataValue)
                        .foregroundStyle(ZenithiumColor.textPrimary)
                    Text(ZenithiumFormat.duration(seconds: slice.seconds))
                        .font(ZenithiumFont.caption.monospacedDigit())
                        .foregroundStyle(ZenithiumColor.textPrimary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(slice.stage.displayName)
            .accessibilityValue(
                "\(ZenithiumFormat.spokenDuration(seconds: slice.seconds)), \(ZenithiumFormat.percent(slice.share)) gecenin"
            )
        }
    }
}
