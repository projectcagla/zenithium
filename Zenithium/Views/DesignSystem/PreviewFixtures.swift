//
//  PreviewFixtures.swift
//  Zenithium
//
//  Deterministik önizleme ve görsel gerileme testleri için örnek veri sağlayıcı.
//  MockHealthProvider ve DailyRecalculationCoordinator üzerinden gerçek veriler üretilir.
//

import SwiftUI
import SwiftData

@MainActor
enum PreviewState: String, CaseIterable, Sendable {
    case dolu
    case kalibrasyon
    case veriyok
}

@MainActor
enum PreviewScreen: String, CaseIterable, Sendable {
    case bugun
    case uyku
    case yuk
    case trendler
    case kas
    case tahlil
    case neden

    var displayName: String {
        switch self {
        case .bugun: return "Bugün"
        case .uyku: return "Uyku"
        case .yuk: return "Yük"
        case .trendler: return "Trendler"
        case .kas: return "Kas"
        case .tahlil: return "Tahlil"
        case .neden: return "Neden"
        }
    }
}

@MainActor
final class PreviewFixtures {

    static let shared = PreviewFixtures()

    private var doluDependencies: AppDependencies?
    private var kalibrasyonDependencies: AppDependencies?
    private var veriyokDependencies: AppDependencies?

    private init() {}

    // MARK: - Dependencies Hazırlayıcıları

    func dependencies(for state: PreviewState) async throws -> AppDependencies {
        switch state {
        case .dolu:
            if let existing = doluDependencies { return existing }
            let deps = try AppDependencies.preview(configuration: .complete)
            _ = try await deps.coordinator.recalculate(now: Date())
            try await seedBloodMarkers(into: deps.store)
            doluDependencies = deps
            return deps

        case .kalibrasyon:
            if let existing = kalibrasyonDependencies { return existing }
            let config = MockHealthProvider.Configuration(
                daysOfHistory: 3,
                recordsWristTemperature: true,
                recordsSleepStages: true,
                missingNightFraction: 0.0,
                authorizationState: .authorized
            )
            let deps = try AppDependencies.preview(configuration: config)
            _ = try? await deps.coordinator.recalculate(now: Date())
            kalibrasyonDependencies = deps
            return deps

        case .veriyok:
            if let existing = veriyokDependencies { return existing }
            let config = MockHealthProvider.Configuration(
                daysOfHistory: 0,
                recordsWristTemperature: false,
                recordsSleepStages: false,
                missingNightFraction: 1.0,
                authorizationState: .authorized
            )
            let deps = try AppDependencies.preview(configuration: config)
            _ = try? await deps.coordinator.recalculate(now: Date())
            veriyokDependencies = deps
            return deps
        }
    }

    private func seedBloodMarkers(into store: ZenithiumStore) async throws {
        let now = Date()
        try await store.saveBloodMarker(
            id: UUID(),
            marker: .ferritin,
            value: 125.0,
            unitSymbol: "ng/mL",
            referenceRange: MarkerRange(minimum: 30, maximum: 300),
            optimalRange: MarkerRange(minimum: 50, maximum: 150),
            drawnAt: now.addingTimeInterval(-86400 * 14),
            note: "Rutin kontrol"
        )
        try await store.saveBloodMarker(
            id: UUID(),
            marker: .highSensitivityCRP,
            value: 0.6,
            unitSymbol: "mg/L",
            referenceRange: MarkerRange(minimum: 0.0, maximum: 3.0),
            optimalRange: MarkerRange(minimum: 0.0, maximum: 1.0),
            drawnAt: now.addingTimeInterval(-86400 * 14),
            note: "Enflamasyon takibi"
        )
        try await store.saveBloodMarker(
            id: UUID(),
            marker: .vitaminD,
            value: 48.0,
            unitSymbol: "ng/mL",
            referenceRange: MarkerRange(minimum: 30, maximum: 100),
            optimalRange: MarkerRange(minimum: 40, maximum: 70),
            drawnAt: now.addingTimeInterval(-86400 * 14),
            note: "Kış sonu kontrolü"
        )
        try await store.saveBloodMarker(
            id: UUID(),
            marker: .fastingGlucose,
            value: 92.0,
            unitSymbol: "mg/dL",
            referenceRange: MarkerRange(minimum: 70, maximum: 99),
            optimalRange: MarkerRange(minimum: 75, maximum: 90),
            drawnAt: now.addingTimeInterval(-86400 * 14),
            note: "Açlık glukozu"
        )
    }

