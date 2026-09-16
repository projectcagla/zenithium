import SwiftUI

struct SettingsView: View {
    var onRestored: () -> Void = {}
    @State var viewModel: SettingsViewModel
    var archive: ArchiveService? = nil
    var onErase: (() async throws -> Void)? = nil
    @State private var maxHeartRateText = ""
    @State private var confirmsBaseline = false
    @State private var confirmsErase = false
    @State private var isErasing = false
    @State private var eraseError: String?
    @State private var editsBirthDate = false
    @State private var birthDateDraft = Date()
    @State private var birthDateChanged = false

    var body: some View {
        Form {
            ViewStateContainer(state: viewModel.state, loadingLabel: "Ayarlar yükleniyor",
                retry: { await viewModel.load() }, requestAccess: { await viewModel.requestHealth() }) { content in
                sections(content)
            }
            if let error = viewModel.saveError {
                Section { Text(error.localizedDescription).foregroundStyle(ZenithiumColor.red) }
            }
            if let eraseError { Section { Text(eraseError).foregroundStyle(ZenithiumColor.red) } }
        }
        .scrollContentBackground(.hidden)
        .background(ZenithiumColor.background.ignoresSafeArea())
        .navigationTitle("Ayarlar")
        .disabled(viewModel.isSaving || isErasing)
        .task { await viewModel.onAppear() }
        .tint(ZenithiumColor.accent)
        .sheet(isPresented: $editsBirthDate) {
            NavigationStack {
                Form {
                    DatePicker("Doğum tarihi", selection: $birthDateDraft, in: ...Date(), displayedComponents: .date)
                        .onChange(of: birthDateDraft) { _, _ in birthDateChanged = true }
                    if let error = viewModel.saveError { Text(error.localizedDescription).foregroundStyle(ZenithiumColor.red) }
                }
                .navigationTitle("Doğum tarihin")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { editsBirthDate = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Kaydet") { Task { await viewModel.setDateOfBirth(birthDateDraft); if viewModel.saveError == nil { editsBirthDate = false } } }
                            .disabled(!birthDateChanged || viewModel.isSaving)
                    }
                }
            }
        }
        .confirmationDialog("Kişisel tabanın yeniden başlatılsın mı?", isPresented: $confirmsBaseline, titleVisibility: .visible) {
            Button("Bugünden başlat", role: .destructive) { Task { await viewModel.rebuildBaselines() } }
        } message: {
            Text("Geçmiş kayıtların kalır. Yeni toparlanma hesapları yalnızca bugünden sonra biriken gecelerle karşılaştırılır; yeterli veri birikene kadar puan gösterilmez.")
        }
        .confirmationDialog("Zenithium kayıtların silinsin mi?", isPresented: $confirmsErase, titleVisibility: .visible) {
            Button("Tümünü sil", role: .destructive) {
                guard let onErase else { return }
                isErasing = true
                Task {
                    defer { isErasing = false }
                    do { try await onErase() }
                    catch { eraseError = "Silme tamamlanamadı: \(error.localizedDescription). Tekrar deneyebilirsin." }
                }
            }
        } message: {
            Text("Tahliller, belgeler, günlük, antrenman kayıtları ve tercihler bu uygulamadan silinir. Apple Sağlık'taki kaynak veriler ve senin paylaştığın arşiv kopyaları korunur. Yeniden kurulumda Sağlık verileri tekrar okunabilir.")
        }
    }

    @ViewBuilder private func sections(_ content: SettingsViewModel.Content) -> some View {
        profileSection(content)
        healthSection(content)
        Section("Kişisel taban") {
            LabeledContent("Geçerli HRV gecesi", value: "\(content.baselineNights) gece")
            ProgressView(value: Double(min(content.baselineNights, 14)), total: 14)
                .accessibilityLabel("Kişisel taban için \(content.baselineNights) gece birikti")
            Text(content.baselineNights >= 14 ? "Başlangıç tabanın hazır; yeni gecelerle gelişmeye devam eder." : "İlk 14 geçerli gecede kişisel tabanın oluşur. Uyku süren ve kayıtların bu sırada da görünür.")
                .font(ZenithiumFont.caption)
            if let start = content.preferences.baselineStart {
                LabeledContent("Başlangıç", value: start.formatted(.dateTime.day().month().year().locale(Locale(identifier: "tr_TR"))))
            }
            Button("Tabanı yeniden başlat", role: .destructive) { confirmsBaseline = true }
        }
        Section {
            Picker("Hedef profil", selection: Binding(get: { content.profile.trainingLens }, set: { value in Task { await viewModel.setTrainingLens(value) } })) {
                ForEach(TrainingLens.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Karar yaklaşımı", selection: Binding(get: { content.preferences.decision }, set: { value in Task { await viewModel.setPreferences { $0.decision = value } } })) {
                ForEach(DecisionPreference.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        } header: { Text("Antrenman kararları") } footer: {
            Text("İhtiyatlı yaklaşım yüksek yük önermeden önce daha güçlü toparlanma bekler. Hedef profil önerilen etkinlikleri değiştirir. Bu tercihler ölçülen toparlanma puanını değiştirmez; sakatlanma riskini hesaplamaz.")
        }
        sleepSection(content)
        Section("Benim bağlamım") {
            NavigationLink("Geçici koşullarımı düzenle") { PersonalContextView(viewModel: viewModel) }
            let active = content.preferences.contexts.filter { $0.isActive(at: Date()) }
            Text(active.isEmpty ? "Etkin bağlam kaydı yok." : active.map { $0.kind.title }.joined(separator: ", "))
                .font(ZenithiumFont.caption)
        }
        notificationsSection(content)
        Section("Bağlantılar") {
            LabeledContent("Widget'lar", value: viewModel.integrations.widgets)
            LabeledContent("Canlı etkinlikler", value: viewModel.integrations.liveActivities)
            LabeledContent("Apple Watch", value: viewModel.integrations.watch)
            if let date = viewModel.integrations.lastSummary {
                LabeledContent("Son paylaşılan özet", value: date.formatted(.dateTime.day().month().hour().minute().locale(Locale(identifier: "tr_TR"))))
            }
            Text("Saat bağlantısı anlık erişimi gösterir; Sağlık verilerinin aktarımı ayrıca gecikebilir.").font(ZenithiumFont.caption)
        }
        Section("Görünüm ve dil") {
            Picker("Birimler", selection: Binding(get: { content.profile.unitPreference }, set: { value in Task { await viewModel.setUnitPreference(value) } })) {
                ForEach(UnitPreference.allCases, id: \.self) { Text($0 == .metric ? "Metrik · km, °C" : "İngiliz · mil, °F").tag($0) }
            }
            Picker("Görünüm", selection: Binding(get: { content.profile.appearance }, set: { value in Task { await viewModel.setAppearance(value) } })) {
                ForEach(AppearancePreference.allCases) { Text($0.displayName).tag($0) }
            }
            LabeledContent("Uygulama dili", value: "Türkçe")
            Text("Bu sürüm Türkçe sunulur. Birimler yalnızca gösterimi değiştirir; hesaplar aynı ölçüm birimleriyle yapılır.").font(ZenithiumFont.caption)
        }
        Section("Verilerin") {
            if let archive { NavigationLink("Dışa aktar veya içe aktar") { DataTransferView(service: archive, onRestored: onRestored) } }
            if onErase != nil { Button("Tüm verilerimi sil", role: .destructive) { confirmsErase = true } }
        }
        Section("Şeffaflık") {
            NavigationLink("Hesaplar, eşikler ve kaynaklar") { EvidenceLibraryView() }
            DisclosureGroup("Tahlil ve EKG bağlamı") {
                ForEach(ClinicalModifierRegistry.allModifiers) { modifier in
                    Toggle(modifier.title, isOn: Binding(
                        get: { !content.preferences.disabledClinicalModifierIDs.contains(modifier.id) },
                        set: { enabled in Task { await viewModel.setPreferences {
                            if enabled { $0.disabledClinicalModifierIDs.remove(modifier.id) }
                            else { $0.disabledClinicalModifierIDs.insert(modifier.id) }
                        } } }
                    ))
                    Text(modifier.rationale).font(ZenithiumFont.caption)
                }
            }
            NavigationLink(SafetyCopy.disclaimerTitle) { DisclaimerView() }
            NavigationLink(SafetyCopy.privacyTitle) { PrivacyView() }
        }
        Section("Zenithium") {
            LabeledContent("Sürüm", value: versionLabel)
            LabeledContent("Hesaplama sürümü", value: "\(content.engineVersion)")
            if let url = URL(string: "mailto:hi@zenithium.app") { Link("hi@zenithium.app", destination: url) }
            if let url = SystemURL.support { Link("Destek", destination: url) }
        }
    }

    private func profileSection(_ content: SettingsViewModel.Content) -> some View {
        Section {
            if let date = content.profile.dateOfBirth {
                LabeledContent("Doğum tarihi", value: date.formatted(.dateTime.day().month().year().locale(Locale(identifier: "tr_TR"))))
                Button("Doğum tarihini kaldır", role: .destructive) { Task { await viewModel.setDateOfBirth(nil) } }
            }
            Button(content.profile.dateOfBirth == nil ? "Doğum tarihi ekle" : "Doğum tarihini düzenle") {
                birthDateDraft = content.profile.dateOfBirth ?? Date()
                birthDateChanged = false
                editsBirthDate = true
            }
            Picker("Biyolojik cinsiyet", selection: Binding(get: { content.profile.biologicalSex }, set: { value in Task { await viewModel.setBiologicalSex(value) } })) {
                ForEach(BiologicalSexValue.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                Text("Maksimum nabız").font(ZenithiumFont.body)
                TextField("Otomatik", text: $maxHeartRateText)
                    .font(.body)
                    .keyboardType(.numberPad)
                    .accessibilityLabel("Maksimum nabız, atım/dakika. Otomatik tahmin için boş bırak.")
                Button("Kaydet") {
                    let trimmed = maxHeartRateText.trimmingCharacters(in: .whitespaces)
                    Task { await viewModel.setMaxHeartRateText(trimmed) }
                }
            }
            .onAppear { maxHeartRateText = content.profile.maxHeartRateOverride.map { ZenithiumFormat.metric($0, digits: 0) } ?? "" }
        } header: { Text("Profil") } footer: {
            Text("Yaş maksimum nabız tahmininde, biyolojik cinsiyet nabza dayalı yük katsayısında kullanılır. İsteğe bağlıdır. Hesapta kullanılmayan boy veya kilo istenmez.")
        }
    }

    private func healthSection(_ content: SettingsViewModel.Content) -> some View {
        Section {
            LabeledContent("Sağlık erişimi", value: healthLabel(content.authorization))
            Button("Sağlık erişimini gözden geçir") { Task { await viewModel.requestHealth() } }
            if let url = SystemURL.appSettings { Link("iPhone ayarlarını aç", destination: url) }
            Text("Sağlık → profilin → Uygulamalar → Zenithium yolundan tek tek veri türlerini yönetebilirsin.")
                .font(ZenithiumFont.caption)
        } header: { Text("Apple Sağlık") } footer: {
            Text("Apple, hangi okuma izinlerini kapattığını uygulamalara açıklamaz. İzin ekranının tamamlanması bütün verilerin okunabildiği anlamına gelmez; eksik kayıt izin, ölçüm veya eşitleme kaynaklı olabilir.")
        }
    }

    private func sleepSection(_ content: SettingsViewModel.Content) -> some View {
        Section {
            LabeledContent("Taban uyku ihtiyacı", value: "\(ZenithiumFormat.metric(content.profile.baselineSleepNeedHours, digits: 2)) saat")
            Slider(value: Binding(get: { content.profile.baselineSleepNeedHours }, set: { value in Task { await viewModel.setSleepNeed(value) } }), in: UserProfile.sleepNeedRange, step: 0.25)
            Picker("Uyku saatleri tercihi", selection: Binding(get: { content.preferences.sleepTiming }, set: { value in
                Task { await viewModel.setPreferences { $0.sleepTiming = value; if let minute = value.suggestedWakeMinute { $0.wakeMinute = minute } } }
            })) { ForEach(SleepTimingPreference.allCases, id: \.self) { Text($0.title).tag($0) } }
            DatePicker("Hedef uyanış", selection: Binding(get: { time(content.preferences.wakeMinute) }, set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                Task { await viewModel.setPreferences { $0.wakeMinute = (components.hour ?? 7) * 60 + (components.minute ?? 0); $0.sleepTiming = .custom } }
            }), displayedComponents: .hourAndMinute)
            if let minute = content.preferences.bedtimeMinute(needHours: content.profile.baselineSleepNeedHours) {
                LabeledContent("Taban uyku penceresi", value: "\(clock(minute))–\(clock(content.preferences.wakeMinute))")
            }
            Picker("Antrenman günü başlangıcı", selection: Binding(get: { content.profile.dayBoundary }, set: { value in Task { await viewModel.setDayBoundary(value) } })) {
                ForEach(DayBoundary.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        } header: { Text("Uyku planın") } footer: {
            Text("Erken veya geç saat tercihi bir kronotip ölçümü değildir; uyanış hedefini belirlemek için başlangıç sağlar. Uyku ekranındaki yatış önerisi bu hedef ve o geceki hesaplanan ihtiyacından oluşur.")
        }
    }

    private func notificationsSection(_ content: SettingsViewModel.Content) -> some View {
        Section {
            LabeledContent("Sistem izni", value: viewModel.notificationAuthorization)
            Toggle("Sabah kararı", isOn: Binding(get: { content.preferences.morningReminder }, set: { enabled in Task { await viewModel.setPreferences({ $0.morningReminder = enabled }, requestNotifications: enabled) } }))
            Toggle("Eksik gece uyarısı", isOn: Binding(get: { content.preferences.missingNightReminder }, set: { enabled in Task { await viewModel.setPreferences({ $0.missingNightReminder = enabled }, requestNotifications: enabled) } }))
            Toggle("Haftalık özet", isOn: Binding(get: { content.preferences.weeklyReminder }, set: { enabled in Task { await viewModel.setPreferences({ $0.weeklyReminder = enabled }, requestNotifications: enabled) } }))
        } header: { Text("Bildirimler") } footer: {
            Text("Sabah hatırlatması uyanış hedefinden 15 dakika sonra, haftalık hatırlatma pazar 18.00'de gelir. Eksik gece uyarısı yeni veri okunduğunda gönderilir; kilitli cihazda veya eşitleme beklerken gecikebilir.")
        }
    }

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func time(_ minute: Int) -> Date { Calendar.current.date(from: DateComponents(hour: minute / 60, minute: minute % 60)) ?? Date() }
    private func clock(_ minute: Int) -> String { time(minute).formatted(.dateTime.hour().minute().locale(Locale(identifier: "tr_TR"))) }
    private func healthLabel(_ state: HealthAuthorizationState) -> String {
        switch state {
        case .authorized: return "İzin ekranı tamamlandı"
        case .notDetermined: return "İzin ekranı bekleniyor"
        case .denied: return "Erişim gerekli"
        case .unavailable: return "Bu cihazda kullanılamıyor"
        }
    }
}
