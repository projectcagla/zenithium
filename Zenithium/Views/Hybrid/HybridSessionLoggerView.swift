//
//  HybridSessionLoggerView.swift
//  Zenithium
//
//  Hibrit seans kaydedici.
//
//  Tasarım kararı: kullanıcı sekiz istasyon × üç alan doldurmaz. Bir "tam yarış" seçtiğinde
//  sekiz tur hazır gelir ve yalnızca süreleri girer. Sürtünmeyi buradan düşürmezsek kimse
//  ikinci seansı kaydetmez.
//

import SwiftUI

struct HybridSessionLoggerView: View {

    let viewModel: HybridViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var kind: HybridSessionKind = .fullRace
    @State private var performedAt = Date()
    @State private var note = ""
    @State private var rounds: [RoundEntry] = RoundEntry.template(for: .fullRace)
    @State private var runDistanceMeters: Double = 1000

    /// Bir tur: koşu süresi, geçiş süresi, istasyon süresi.
    struct RoundEntry: Identifiable, Equatable {
        let id = UUID()
        let index: Int
        let station: HyroxStation
        var runSeconds: Double = 0
        var transitionSeconds: Double = 0
        var stationSeconds: Double = 0

        static func template(for kind: HybridSessionKind) -> [RoundEntry] {
            let stations = HyroxStation.allCases.sorted { $0.order < $1.order }
            switch kind {
            case .fullRace:
                return stations.enumerated().map { RoundEntry(index: $0.offset + 1, station: $0.element) }
            case .halfSimulation:
                return stations.prefix(4).enumerated().map { RoundEntry(index: $0.offset + 1, station: $0.element) }
            case .stationBlock:
                return stations.prefix(4).enumerated().map { RoundEntry(index: $0.offset + 1, station: $0.element) }
            case .compromisedRunBlock:
                return stations.prefix(3).enumerated().map { RoundEntry(index: $0.offset + 1, station: $0.element) }
            }
        }
    }

