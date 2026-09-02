//
//  SettingsView.swift
//  Zenithium
//
//  Settings. Spec §10, and §12's requirement that the disclaimer and privacy statements are
//  reachable from here.
//

import SwiftUI

struct SettingsView: View {

    @State var viewModel: SettingsViewModel
    @State private var maxHeartRateText = ""
    @State private var isConfirmingRebuild = false

    var body: some View {
        NavigationStack {
            Form {
                ViewStateContainer(
                    state: viewModel.state,
                    loadingLabel: "Ayarlar yükleniyor",
                    retry: { await viewModel.load() },
                    requestAccess: nil
                ) { content in
                    sections(content)
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(ZenithiumColor.background.ignoresSafeArea())
            .navigationTitle("Ayarlar")
            .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
        }
        .zenithiumBackground(tint: ZenithiumColor.spectrumIndigo, intensity: 0.3)
        .task { await viewModel.onAppear() }
    }

    @ViewBuilder
    private func sections(_ content: SettingsViewModel.Content) -> some View {
        lensSection(content)
        cycleSection(content)
        clinicalSection(content)
        profileSection(content)
        sleepSection(content)
        strainSection(content)
        unitsSection(content)
        appearanceSection(content)
        dataSection(content)
        safetySection
        aboutSection(content)
    }

    /// The palette. Yol haritası v4, B6.
    ///
    /// Dark is first and is the default, because it is the app's identity rather than a
    /// fallback. Following the phone is offered and is not the default: an app that changed
    /// colour on somebody because of an update they did not read would be making the choice
    /// for them in the other direction.
    private func appearanceSection(_ content: SettingsViewModel.Content) -> some View {
        Section {
            ForEach(AppearancePreference.allCases) { option in
                Button {
                    Task { await viewModel.setAppearance(option) }
                } label: {
                    HStack(spacing: ZenithiumSpacing.m) {
                        VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                            Text(option.displayName)
                                .foregroundStyle(ZenithiumColor.textPrimary)
                            Text(option.subtitle)
                                .font(ZenithiumFont.caption)
                                .foregroundStyle(ZenithiumColor.textSecondary)
                        }
                        Spacer(minLength: 0)
                        if content.profile.appearance == option {
                            Image(systemName: "checkmark")
                                .foregroundStyle(ZenithiumColor.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(
                    content.profile.appearance == option ? [.isButton, .isSelected] : .isButton
                )
            }
        } header: {
            Text("Görünüm")
        }
        .sensoryFeedback(.selection, trigger: content.profile.appearance)
    }

    private func lensSection(_ content: SettingsViewModel.Content) -> some View {
        Section {
            ForEach(TrainingLens.allCases) { lens in
                Button {
                    Task { await viewModel.setTrainingLens(lens) }
                } label: {
                    HStack(spacing: ZenithiumSpacing.m) {
                        // Drawn rather than an SF Symbol: this is the one screen that asks
                        // what kind of athlete somebody is, and it used the same four glyphs
                        // as every other fitness app's onboarding. Yol haritası v4, B9.
                        LensMark(lens: lens)
                            .frame(width: 26)
                            .foregroundStyle(
                                content.profile.trainingLens == lens
                                    ? ZenithiumColor.accent
                                    : ZenithiumColor.textSecondary
                            )
                        VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                            Text(lens.displayName)
                                .foregroundStyle(ZenithiumColor.textPrimary)
                            Text(lens.subtitle)
                                .font(ZenithiumFont.caption)
                                .foregroundStyle(ZenithiumColor.textSecondary)
                        }
                        Spacer(minLength: 8)
                        if content.profile.trainingLens == lens {
                            Image(systemName: "checkmark")
                                .foregroundStyle(ZenithiumColor.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(
                    content.profile.trainingLens == lens ? [.isButton, .isSelected] : .isButton
                )
            }
        } header: {
            Text("Mercek")
        } footer: {
            Text("Mercek hesaplamayı değiştirmez — toparlanma, zorlanma ve uyku dört mercekte de aynı sayıyı üretir. Değişen, hangi ekranların öne çıktığı.")
        }
    }

    /// Faz 12 — cycle awareness, opt-in and never inferred.
    ///
    /// The footer earns its length. This is the one setting that asks for a category of
    /// health data people are rightly careful about, so it says what is read, what it is
    /// used for, and what Zenithium will never do with it.
    private func cycleSection(_ content: SettingsViewModel.Content) -> some View {
        Section {
            Toggle(
                "Döngü farkındalığı",
                isOn: Binding(
                    get: { content.profile.tracksMenstrualCycle },
                    set: { newValue in Task { await viewModel.setTracksMenstrualCycle(newValue) } }
                )
            )
            .accessibilityHint("Toparlanmayı döngü fazına göre karşılaştırır")
        } header: {
            Text("Döngü")
        } footer: {
            Text("Açtığında Sağlık'tan yalnızca kaydettiğin regl günlerini okurum ve toparlanmanı, döngünün aynı fazındaki kendi geçmişinle karşılaştırırım. Luteal fazda istirahat nabzı 2–5 atım yükselir ve HRV düşer; bunu bilmeyen bir motor tamamen normal bir sabahı kötü okur.\n\nGebelik çıkarımı yapmam, doğurgan pencere hesaplamam, döngünü düzenli ya da düzensiz diye nitelemem. Veri cihazdan çıkmaz.")
        }
    }

    private func profileSection(_ content: SettingsViewModel.Content) -> some View {
        Section {
            DatePicker(
                "Doğum tarihi",
                selection: dateOfBirthBinding(content),
                in: ...Date(),
                displayedComponents: .date
            )

            Picker("Biyolojik cinsiyet", selection: sexBinding(content)) {
                ForEach(BiologicalSexValue.allCases, id: \.self) { sex in
                    Text(sex.displayName).tag(sex)
                }
            }
        } header: {
            Text("Sen")
        } footer: {
            Text("Yaş, yedek maksimum nabzı belirler; cinsiyet ise antrenman yükü sabitlerini seçer. İkisi de isteğe bağlı — olmadıklarında belgelenmiş varsayılanları kullanırım.")
        }
    }

    private func sleepSection(_ content: SettingsViewModel.Content) -> some View {
        Section {
            LabeledContent("Uyku ihtiyacı") {
                Text("\(ZenithiumFormat.metric(content.profile.baselineSleepNeedHours, digits: 1)) h")
                    .font(ZenithiumFont.callout.monospacedDigit())
            }
            Slider(
                value: sleepNeedBinding(content),
                in: UserProfile.sleepNeedRange,
                step: 0.25
            ) {
                Text("Uyku ihtiyacı")
            }
            .accessibilityLabel("Taban uyku ihtiyacı")
            .accessibilityValue("\(ZenithiumFormat.metric(content.profile.baselineSleepNeedHours, digits: 1)) saat")
        } header: {
            Text("Uyku")
        } footer: {
            Text("Başlangıç noktan. Dünkü zorlanma ve uyku borcu için üstüne eklerim, şekerlemeler için düşerim.")
        }
    }

    private func strainSection(_ content: SettingsViewModel.Content) -> some View {
        Section {
            Picker("Gün şurada başlar", selection: dayBoundaryBinding(content)) {
                ForEach(DayBoundary.allCases, id: \.self) { boundary in
                    Text(boundary.displayName).tag(boundary)
                }
            }
            Text(content.profile.dayBoundary.explanation)
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textSecondary)

            HStack {
                Text("Maksimum nabız")
                Spacer()
                TextField("Otomatik", text: $maxHeartRateText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                    .font(ZenithiumFont.callout.monospacedDigit())
                    .onSubmit { Task { await submitMaxHeartRate() } }
                Text("bpm")
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textSecondary)
            }
            .accessibilityElement(children: .contain)

            if let error = viewModel.saveError, error.isRetryable == false {
                Text(error.errorDescription ?? "")
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.red)
            }
        } header: {
            Text("Zorlanma")
        } footer: {
            Text("Maksimumu boş bırakırsan gözlediğim değer ile yaşa dayalı tahminin yüksek olanını kullanırım.")
        }
        .onAppear {
            if let override = content.profile.maxHeartRateOverride {
                maxHeartRateText = ZenithiumFormat.metric(override, digits: 0)
            }
        }
    }

    private func unitsSection(_ content: SettingsViewModel.Content) -> some View {
        Section {
            Picker("Birimler", selection: unitBinding(content)) {
                ForEach(UnitPreference.allCases, id: \.self) { preference in
                    Text(preference.displayName).tag(preference)
                }
            }
        } header: {
            Text("Görünüm")
        } footer: {
            Text("Yalnızca görünüm. Her şey iki durumda da aynı birimlerle saklanır ve hesaplanır.")
        }
    }

    private func dataSection(_ content: SettingsViewModel.Content) -> some View {
        Section {
            LabeledContent("Sağlık erişimi") {
                Text(authorizationLabel(content.authorization))
                    .foregroundStyle(authorizationTint(content.authorization))
            }

            Button(role: .destructive) {
                isConfirmingRebuild = true
            } label: {
                Text("Taban çizgilerini yeniden kur")
            }
            .disabled(viewModel.isSaving)
            .confirmationDialog(
                "Taban çizgileri yeniden kurulsun mu?",
                isPresented: $isConfirmingRebuild,
                titleVisibility: .visible
            ) {
                Button("Yeniden kur", role: .destructive) {
                    Task { await viewModel.rebuildBaselines() }
                }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("Puanlarken karşılaştırdığım 60 günlük ortalamaları unutup Sağlık'tan yeniden kuracağım. Yeterli gece birikene kadar puanlar kalibrasyonda görünecek.")
            }
        } header: {
            Text("Veri")
        } footer: {
            Text("Uzun bir aradan ya da yeni bir saatten sonra yapmaya değer; eski taban çizgisi artık içinde bulunduğundan farklı bir durumu anlatıyordur.")
        }
    }

    private var safetySection: some View {
        Section {
            NavigationLink { DisclaimerView() } label: {
                Label(SafetyCopy.disclaimerTitle, systemImage: "cross.case")
            }
            NavigationLink { PrivacyView() } label: {
                Label(SafetyCopy.privacyTitle, systemImage: "lock.shield")
            }
            if let supportURL = SystemURL.support {
                Link(destination: supportURL) {
                    Label("Destek ve İletişim", systemImage: "questionmark.circle")
                }
            }
        } header: {
            Text("Zenithium hakkında")
        }
    }

    private func aboutSection(_ content: SettingsViewModel.Content) -> some View {
        Section {
            LabeledContent("Motor sürümü") {
                Text("\(content.engineVersion)")
                    .font(ZenithiumFont.callout.monospacedDigit())
            }
            LabeledContent("Paylaşılan kapsayıcı") {
                Text(content.appGroupIdentifier)
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } footer: {
            Text(SafetyCopy.disclaimerFooter)
        }
    }

    // MARK: - Bindings

    private func dateOfBirthBinding(_ content: SettingsViewModel.Content) -> Binding<Date> {
        Binding(
            get: { content.profile.dateOfBirth ?? Date(timeIntervalSince1970: 0) },
            set: { newValue in Task { await viewModel.setDateOfBirth(newValue) } }
        )
    }

    private func sexBinding(_ content: SettingsViewModel.Content) -> Binding<BiologicalSexValue> {
        Binding(
            get: { content.profile.biologicalSex },
            set: { newValue in Task { await viewModel.setBiologicalSex(newValue) } }
        )
    }

    private func sleepNeedBinding(_ content: SettingsViewModel.Content) -> Binding<Double> {
        Binding(
            get: { content.profile.baselineSleepNeedHours },
            set: { newValue in Task { await viewModel.setSleepNeed(newValue) } }
        )
    }

    private func dayBoundaryBinding(_ content: SettingsViewModel.Content) -> Binding<DayBoundary> {
        Binding(
            get: { content.profile.dayBoundary },
            set: { newValue in Task { await viewModel.setDayBoundary(newValue) } }
        )
    }

    private func unitBinding(_ content: SettingsViewModel.Content) -> Binding<UnitPreference> {
        Binding(
            get: { content.profile.unitPreference },
            set: { newValue in Task { await viewModel.setUnitPreference(newValue) } }
        )
    }

    private func submitMaxHeartRate() async {
        let trimmed = maxHeartRateText.trimmingCharacters(in: .whitespaces)
        await viewModel.setMaxHeartRateOverride(trimmed.isEmpty ? nil : Double(trimmed))
    }

    private func authorizationLabel(_ state: HealthAuthorizationState) -> String {
        switch state {
        case .authorized: return "Verildi"
        case .denied: return "Kapalı"
        case .notDetermined: return "Sorulmadı"
        case .unavailable: return "Kullanılamıyor"
        }
    }

    private func authorizationTint(_ state: HealthAuthorizationState) -> Color {
        switch state {
        case .authorized: return ZenithiumColor.green
        case .denied: return ZenithiumColor.red
        case .notDetermined, .unavailable: return ZenithiumColor.textSecondary
        }
    }

    private func clinicalSection(_ content: SettingsViewModel.Content) -> some View {
        Section {
            ForEach(ClinicalModifierRegistry.allModifiers) { modifier in
                let isEnabled = !ClinicalModifierRegistry.disabledModifierIDs().contains(modifier.id)
                Toggle(isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        ClinicalModifierRegistry.setModifier(id: modifier.id, isEnabled: newValue)
                    }
                )) {
                    VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                        Text(modifier.title)
                            .foregroundStyle(ZenithiumColor.textPrimary)
                        Text(modifier.rationale)
                            .font(ZenithiumFont.caption)
                            .foregroundStyle(ZenithiumColor.textSecondary)
                    }
                }
                .tint(ZenithiumColor.accent)
            }
        } header: {
            Text("Klinik Bağlam")
        } footer: {
            Text("Laboratuvar ve EKG bulgularının karar güvenine etkisini tek tek yönetin. Devre dışı bırakılan düzenleyiciler toparlanma ve yük güvenini etkilemez.")
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textTertiary)
        }
    }
}
