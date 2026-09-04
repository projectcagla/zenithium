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
    static let privacyPolicy = URL(string: "https://projectcagla.github.io/zenithium/privacy")
    static let support = URL(string: "https://projectcagla.github.io/zenithium/support")
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

/// §4.2.4 — fewer than five valid baseline days. Shows `n/14` progress with dots and metric separation.
struct CalibratingView: View {

    let daysCollected: Int
    let daysRequired: Int
    let progress: Double

    var body: some View {
        StatusView(
            symbolName: "circle.dotted",
            tint: ZenithiumColor.accent,
            title: SafetyCopy.calibratingTitle,
            message: "\(daysCollected)/\(daysRequired) gün toplandı · \(max(0, daysRequired - daysCollected)) gün kaldı"
        ) {
            VStack(spacing: ZenithiumSpacing.l) {
                // İlerleme çubuğu yerine kalibre olan günlerin noktaları (7 veya 14 nokta)
                HStack(spacing: 8) {
                    ForEach(0..<max(daysRequired, 1), id: \.self) { index in
                        Circle()
                            .fill(index < daysCollected ? ZenithiumColor.accent : ZenithiumColor.hairline)
                            .frame(width: 10, height: 10)
                    }
                }
                .padding(.vertical, ZenithiumSpacing.xs)

                // Kalibrasyon sürecinde hangi metriklerin şimdiden güvenilir olduğu, hangilerinin taban çizgisi beklediği
                VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                    HStack(alignment: .top, spacing: ZenithiumSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(ZenithiumColor.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Şimdiden güvenilir:")
                                .font(ZenithiumFont.caption)
                                .foregroundStyle(ZenithiumColor.textSecondary)
                            Text("Uyku süresi, anlık nabız, solunum hızı")
                                .font(ZenithiumFont.caption)
                                .foregroundStyle(ZenithiumColor.textPrimary)
                        }
                    }

                    Divider().overlay(ZenithiumColor.hairlineSoft)

                    HStack(alignment: .top, spacing: ZenithiumSpacing.xs) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 13))
                            .foregroundStyle(ZenithiumColor.yellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Taban çizgisi bekleyen:")
                                .font(ZenithiumFont.caption)
                                .foregroundStyle(ZenithiumColor.textSecondary)
                            Text("HRV sapması, toparlanma skoru, yük dengesi")
                                .font(ZenithiumFont.caption)
                                .foregroundStyle(ZenithiumColor.textPrimary)
                        }
                    }
                }
                .padding(ZenithiumSpacing.m)
                .background(
                    RoundedRectangle(cornerRadius: ZenithiumRadius.card, style: .continuous)
                        .fill(ZenithiumColor.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: ZenithiumRadius.card, style: .continuous)
                                .strokeBorder(ZenithiumColor.hairline, lineWidth: 1)
                        )
                )
            }
            .frame(maxWidth: 320)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Kalibrasyon: \(daysCollected) / \(daysRequired) gün")
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
    var actionCallout: String? = nil
    var layout: SkeletonLayout = .cards
    var retry: (() async -> Void)?

    var body: some View {
        VStack(spacing: ZenithiumSpacing.l) {
            StatusView(
                symbolName: symbolName,
                tint: ZenithiumColor.textSecondary,
                title: reason.title,
                message: reason.message
            ) {
                VStack(spacing: ZenithiumSpacing.m) {
                    // "Ne yapmalısın?" tek cümlelik eylem çağrısı
                    HStack(alignment: .top, spacing: ZenithiumSpacing.s) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(ZenithiumColor.accent)
                            .padding(.top, 2)
                        Text(effectiveActionCallout)
                            .font(ZenithiumFont.body)
                            .foregroundStyle(ZenithiumColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(ZenithiumSpacing.m)
                    .background(
                        RoundedRectangle(cornerRadius: ZenithiumRadius.card, style: .continuous)
                            .fill(ZenithiumColor.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: ZenithiumRadius.card, style: .continuous)
                                    .strokeBorder(ZenithiumColor.hairline, lineWidth: 1)
                            )
                    )

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

            // Hayalet iskelet (skeleton): verinin nereye geleceğini gösteren %6 opaklıkta sessiz yer tutucular
            ghostSkeleton(layout)
                .opacity(0.06)
                .allowsHitTesting(false)
        }
    }

    private var effectiveActionCallout: String {
        if let actionCallout, !actionCallout.isEmpty {
            return actionCallout
        }
        switch reason {
        case .noOvernightData, .sleepImplausible:
            return "Apple Watch'unuzu bu gece kolunuzda tutarak uyuyun."
        case .noHeartRateYet:
            return "İlk gecenizden sonra toparlanma skorunuz burada hesaplanacak."
        case .recoveryUnavailable:
            return "İlk gecenizden sonra toparlanma skorunuz burada hesaplanacak."
        case .notEnoughHistory:
            return "En az 3 günlük veri toplandığında eğilimler burada görünecek."
        case .nothingLogged(let what):
            if what.localizedCaseInsensitiveContains("kas") || what.localizedCaseInsensitiveContains("kuvvet") {
                return "Bir kuvvet antrenmanı tamamlayın."
            } else if what.localizedCaseInsensitiveContains("tahlil") || what.localizedCaseInsensitiveContains("kan") {
                return "Sağlık ocağı veya laboratuvar tahlilinizi PDF olarak aktarın."
            } else if what.localizedCaseInsensitiveContains("antrenman") || what.localizedCaseInsensitiveContains("yük") {
                return "Antrenman uygulamasından ilk antrenmanınızı kaydedin."
            } else if what.localizedCaseInsensitiveContains("öneri") || what.localizedCaseInsensitiveContains("neden") {
                return "Günün önerisi oluştuktan sonra karar gerekçesi burada incelenebilir."
            } else {
                return "Yeni bir kayıt ekleyerek başlayın."
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

    @ViewBuilder
    private func ghostSkeleton(_ layout: SkeletonLayout) -> some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
            switch layout {
            case .scored:
                HStack {
                    Spacer()
                    Circle()
                        .stroke(ZenithiumColor.textPrimary, lineWidth: 8)
                        .frame(width: 120, height: 120)
                    Spacer()
                }
                RoundedRectangle(cornerRadius: ZenithiumRadius.card)
                    .fill(ZenithiumColor.textPrimary)
                    .frame(height: 50)
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: ZenithiumRadius.card).fill(ZenithiumColor.textPrimary).frame(height: 40)
                    RoundedRectangle(cornerRadius: ZenithiumRadius.card).fill(ZenithiumColor.textPrimary).frame(height: 40)
                    RoundedRectangle(cornerRadius: ZenithiumRadius.card).fill(ZenithiumColor.textPrimary).frame(height: 40)
                }
            case .chart:
                RoundedRectangle(cornerRadius: ZenithiumRadius.card)
                    .fill(ZenithiumColor.textPrimary)
                    .frame(height: 160)
                RoundedRectangle(cornerRadius: ZenithiumRadius.card)
                    .fill(ZenithiumColor.textPrimary)
                    .frame(height: 70)
            case .cards:
                RoundedRectangle(cornerRadius: ZenithiumRadius.card)
                    .fill(ZenithiumColor.textPrimary)
                    .frame(height: 60)
                RoundedRectangle(cornerRadius: ZenithiumRadius.card)
                    .fill(ZenithiumColor.textPrimary)
                    .frame(height: 60)
                RoundedRectangle(cornerRadius: ZenithiumRadius.card)
                    .fill(ZenithiumColor.textPrimary)
                    .frame(height: 60)
            }
        }
        .padding(.horizontal, ZenithiumSpacing.m)
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
    var actionCallout: String? = nil

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
            NoDataView(
                reason: reason,
                actionCallout: actionCallout,
                layout: loadingLayout,
                retry: retry
            )

        case .loaded(let value):
            loaded(value)

        case .failed(let error):
            ErrorStateView(error: error, retry: retry)
        }
    }
}