    private var hasAnyTime: Bool {
        rounds.contains { $0.runSeconds > 0 || $0.stationSeconds > 0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                kindSection
                roundsSection
                detailsSection
                if let error = viewModel.saveError {
                    Section {
                        Text(error.errorDescription ?? "Kaydedilemedi.")
                            .font(ZenithiumFont.callout)
                            .foregroundStyle(ZenithiumColor.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ZenithiumColor.background.ignoresSafeArea())
            .navigationTitle("Seans ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { Task { await save() } }
                        .disabled(!hasAnyTime || viewModel.isSaving)
                }
            }
        }
        .tint(ZenithiumColor.accent)
    }

    private var kindSection: some View {
        Section {
            Picker("Seans türü", selection: $kind) {
                ForEach(HybridSessionKind.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .onChange(of: kind) { _, newValue in
                rounds = RoundEntry.template(for: newValue)
            }
            Text(kind.subtitle)
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textSecondary)

            if kind != .stationBlock {
                HStack {
                    Text("Koşu mesafesi")
                    Spacer()
                    Text("\(Int(runDistanceMeters)) m")
                        .font(ZenithiumFont.dataValue)
                        .foregroundStyle(ZenithiumColor.textSecondary)
                }
                Slider(value: $runDistanceMeters, in: 200...2000, step: 100)
                    .accessibilityLabel("Tur başına koşu mesafesi")
                    .accessibilityValue("\(Int(runDistanceMeters)) metre")
            }
        } header: {
            Text("Tür")
        }
    }

    private var roundsSection: some View {
        Section {
            ForEach($rounds) { $round in
                RoundRow(round: $round, includesRun: kind != .stationBlock)
            }
        } header: {
            Text("Turlar")
        } footer: {
            Text("Boş bıraktığın alanlar hesaba katılmaz. Yalnızca koşu sürelerini girsen bile kompanse koşu cezası çıkar.")
        }
    }

    private var detailsSection: some View {
        Section {
            DatePicker("Ne zaman", selection: $performedAt, in: ...Date())
            TextField("Not", text: $note, axis: .vertical)
                .lineLimit(1...3)
        } header: {
            Text("Detaylar")
        }
    }

    /// Girilen süreleri zaman çizgisine dizer.
    ///
    /// Motorun gerçek `DateInterval`'lara ihtiyacı var, ama kullanıcı süre giriyor. Turlar
    /// başlangıçtan itibaren arka arkaya yerleştiriliyor — sıralama ve süreler doğru olduğu
    /// sürece mutlak saatlerin ne olduğu analizi etkilemiyor.
    private func buildSegments() -> [HybridSegment] {
        var segments: [HybridSegment] = []
        var cursor = performedAt

        for round in rounds {
            if kind != .stationBlock, round.runSeconds > 0 {
                let end = cursor.addingTimeInterval(round.runSeconds)
                segments.append(
                    HybridSegment(
                        id: UUID(),
                        kind: .run(distanceMeters: runDistanceMeters, roundIndex: round.index),
                        interval: DateInterval(start: cursor, end: end),
                        averageHeartRate: nil,
                        peakHeartRate: nil
                    )
                )
                cursor = end
            }
            if round.transitionSeconds > 0 {
                let end = cursor.addingTimeInterval(round.transitionSeconds)
                segments.append(
                    HybridSegment(
                        id: UUID(),
                        kind: .transition,
                        interval: DateInterval(start: cursor, end: end),
                        averageHeartRate: nil,
                        peakHeartRate: nil
                    )
                )
                cursor = end
            }
            if round.stationSeconds > 0 {
                let end = cursor.addingTimeInterval(round.stationSeconds)
                segments.append(
                    HybridSegment(
                        id: UUID(),
                        kind: .station(round.station),
                        interval: DateInterval(start: cursor, end: end),
                        averageHeartRate: nil,
                        peakHeartRate: nil
                    )
                )
                cursor = end
            }
        }
        return segments
    }

    private func save() async {
        await viewModel.save(
            kind: kind,
            performedAt: performedAt,
            segments: buildSegments(),
            note: note
        )
        if viewModel.saveError == nil { dismiss() }
    }
}

/// Bir turun üç süresi.
private struct RoundRow: View {

    @Binding var round: HybridSessionLoggerView.RoundEntry
    let includesRun: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
            HStack(spacing: ZenithiumSpacing.s) {
                Text("\(round.index)")
                    .font(ZenithiumFont.dataValue)
                    .foregroundStyle(ZenithiumColor.textTertiary)
                    .frame(width: 18, alignment: .leading)
                Image(systemName: round.station.symbolName)
                    .imageScale(.small)
                    .foregroundStyle(ZenithiumColor.accent)
                    .accessibilityHidden(true)
                Text(round.station.displayName)
                    .font(ZenithiumFont.label)
                Spacer(minLength: 0)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: ZenithiumSpacing.m) { fields }
                VStack(alignment: .leading, spacing: ZenithiumSpacing.s) { fields }
            }
        }
        .padding(.vertical, ZenithiumSpacing.xs)
    }

    @ViewBuilder
    private var fields: some View {
        if includesRun {
            DurationField(title: "Koşu", seconds: $round.runSeconds)
        }
        DurationField(title: "Geçiş", seconds: $round.transitionSeconds)
        DurationField(title: "İstasyon", seconds: $round.stationSeconds)
    }
}

/// Dakika:saniye girişi.
///
/// Saniye olarak tek alan istemek, kullanıcıyı 4:32'yi 272'ye çevirmeye zorlar. İki alan
/// daha fazla dokunuş ama sıfır zihinsel iş.
private struct DurationField: View {

    let title: String
    @Binding var seconds: Double

    @State private var minutesText = ""
    @State private var secondsText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
            Text(title)
                .font(ZenithiumFont.caption)
                .foregroundStyle(ZenithiumColor.textTertiary)
            HStack(spacing: ZenithiumSpacing.xs) {
                TextField("0", text: $minutesText)
                    .keyboardType(.numberPad)
                    .frame(width: 34)
                    .multilineTextAlignment(.trailing)
                Text(":")
                    .foregroundStyle(ZenithiumColor.textTertiary)
                TextField("00", text: $secondsText)
                    .keyboardType(.numberPad)
                    .frame(width: 34)
            }
            .font(ZenithiumFont.dataValue)
            .onChange(of: minutesText) { _, _ in recompute() }
            .onChange(of: secondsText) { _, _ in recompute() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func recompute() {
        let minutes = Double(minutesText) ?? 0
        let secs = Double(secondsText) ?? 0
        seconds = minutes * 60 + secs
    }
}
