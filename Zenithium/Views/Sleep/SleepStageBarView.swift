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
            HStack(spacing: ZenithiumSpacing.xxs) {
                ForEach(occupied) { slice in
                    RoundedRectangle(cornerRadius: ZenithiumRadius.small, style: .continuous)
                        .fill(ZenithiumColor.color(for: slice.stage))
                        .frame(width: max(proxy.size.width * slice.share - 2, 2))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: ZenithiumSpacing.l) { legendRows }
            VStack(alignment: .leading, spacing: ZenithiumSpacing.s) { legendRows }
        }
    }

    @ViewBuilder
    private var legendRows: some View {
        ForEach(occupied) { slice in
            HStack(spacing: ZenithiumSpacing.s) {
                RoundedRectangle(cornerRadius: ZenithiumRadius.small, style: .continuous)
                    .fill(ZenithiumColor.color(for: slice.stage))
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ZenithiumSpacing.none) {
                    Text(slice.stage.displayName)
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(ZenithiumColor.textSecondary)
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
