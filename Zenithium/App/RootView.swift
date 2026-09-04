//
//  RootView.swift
//  Zenithium
//
//  The tab shell and the onboarding gate. Spec §10.
//
//  View models are built once here and handed to their screens, so each screen owns exactly
//  one and nothing constructs its own dependencies (§6).
//

import SwiftUI

struct RootView: View {

    let dependencies: AppDependencies

    @State private var hasCompletedOnboarding: Bool?
    @State private var todayViewModel: TodayViewModel
    @State private var strainViewModel: StrainViewModel
    @State private var sleepViewModel: SleepViewModel
    @State private var muscleViewModel: MuscleMapViewModel
    @State private var trendsViewModel: TrendsViewModel
    @State private var bloodworkViewModel: BloodworkViewModel
    @State private var settingsViewModel: SettingsViewModel
    @State private var onboardingViewModel: OnboardingViewModel
    @State private var journalViewModel: JournalViewModel
    @State private var hybridViewModel: HybridViewModel
    @State private var trainingLoadViewModel: TrainingLoadViewModel
    @State private var vitalsViewModel: VitalsViewModel
    @State private var enduranceViewModel: EnduranceViewModel
    @State private var strengthViewModel: StrengthViewModel
    @State private var planViewModel: PlanViewModel
    @State private var reportViewModel: ReportViewModel
    @State private var documentsViewModel: DocumentsViewModel

    /// Aktif mercek. Profil okunana kadar dayanıklılık varsayılıyor — ilk karede sekmelerin
    /// yerinde durması, doğru olması kadar önemli.
    @State private var lens: TrainingLens = .endurance

    /// Which tab is showing. Bound so an App Intent can steer the app somewhere (Faz 22).
    @State private var selectedTab: RootTab = .today

    /// The palette the app draws in. Dark until the profile says otherwise, so the first
    /// frame is never the wrong colour. Yol haritası v4, B6.
    @State private var appearance: AppearancePreference = .default

    @Environment(\.scenePhase) private var scenePhase

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies

        let coordinator = dependencies.coordinator
        let store = dependencies.store
        let health = dependencies.health

        // Every screen reads day records through the one cache rather than through the
        // store, so the windows they ask for overlap instead of repeating. Yol haritası v4, A4.
        let records = dependencies.dayRecords

        // `HealthDataProviding` inherits `HealthAuthorizing`, so the provider is already a
        // permission gate — no cast, and no fallback that could silently swap in a mock.
        let authorizing: any HealthAuthorizing = health

