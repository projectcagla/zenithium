//
//  OnboardingView.swift
//  Zenithium
//
//  Onboarding: welcome → disclaimer → permissions → profile → done.
//
//  Spec §12 requires the disclaimer here. §5.6 requires denial to be recoverable, so the
//  permission step advances whether or not access was granted — Zenithium works with whatever
//  the user allows, and the gate on each screen explains what is missing.
//

import SwiftUI

struct OnboardingView: View {

    @State var viewModel: OnboardingViewModel
    let onFinished: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: ZenithiumSpacing.none) {
                progressBar
                ScrollView {
                    stepContent
                        .padding(.horizontal, ZenithiumSpacing.xl)
                        .padding(.vertical, ZenithiumSpacing.xl)
                }
                .scrollBounceBehavior(.basedOnSize)
                footer
            }
            .background(ZenithiumColor.background.ignoresSafeArea())
            .navigationTitle(viewModel.step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
        }
        .tint(ZenithiumColor.accent)
        .task { await viewModel.onAppear() }
        .onChange(of: viewModel.step) { _, newValue in
            if newValue == .done { onFinished() }
        }
    }

    private var progressBar: some View {
        ProgressView(
            value: Double(viewModel.step.rawValue),
            total: Double(OnboardingViewModel.Step.done.rawValue)
        )
        .tint(ZenithiumColor.accent)
        .padding(.horizontal, ZenithiumSpacing.xl)
        .accessibilityLabel("Kurulum ilerlemesi")
        .accessibilityValue("\(OnboardingViewModel.Step.allCases.count) adımdan \(viewModel.step.rawValue + 1). adım")
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .welcome: welcomeStep
        case .disclaimer: disclaimerStep
        case .permissions: permissionsStep
        case .profile: profileStep
        case .done: doneStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.l) {
            Image(systemName: "bolt.heart")
                .font(.system(size: 48, weight: .regular, design: .rounded))
                .foregroundStyle(ZenithiumColor.accent)
                .accessibilityHidden(true)

            Text("Zenithium, saatinin zaten kaydettiğini antrenman yönlendirmesine çevirir.")
                .font(ZenithiumFont.title)
                .foregroundStyle(ZenithiumColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                point("Toparlanma", "Vücudunun bugün ne kadar yüke hazır olduğu.", "heart.fill")
                point("Zorlanma", "Toparlanmanın koyduğu hedefe göre ne kadar zorladığın.", "flame.fill")
                point("Kaslar", "Hangi grupların toparlandığı, hangilerinin hâlâ yük taşıdığı.", "figure.strengthtraining.traditional")
                point("Günün", "Ne zaman keskin olacağın, ne zaman olmayacağın.", "sun.max.fill")
            }

            Text("Bir topluluğa değil sana göre kalibre olur; bu yüzden ilk iki hafta senin normalini öğrenmekle geçer.")
                .font(ZenithiumFont.callout)
                .foregroundStyle(ZenithiumColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var disclaimerStep: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.l) {
            Image(systemName: "cross.case")
                .font(.system(size: 40, weight: .regular, design: .rounded))
                .foregroundStyle(ZenithiumColor.accent)
                .accessibilityHidden(true)

            Text(SafetyCopy.disclaimerBody)
                .font(ZenithiumFont.body)
                .foregroundStyle(ZenithiumColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.l) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 40, weight: .regular, design: .rounded))
                .foregroundStyle(ZenithiumColor.accent)
                .accessibilityHidden(true)

            Text(SafetyCopy.authorizationBody)
                .font(ZenithiumFont.body)
                .foregroundStyle(ZenithiumColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            SectionCard(title: "Neleri okur") {
                VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                    ForEach(HealthDataKind.allCases, id: \.self) { kind in
                        HStack(spacing: ZenithiumSpacing.s) {
                            Image(systemName: "checkmark.circle")
                                .imageScale(.small)
                                .foregroundStyle(ZenithiumColor.green)
                                .accessibilityHidden(true)
                            Text(kind.displayName.capitalized)
                                .font(ZenithiumFont.callout)
                                .foregroundStyle(ZenithiumColor.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Text("Zenithium Sağlık'a hiçbir şey geri yazmaz ve hiçbir yere bir şey göndermez.")
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.authorization == .denied {
                Text(SafetyCopy.authorizationDeniedBody)
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.yellow)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.l) {
            Text("Hepsi isteğe bağlı. Atladığın her şey için belgelenmiş varsayılanlarım var.")
                .font(ZenithiumFont.callout)
                .foregroundStyle(ZenithiumColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            SectionCard(title: "Sen") {
                VStack(alignment: .leading, spacing: ZenithiumSpacing.l) {
                    DatePicker(
                        "Doğum tarihi",
                        selection: Binding(
                            get: { viewModel.dateOfBirth ?? Date(timeIntervalSince1970: 0) },
                            set: { viewModel.dateOfBirth = $0 }
                        ),
                        in: ...Date(),
                        displayedComponents: .date
                    )

                    Picker("Biyolojik cinsiyet", selection: $viewModel.biologicalSex) {
                        ForEach(BiologicalSexValue.allCases, id: \.self) { sex in
                            Text(sex.displayName).tag(sex)
                        }
                    }

                    VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                        HStack {
                            Text("Uyku ihtiyacı")
                                .font(ZenithiumFont.label)
                            Spacer()
                            Text("\(ZenithiumFormat.metric(viewModel.sleepNeedHours, digits: 1)) h")
                                .font(ZenithiumFont.callout.monospacedDigit())
                                .foregroundStyle(ZenithiumColor.textSecondary)
                        }
                        Slider(
                            value: $viewModel.sleepNeedHours,
                            in: UserProfile.sleepNeedRange,
                            step: 0.25
                        )
                        .accessibilityLabel("Taban uyku ihtiyacı")
                        .accessibilityValue("\(ZenithiumFormat.metric(viewModel.sleepNeedHours, digits: 1)) saat")
                    }
                }
            }

            SectionCard(title: "Zenithium neyi kullanacak") {
                let implied = viewModel.impliedMaxHeartRate
                VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                    LabeledContent("Maksimum nabız") {
                        Text("\(ZenithiumFormat.metric(implied.value, digits: 0)) bpm")
                            .font(ZenithiumFont.callout.monospacedDigit())
                    }
                    Text(implied.source.displayName)
                        .font(ZenithiumFont.caption)
                        .foregroundStyle(
                            implied.source.invitesCorrection
                                ? ZenithiumColor.yellow
                                : ZenithiumColor.textTertiary
                        )
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.l) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 48, weight: .regular, design: .rounded))
                .foregroundStyle(ZenithiumColor.green)
                .accessibilityHidden(true)

            Text("Saatini gece tak, sabah senin için bir puanım olacak.")
                .font(ZenithiumFont.body)
                .foregroundStyle(ZenithiumColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(spacing: ZenithiumSpacing.m) {
            if let error = viewModel.error {
                Text(error.errorDescription ?? "")
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.yellow)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await advance() }
            } label: {
                Text(primaryActionTitle)
                    .font(ZenithiumFont.label)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ZenithiumSpacing.xs)
            }
            .buttonStyle(.borderedProminent)
            .tint(ZenithiumColor.accent)
            .disabled(viewModel.isWorking)

            if viewModel.step != .welcome && viewModel.step != .done {
                Button("Geri") { viewModel.back() }
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textSecondary)
            }
        }
        .padding(.horizontal, ZenithiumSpacing.xl)
        .padding(.bottom, ZenithiumSpacing.xl)
    }

    private var primaryActionTitle: String {
        switch viewModel.step {
        case .welcome: return "Başla"
        case .disclaimer: return SafetyCopy.disclaimerAcknowledgement
        case .permissions: return viewModel.authorization.shouldPrompt ? "Sağlık erişimine izin ver" : "Devam"
        case .profile: return "Bitir"
        case .done: return "Zenithium'u aç"
        }
    }

    private func advance() async {
        switch viewModel.step {
        case .welcome:
            viewModel.advance()
        case .disclaimer:
            await viewModel.acknowledgeDisclaimer()
        case .permissions:
            if viewModel.authorization.shouldPrompt {
                await viewModel.requestPermissions()
            } else {
                viewModel.advance()
            }
        case .profile:
            await viewModel.finish()
        case .done:
            onFinished()
        }
    }

    private func point(_ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(alignment: .top, spacing: ZenithiumSpacing.m) {
            Image(systemName: symbol)
                .frame(width: 26)
                .foregroundStyle(ZenithiumColor.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                Text(title)
                    .font(ZenithiumFont.label)
                    .foregroundStyle(ZenithiumColor.textPrimary)
                Text(detail)
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
