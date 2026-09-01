//
//  WatchLiveSessionView.swift
//  ZenithiumWatch
//
//  The session screen. Yol haritası v4, C1.
//
//  Read mid-effort, at arm's length, often in the rain. So: one number large enough to read
//  without stopping, one ring saying where the day sits against its ceiling, and everything
//  else small. No advice — §12 and §1 apply here more than anywhere, because a screen read
//  while someone is running is the worst possible place to tell them what to do.
//

import SwiftUI

struct WatchLiveSessionView: View {

    @State private var viewModel = LiveWorkoutViewModel()

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .finished:
                startScreen
            case .requestingAuthorization:
                waiting("İzin isteniyor…")
            case .running, .paused:
                runningScreen
            case .ending:
                waiting("Kaydediliyor…")
            case .failed(let message):
                failure(message)
            }
        }
        .containerBackground(ZenithiumColor.background.gradient, for: .navigation)
        .navigationTitle("Seans")
    }

    // MARK: - Idle

    private var startScreen: some View {
        VStack(spacing: ZenithiumSpacing.m) {
            Image(systemName: "figure.run")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(ZenithiumColor.accent)
                .accessibilityHidden(true)

            if let ceiling = viewModel.ceiling {
                Text("Bugünün tavanı \(ZenithiumFormat.strain(ceiling))")
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Telefonda hesaplanmış tavan yok")
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textTertiary)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await viewModel.start() }
            } label: {
                Text("Başlat").frame(maxWidth: .infinity)
            }
            .tint(ZenithiumColor.accent)
        }
        .padding(.horizontal, ZenithiumSpacing.s)
    }

    // MARK: - Running

    private var runningScreen: some View {
        ScrollView {
            VStack(spacing: ZenithiumSpacing.m) {
                strainReadout
                ceilingRing
                secondaryRows
                controls
            }
            .padding(.horizontal, ZenithiumSpacing.xxs)
        }
    }

    private var strainReadout: some View {
        VStack(spacing: ZenithiumSpacing.none) {
            Text(ZenithiumFormat.strain(viewModel.output?.dayStrain ?? 0))
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ZenithiumColor.textPrimary)
                .contentTransition(.numericText())
                .animation(.snappy, value: viewModel.output?.dayStrain)
            Text("gün zorlanması")
                .font(ZenithiumFont.caption2)
                .foregroundStyle(ZenithiumColor.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gün zorlanması")
        .accessibilityValue(ZenithiumFormat.strain(viewModel.output?.dayStrain ?? 0))
    }

    @ViewBuilder
    private var ceilingRing: some View {
        if let output = viewModel.output, let progress = output.ceilingProgress {
            VStack(spacing: ZenithiumSpacing.xs) {
                ZStack {
                    Circle()
                        .stroke(ZenithiumColor.hairline, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: min(progress, 1))
                        .stroke(ZenithiumColor.color(for: output.band), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("%\(Int((progress * 100).rounded()))")
                        .font(ZenithiumFont.dataValue.monospacedDigit())
                        .foregroundStyle(ZenithiumColor.textPrimary)
                }
                .frame(width: 74, height: 74)
                .animation(.snappy, value: progress)

                Text(output.band.summary)
                    .font(ZenithiumFont.caption2)
                    .foregroundStyle(ZenithiumColor.color(for: output.band))
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tavanın yüzdesi")
            .accessibilityValue("yüzde \(Int((progress * 100).rounded())), \(output.band.summary)")
            .sensoryFeedback(.impact(weight: .medium), trigger: output.band)
        }
    }

    private var secondaryRows: some View {
        VStack(spacing: ZenithiumSpacing.xs) {
            row("Süre", ZenithiumFormat.longClock(seconds: viewModel.elapsedSeconds))
            if let heartRate = viewModel.heartRate {
                row("Nabız", "\(Int(heartRate.rounded()))")
            }
            if let seconds = viewModel.output?.secondsToCeiling {
                row("Tavana", ZenithiumFormat.longClock(seconds: seconds))
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(ZenithiumFont.caption2)
                .foregroundStyle(ZenithiumColor.textSecondary)
            Spacer(minLength: 4)
            Text(value)
                .font(ZenithiumFont.caption.monospacedDigit())
                .foregroundStyle(ZenithiumColor.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private var controls: some View {
        HStack(spacing: ZenithiumSpacing.s) {
            if viewModel.phase == .paused {
                Button("Sürdür") { viewModel.resume() }
                    .tint(ZenithiumColor.accent)
            } else {
                Button("Duraklat") { viewModel.pause() }
                    .tint(ZenithiumColor.textSecondary)
            }
            Button("Bitir") {
                Task { await viewModel.end() }
            }
            .tint(ZenithiumColor.red)
        }
        .font(ZenithiumFont.caption)
    }

    // MARK: - Other states

    private func waiting(_ text: String) -> some View {
        VStack(spacing: ZenithiumSpacing.s) {
            ProgressView().tint(ZenithiumColor.accent)
            Text(text)
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: ZenithiumSpacing.s) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(ZenithiumColor.yellow)
                .accessibilityHidden(true)
            Text(message)
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textSecondary)
                .multilineTextAlignment(.center)
            Button("Tekrar dene") {
                Task { await viewModel.start() }
            }
            .tint(ZenithiumColor.accent)
            .font(ZenithiumFont.caption)
        }
        .padding(.horizontal, ZenithiumSpacing.s)
    }

}