        _todayViewModel = State(
            initialValue: TodayViewModel(
                coordinator: coordinator,
                health: authorizing,
                journal: store,
                bloodMarkers: store,
                records: records,
                sessions: store,
                cycleSource: health,
                goals: store,
                workoutSource: health
            )
        )
        _strainViewModel = State(
            initialValue: StrainViewModel(
                coordinator: coordinator,
                health: authorizing,
                records: records,
                stressSource: health
            )
        )
        _sleepViewModel = State(
            initialValue: SleepViewModel(
                coordinator: coordinator,
                health: authorizing,
                records: records
            )
        )
        _muscleViewModel = State(
            initialValue: MuscleMapViewModel(
                coordinator: coordinator,
                repository: store,
                painRepository: store,
                records: records
            )
        )
        _trendsViewModel = State(
            initialValue: TrendsViewModel(repository: records)
        )
        _bloodworkViewModel = State(
            initialValue: BloodworkViewModel(repository: store, profile: store)
        )
        _settingsViewModel = State(
            initialValue: SettingsViewModel(
                repository: store,
                baselines: store,
                health: authorizing,
                coordinator: coordinator
            )
        )
        _onboardingViewModel = State(
            initialValue: OnboardingViewModel(
                health: authorizing,
                profileRepository: store,
                coordinator: coordinator
            )
        )
        _journalViewModel = State(
            initialValue: JournalViewModel(journal: store, records: records, supplements: store)
        )
        _hybridViewModel = State(
            initialValue: HybridViewModel(
                repository: store,
                profiles: store,
                baselines: store
            )
        )
        _trainingLoadViewModel = State(
            initialValue: TrainingLoadViewModel(records: records)
        )
        _vitalsViewModel = State(
            initialValue: VitalsViewModel(vitals: health, records: records, profile: store)
        )
        _enduranceViewModel = State(
            initialValue: EnduranceViewModel(health: health)
        )
        _strengthViewModel = State(
            initialValue: StrengthViewModel(sessions: store, records: records, muscles: store)
        )
        _planViewModel = State(
            initialValue: PlanViewModel(goals: store, records: records)
        )
        _documentsViewModel = State(
            initialValue: DocumentsViewModel(repository: store)
        )
        _reportViewModel = State(
            initialValue: ReportViewModel(
                records: records,
                markers: store,
                profile: store,
                vitals: health
            )
        )
    }

    var body: some View {
        Group {
            switch hasCompletedOnboarding {
            case .none:
                // Held deliberately blank on the app's own background: a spinner here would
                // flash for one store read on every cold launch.
                ZenithiumColor.background.ignoresSafeArea()

            case .some(false):
                OnboardingView(viewModel: onboardingViewModel) {
                    hasCompletedOnboarding = true
                }

            case .some(true):
                tabs
            }
        }
        // Applied at the root so it reaches every sheet and every asset colour beneath it.
        // `nil` means follow the phone. Yol haritası v4, B6.
        .preferredColorScheme(appearance.colorScheme)
        .task { await loadOnboardingState() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                Task {
                    await dependencies.coordinator.cancelBackfill()
                }
            }
            guard newPhase == .active, hasCompletedOnboarding == true else { return }
            // The user is looking at the screen, so the device is unlocked. Anything a locked
            // background wake had to defer can run now, even if the unlock notification was
            // missed because the process had been suspended. Faz v4 / Adım 3.
            dependencies.scheduler.drainDeferredWork()
            Task {
                // Drained before anything reads the journal, so a behaviour tapped on the
                // home screen is already in the store when the app opens.
                if await PendingJournalDrain.drain(into: dependencies.store) {
                    await journalViewModel.load()
                }
                await todayViewModel.refresh()
                await refreshLens()
                applyPendingDeepLink()
            }
        }
        .onChange(of: settingsViewModel.state.value?.profile.trainingLens) { _, newLens in
            if let newLens { lens = newLens }
        }
        .onChange(of: settingsViewModel.state.value?.profile.appearance) { _, newAppearance in
            if let newAppearance { appearance = newAppearance }
        }
    }

    /// The custom 5-tab shell (Faz 6).
    ///
    /// Standart UITabBar yerine özel hafif tab bar:
    /// - 5 sekme: Bugün, Uyku, Yük, Trend, Kas
    /// - Yükseklik: 56pt + safe area
    /// - Arka plan: ZenithiumColor.background (%85 blur ile ultraThinMaterial)
    /// - Üst kenar: 1px hairline (#1F2836)
    /// - SF Symbol'ler: 20pt, .medium ağırlık (aktif textPrimary, pasif textTertiary)
    /// - Today sekmesi görsel ağırlığı: aktifken prizmatik spektrum noktası
    private var tabs: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .today:
                    TodayView(viewModel: todayViewModel)
                case .sleep:
                    SleepView(viewModel: sleepViewModel)
                case .load, .secondary:
                    TrainingLoadView(viewModel: trainingLoadViewModel)
                case .trends:
                    TrendsView(viewModel: trendsViewModel)
                case .muscle:
                    MuscleMapView(viewModel: muscleViewModel)
                case .journal:
                    JournalView(viewModel: journalViewModel)
                case .hub:
                    hub
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 56)
            }

            customTabBar
        }
        .ignoresSafeArea(.keyboard)
    }

    private var customTabBar: some View {
        HStack(spacing: 0) {
            tabItem(.today, title: "Bugün", symbol: "heart.fill")
            tabItem(.sleep, title: "Uyku", symbol: "moon.zzz.fill")
            tabItem(.load, title: "Yük", symbol: "flame.fill")
            tabItem(.trends, title: "Trend", symbol: "chart.line.uptrend.xyaxis")
            tabItem(.muscle, title: "Kas", symbol: "figure.strengthtraining.traditional")
        }
        .frame(height: 56)
        .background {
            ZenithiumColor.background
                .opacity(0.85)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ZenithiumColor.hairline)
                .frame(height: 1)
        }
    }

    private func tabItem(_ tab: RootTab, title: String, symbol: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(selectedTab == tab ? ZenithiumColor.textPrimary : ZenithiumColor.textTertiary)

                Text(title)
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(selectedTab == tab ? ZenithiumColor.textPrimary : ZenithiumColor.textTertiary)

                // Today sekmesi görsel ağırlığı farklı: aktifken küçük bir spektrum noktası altında belirsin
                if tab == .today {
                    if selectedTab == .today {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [ZenithiumColor.spectrumViolet, ZenithiumColor.spectrumTeal, ZenithiumColor.spectrumAmber],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 4, height: 4)
                    } else {
                        Color.clear.frame(width: 4, height: 4)
                    }
                } else {
                    Color.clear.frame(width: 4, height: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selectedTab == tab ? [.isButton, .isSelected] : .isButton)
    }

    /// Everything that is not part of the daily loop, described rather than just listed.
    private var hub: some View {
        HubView(lens: lens) { destination in
            switch destination {
            case .strain: StrainView(viewModel: strainViewModel)
            case .load: TrainingLoadView(viewModel: trainingLoadViewModel)
            case .muscles: MuscleMapView(viewModel: muscleViewModel)
            case .vitals: VitalsView(viewModel: vitalsViewModel)
            case .endurance: EnduranceView(viewModel: enduranceViewModel)
            case .racePlan: RacePlanView(health: dependencies.health)
            case .strength: StrengthView(viewModel: strengthViewModel)
            case .plan: PlanView(viewModel: planViewModel)
            case .hybrid: HybridView(viewModel: hybridViewModel)
            case .trends: TrendsView(viewModel: trendsViewModel)
            case .bloodwork: BloodworkView(viewModel: bloodworkViewModel)
            case .report: ReportView(viewModel: reportViewModel)
            case .documents: DocumentsView(viewModel: documentsViewModel)
            case .dataTransfer: DataTransferView(service: dependencies.archive)
            case .settings: SettingsView(viewModel: settingsViewModel)
            }
        }
    }

    /// Take whatever an App Intent asked for and go there.
    ///
    /// Applied on foreground rather than at launch: an intent can fire while the app is
    /// already running, and a launch-only check would silently drop it.
    ///
    /// Explicitly on the main actor because it both reads `DeepLink`, which is isolated
    /// there, and writes `selectedTab`. A `View`'s private helpers are nonisolated unless
    /// they say otherwise, and this one is called from inside a `Task` where that would not
    /// have been obvious from the call site.
    @MainActor
    private func applyPendingDeepLink() {
        guard let destination = DeepLink.take() else { return }
        switch destination {
        case .today: selectedTab = .today
        case .sleep: selectedTab = .sleep
        case .journal: selectedTab = .journal
        }
    }

    /// Merceği profilden tazeler. Ayarlar ekranı kapandıktan sonra sekmelerin değişmesi için.
    private func refreshLens() async {
        guard let profile = try? await dependencies.store.profile() else { return }
        lens = profile.trainingLens
    }

    private func loadOnboardingState() async {
        guard hasCompletedOnboarding == nil else { return }
        if ProcessInfo.processInfo.arguments.contains("-mockData") || ProcessInfo.processInfo.arguments.contains("-skipOnboarding") {
            hasCompletedOnboarding = true
            if ProcessInfo.processInfo.arguments.contains("-tabSleep") {
                selectedTab = .sleep
            }
            return
        }
        let profile = try? await dependencies.store.profile()
        // A store that cannot be read is not a reason to skip onboarding — showing it again
        // is recoverable, silently entering the app without a profile is not.
        hasCompletedOnboarding = profile?.hasCompletedOnboarding ?? false
        if let profile {
            lens = profile.trainingLens
            appearance = profile.appearance
        }
    }
}


/// The tabs, as a value an intent can select.
///
/// The second tab is one case rather than three, because which screen sits there is the
/// lens's decision and nothing outside should have to know which one it got.
enum RootTab: Hashable, CaseIterable {
    case today
    case sleep
    case load
    case trends
    case muscle
    case secondary
    case journal
    case hub

    static var allCases: [RootTab] {
        [.today, .sleep, .load, .trends, .muscle]
    }
}