    // MARK: - Ekran ViewModel Fabrikaları

    func makeTodayViewModel(state: PreviewState) async -> TodayViewModel {
        guard let deps = try? await dependencies(for: state) else {
            return fallbackTodayViewModel()
        }
        let vm = TodayViewModel(
            coordinator: deps.coordinator,
            health: deps.health,
            journal: deps.store,
            bloodMarkers: deps.store,
            records: deps.dayRecords,
            sessions: deps.store,
            cycleSource: deps.health,
            goals: deps.store,
            workoutSource: deps.health
        )
        await vm.refresh()
        return vm
    }

    func makeSleepViewModel(state: PreviewState) async -> SleepViewModel {
        guard let deps = try? await dependencies(for: state) else {
            return fallbackSleepViewModel()
        }
        let vm = SleepViewModel(
            coordinator: deps.coordinator,
            health: deps.health,
            records: deps.dayRecords
        )
        await vm.refresh()
        return vm
    }

    func makeTrainingLoadViewModel(state: PreviewState) async -> TrainingLoadViewModel {
        guard let deps = try? await dependencies(for: state) else {
            return fallbackTrainingLoadViewModel()
        }
        let vm = TrainingLoadViewModel(records: deps.dayRecords)
        await vm.load()
        return vm
    }

    func makeTrendsViewModel(state: PreviewState) async -> TrendsViewModel {
        guard let deps = try? await dependencies(for: state) else {
            return fallbackTrendsViewModel()
        }
        let vm = TrendsViewModel(repository: deps.dayRecords)
        await vm.load()
        return vm
    }

    func makeMuscleMapViewModel(state: PreviewState) async -> MuscleMapViewModel {
        guard let deps = try? await dependencies(for: state) else {
            return fallbackMuscleMapViewModel()
        }
        let vm = MuscleMapViewModel(
            coordinator: deps.coordinator,
            repository: deps.store,
            painRepository: deps.store,
            records: deps.dayRecords
        )
        await vm.refresh()
        return vm
    }

    func makeBloodworkViewModel(state: PreviewState) async -> BloodworkViewModel {
        guard let deps = try? await dependencies(for: state) else {
            return fallbackBloodworkViewModel()
        }
        let vm = BloodworkViewModel(repository: deps.store, profile: deps.store)
        await vm.load()
        return vm
    }

    func makeReasonView(state: PreviewState) -> ReasonView {
        switch state {
        case .dolu:
            return ReasonView(state: .loaded(Self.sampleRecommendation), embedInNavigation: false)
        case .kalibrasyon:
            return ReasonView(state: .calibrating(progress: 0.35, daysCollected: 5, daysRequired: 14), embedInNavigation: false)
        case .veriyok:
            return ReasonView(state: .noData(reason: .notEnoughHistory(daysAvailable: 0, daysRequired: 14)), embedInNavigation: false)
        }
    }

    func makeView(screen: PreviewScreen, state: PreviewState) async -> AnyView {
        switch screen {
        case .bugun:
            let vm = await makeTodayViewModel(state: state)
            return AnyView(TodayView(viewModel: vm, embedInNavigation: false))
        case .uyku:
            let vm = await makeSleepViewModel(state: state)
            return AnyView(SleepView(viewModel: vm, embedInNavigation: false))
        case .yuk:
            let vm = await makeTrainingLoadViewModel(state: state)
            return AnyView(TrainingLoadView(viewModel: vm, embedInNavigation: false))
        case .trendler:
            let vm = await makeTrendsViewModel(state: state)
            return AnyView(TrendsView(viewModel: vm, embedInNavigation: false))
        case .kas:
            let vm = await makeMuscleMapViewModel(state: state)
            return AnyView(MuscleMapView(viewModel: vm, embedInNavigation: false))
        case .tahlil:
            let vm = await makeBloodworkViewModel(state: state)
            return AnyView(BloodworkView(viewModel: vm, embedInNavigation: false))
        case .neden:
            return AnyView(makeReasonView(state: state))
        }
    }

    // MARK: - Fallback / Güvenlik Fabrikaları

