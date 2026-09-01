//
//  StateViews.swift
//  Zenithium
//
//  The non-loaded states. Spec §5.6 requires HealthKit denial to be a full-screen recoverable
//  state with a deep link to Settings, and §15 rule 9 requires every missing-data path to have
//  a defined state rather than a crash or a zero.
//

import SwiftUI

/// System URLs the app opens.
enum SystemURL {

    /// The value of `UIApplication.openSettingsURLString`, written as a literal.
    ///
    /// UIKit is not on the framework list in §2.2, and importing it for one string constant
    /// would widen the app's surface for no benefit. The value is a documented, stable
    /// system URL.
    static let appSettings = URL(string: "app-settings:")
}

/// The shared shape of every empty state, so they read as one family.
struct StatusView<Actions: View>: View {

    let symbolName: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: ZenithiumSpacing.l) {
            Image(systemName: symbolName)
                .font(.system(size: 44, weight: .regular, design: .rounded))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            Text(title)
                .font(ZenithiumFont.sectionTitle)
                .foregroundStyle(ZenithiumColor.textPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(ZenithiumFont.callout)
                .foregroundStyle(ZenithiumColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            actions()
        }
        .padding(ZenithiumSpacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// §4.2.4 — fewer than five valid baseline days. Shows `n/14` progress.
struct CalibratingView: View {

    let daysCollected: Int
    let daysRequired: Int
    let progress: Double

    var body: some View {
        StatusView(
            symbolName: "circle.dotted",
            tint: ZenithiumColor.accent,
            title: SafetyCopy.calibratingTitle,
            message: SafetyCopy.calibratingBody(
                daysCollected: daysCollected,
                daysRequired: daysRequired
            )
        ) {
            VStack(spacing: ZenithiumSpacing.s) {
                ProgressView(value: MathSupport.clamp(progress, 0, 1))
                    .tint(ZenithiumColor.accent)
                    .frame(maxWidth: 240)
                Text("\(daysRequired) gecenin \(daysCollected) tanesi")
                    .font(ZenithiumFont.caption.monospacedDigit())
                    .foregroundStyle(ZenithiumColor.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Kalibrasyon ilerlemesi")
            .accessibilityValue("\(daysRequired) gecenin \(daysCollected) tanesi toplandı")
        }
    }
}

/// §5.6 — Health access missing. Recoverable, with a deep link to Settings.
struct AuthorizationGateView: View {

    let state: HealthAuthorizationState
    let requestAccess: () async -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        StatusView(
            symbolName: "heart.text.square",
            tint: ZenithiumColor.accent,
            title: SafetyCopy.authorizationTitle,
            message: message
        ) {
            VStack(spacing: ZenithiumSpacing.m) {
                if state.shouldPrompt {
                    Button {
                        Task { await requestAccess() }
                    } label: {
                        Text("Devam")
                            .font(ZenithiumFont.label)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ZenithiumColor.accent)
                    .accessibilityHint("Sağlık izin ekranını açar")
                } else if state == .denied {
                    Button {
                        // §5.6 — the deep link, so the recoverable state is actually
                        // recoverable rather than a description of a dead end.
                        if let url = SystemURL.appSettings {
                            openURL(url)
                        }
                    } label: {
                        Text(SafetyCopy.openSettingsAction)
                            .font(ZenithiumFont.label)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ZenithiumColor.accent)
                    .accessibilityHint("Zenithium ayarlarını açar; Sağlık erişimi oradan açılabilir")
                }

                Text(SafetyCopy.disclaimerFooter)
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textTertiary)
            }
            .frame(maxWidth: 320)
        }
    }

    private var message: String {
        switch state {
        case .denied: return SafetyCopy.authorizationDeniedBody
        case .unavailable: return ZenithiumError.healthDataUnavailable.recoverySuggestion ?? ""
        case .notDetermined, .authorized: return SafetyCopy.authorizationBody
        }
    }
}

/// Nothing to show, and nothing wrong.
struct NoDataView: View {

    let reason: NoDataReason
    var retry: (() async -> Void)?

    var body: some View {
        StatusView(
            symbolName: symbolName,
            tint: ZenithiumColor.textSecondary,
            title: reason.title,
            message: reason.message
        ) {
            if let retry {
                Button {
                    Task { await retry() }
                } label: {
                    Text("Yenile")
                        .font(ZenithiumFont.label)
                }
                .buttonStyle(.bordered)
                .tint(ZenithiumColor.accent)
            }
        }
    }

    private var symbolName: String {
        switch reason {
        case .noOvernightData: return "moon.zzz"
        case .noHeartRateYet: return "waveform.path.ecg"
        case .recoveryUnavailable: return "exclamationmark.circle"
        case .sleepImplausible: return "questionmark.circle"
        case .notEnoughHistory: return "chart.line.uptrend.xyaxis"
        case .nothingLogged: return "tray"
        }
    }
}

/// A typed failure, with the affordance the error itself says it deserves.
struct ErrorStateView: View {

    let error: ZenithiumError
    var retry: (() async -> Void)?

    @Environment(\.openURL) private var openURL

    var body: some View {
        StatusView(
            symbolName: "exclamationmark.triangle",
            tint: ZenithiumColor.yellow,
            title: error.errorDescription ?? "Bir şeyler ters gitti",
            message: error.recoverySuggestion ?? ""
        ) {
            VStack(spacing: ZenithiumSpacing.m) {
                if error.requiresSystemSettings {
                    Button {
                        if let url = SystemURL.appSettings {
                            openURL(url)
                        }
                    } label: {
                        Text(SafetyCopy.openSettingsAction)
                            .font(ZenithiumFont.label)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ZenithiumColor.accent)
                }
                if error.isRetryable, let retry {
                    Button {
                        Task { await retry() }
                    } label: {
                        Text("Tekrar dene")
                            .font(ZenithiumFont.label)
                    }
                    .buttonStyle(.bordered)
                    .tint(ZenithiumColor.accent)
                }
            }
        }
    }
}

/// The first-load placeholder.
///
/// A skeleton of the screen that is coming rather than a spinner, so the layout is already
/// in place when the numbers arrive instead of appearing under them. Yol haritası v4, B5.
struct LoadingStateView: View {

    let label: String

    /// The shape of the screen being waited on. Cards by default, because most screens are
    /// a column of them.
    var layout: SkeletonLayout = .cards

    var body: some View {
        SkeletonView(layout: layout, label: label)
    }
}

/// Renders whichever non-loaded state applies, so no screen re-implements the switch.
struct ViewStateContainer<Value: Sendable, Loaded: View>: View {

    let state: ViewState<Value>
    let loadingLabel: String

    /// The shape the loading skeleton takes. Screens that open on an arc or a chart say so;
    /// everything else gets the card column. Yol haritası v4, B5.
    var loadingLayout: SkeletonLayout = .cards

    var retry: (() async -> Void)?
    var requestAccess: (() async -> Void)?
    @ViewBuilder let loaded: (Value) -> Loaded

    var body: some View {
        switch state {
        case .loading:
            LoadingStateView(label: loadingLabel, layout: loadingLayout)

        case .calibrating(let progress, let collected, let required):
            CalibratingView(
                daysCollected: collected,
                daysRequired: required,
                progress: progress
            )

        case .needsAuthorization(let authorization):
            AuthorizationGateView(state: authorization) {
                await requestAccess?()
            }

        case .noData(let reason):
            NoDataView(reason: reason, retry: retry)

        case .loaded(let value):
            loaded(value)

        case .failed(let error):
            ErrorStateView(error: error, retry: retry)
        }
    }
}