    private func fallbackTodayViewModel() -> TodayViewModel {
        guard let container = try? ModelContainerFactory.makeInMemory() else {
            fatalError("InMemory ModelContainer oluşturulamadı")
        }
        let store = ZenithiumStore(modelContainer: container)
        let health = MockHealthProvider(configuration: .default)
        return TodayViewModel(
            coordinator: DailyRecalculationCoordinator(health: health, store: store),
            health: health
        )
    }

    private func fallbackSleepViewModel() -> SleepViewModel {
        guard let container = try? ModelContainerFactory.makeInMemory() else {
            fatalError("InMemory ModelContainer oluşturulamadı")
        }
        let store = ZenithiumStore(modelContainer: container)
        let health = MockHealthProvider(configuration: .default)
        return SleepViewModel(
            coordinator: DailyRecalculationCoordinator(health: health, store: store),
            health: health
        )
    }

    private func fallbackTrainingLoadViewModel() -> TrainingLoadViewModel {
        guard let container = try? ModelContainerFactory.makeInMemory() else {
            fatalError("InMemory ModelContainer oluşturulamadı")
        }
        let store = ZenithiumStore(modelContainer: container)
        return TrainingLoadViewModel(records: store)
    }

    private func fallbackTrendsViewModel() -> TrendsViewModel {
        guard let container = try? ModelContainerFactory.makeInMemory() else {
            fatalError("InMemory ModelContainer oluşturulamadı")
        }
        let store = ZenithiumStore(modelContainer: container)
        return TrendsViewModel(repository: store)
    }

    private func fallbackMuscleMapViewModel() -> MuscleMapViewModel {
        guard let container = try? ModelContainerFactory.makeInMemory() else {
            fatalError("InMemory ModelContainer oluşturulamadı")
        }
        let store = ZenithiumStore(modelContainer: container)
        let health = MockHealthProvider(configuration: .default)
        return MuscleMapViewModel(
            coordinator: DailyRecalculationCoordinator(health: health, store: store),
            repository: store
        )
    }

    private func fallbackBloodworkViewModel() -> BloodworkViewModel {
        guard let container = try? ModelContainerFactory.makeInMemory() else {
            fatalError("InMemory ModelContainer oluşturulamadı")
        }
        let store = ZenithiumStore(modelContainer: container)
        return BloodworkViewModel(repository: store)
    }

    // MARK: - Örnek Öneri Verisi

    static let sampleRecommendation = Recommendation(
        id: "rec_training_strain_sweetspot",
        domain: .training,
        strength: .recommendation,
        headline: "Bugün 12,4 zorlanma tavanı hedeflenebilir",
        body: "Toparlanma skorun %78 ve son 14 günlük akut:kronik iş yükü oranın 1,08 ile dengeli aralıkta. Kardiyovasküler kapasiteyi korumak için 45-60 dakikalık Bölge 2 antrenmanı uygundur.",
        confidence: ConfidenceScore(value: 0.84),
        evidence: [
            EvidenceNode(sourceCategory: "Toparlanma", summary: "HRV taban ortalamasının +0,6σ üzerinde (54 ms).", timestamp: Date()),
            EvidenceNode(sourceCategory: "Uyku", summary: "Dün gece 7 sa 22 dk uyku ile uyku ihtiyacının %92'si karşılandı.", timestamp: Date()),
            EvidenceNode(sourceCategory: "Yük", summary: "Akut/kronik oran 1,08 (tatlı nokta aralığı).", timestamp: Date())
        ],
        referenceIDs: ["GABBETT-2016", "PLEWS-2013"],
        limitations: [
            ScientificLimitation(code: "LIT-OBS", explanation: "Gözlemsel kohort çalışması; bireysel toparlanma hızı antrenman geçmişine göre değişkenlik gösterebilir.", isBlocking: false)
        ],
        wouldChangeIf: [
            "İstirahat nabzı tabandan >1,5σ saparsa",
            "Öznel kas ağrısı >6/10 düzeyine çıkarsa",
            "Akut/kronik yük oranı 1,30 seviyesini aşarsa"
        ],
        disclaimerTier: .training,
        populationNote: "Elit ve rekreasyonel dayanıklılık sporcuları kohortuna dayanmaktadır."
    )
}
