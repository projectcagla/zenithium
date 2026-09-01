//
//  StrengthSessionLoggerView.swift
//  Zenithium
//
//  The manual strength logger. Spec §5.4: strength sessions require a manual logger with a
//  movement pattern preset, because Zenithium never fabricates strength muscle data from
//  HealthKit (ASSUMPTION MUSCLE-2). RPE is per exercise (ASSUMPTION RPE-1).
//

import SwiftUI

struct StrengthSessionLoggerView: View {

    let viewModel: MuscleMapViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var pattern: MovementPattern = .push
    @State private var isolationMuscle: MuscleGroup = .biceps
    @State private var usesIsolation = false
    @State private var performedAt = Date()
    @State private var note = ""
    @State private var entries: [StrengthEntry] = [
        StrengthEntry(id: UUID(), exerciseName: "", sets: 3, reps: 8, rpe: 7)
    ]

    private var resolvedPattern: MovementPattern {
        usesIsolation ? .isolation(isolationMuscle) : pattern
    }

    private var previewLoad: Double {
        viewModel.previewSessionLoad(for: entries)
    }

    private var canSave: Bool {
        entries.contains(where: \.isValid) && !viewModel.isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                patternSection
                exercisesSection
                loadSection
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
            .navigationTitle("Seans kaydet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        Task {
                            await viewModel.saveSession(
                                pattern: resolvedPattern,
                                performedAt: performedAt,
                                entries: entries,
                                note: note
                            )
                            if viewModel.saveError == nil { dismiss() }
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
        .tint(ZenithiumColor.accent)
    }

    private var patternSection: some View {
        Section {
            Toggle("Tek kas", isOn: $usesIsolation)
                .accessibilityHint("Hareket kalıbı yerine tek bir grubu hedefleyen çalışmayı kaydet")

            if usesIsolation {
                Picker("Kas", selection: $isolationMuscle) {
                    ForEach(MuscleGroup.allCases) { muscle in
                        Text(muscle.displayName).tag(muscle)
                    }
                }
            } else {
                Picker("Kalıp", selection: $pattern) {
                    ForEach(MovementPattern.compoundCases, id: \.storageKey) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Text(pattern.subtitle)
                    .font(ZenithiumFont.caption)
                    .foregroundStyle(ZenithiumColor.textSecondary)
            }
        } header: {
            Text("Hareket")
        } footer: {
            Text("Kardiyoyu saatinden okuyabiliyorum ama bir kuvvet seansında neyi çalıştığını okuyamıyorum. Kalıp, hangi grupları yükleyeceğimi söyler.")
        }
    }

    private var exercisesSection: some View {
        Section {
            ForEach($entries) { $entry in
                StrengthEntryRow(entry: $entry)
            }
            .onDelete { offsets in
                entries.remove(atOffsets: offsets)
                if entries.isEmpty {
                    entries = [StrengthEntry(id: UUID(), exerciseName: "", sets: 3, reps: 8, rpe: 7)]
                }
            }

            Button {
                entries.append(StrengthEntry(id: UUID(), exerciseName: "", sets: 3, reps: 8, rpe: 7))
            } label: {
                Label("Hareket ekle", systemImage: "plus.circle")
            }
        } header: {
            Text("Hareketler")
        }
    }

    private var loadSection: some View {
        Section {
            HStack {
                Text("Seans yükü")
                    .font(ZenithiumFont.label)
                Spacer()
                Text(ZenithiumFormat.score(previewLoad))
                    .font(ZenithiumFont.metricValue)
                    .foregroundStyle(ZenithiumColor.accent)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Seans yükü")
            .accessibilityValue("100 üzerinden \(ZenithiumFormat.score(previewLoad))")

            ProgressView(value: MathSupport.clamp(previewLoad / 100, 0, 1))
                .tint(ZenithiumColor.accent)
                .accessibilityHidden(true)
        } footer: {
            Text("Set × tekrar × RPE, 3'e bölünüp 100 ile sınırlanır — sert bir kardiyo seansının düştüğü ölçekle aynı.")
        }
    }

    private var detailsSection: some View {
        Section {
            DatePicker("Ne zaman", selection: $performedAt, in: ...Date())
            TextField("Not", text: $note, axis: .vertical)
                .lineLimit(1...3)
        } header: {
            Text("Ayrıntılar")
        }
    }
}

/// One exercise row: name, sets, reps, RPE.
private struct StrengthEntryRow: View {

    @Binding var entry: StrengthEntry

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
            TextField("Hareket", text: $entry.exerciseName)
                .font(ZenithiumFont.body)
                .textInputAutocapitalization(.words)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: ZenithiumSpacing.m) { steppers }
                VStack(alignment: .leading, spacing: ZenithiumSpacing.s) { steppers }
            }
        }
        .padding(.vertical, ZenithiumSpacing.xs)
    }

    @ViewBuilder
    private var steppers: some View {
        Stepper(value: $entry.sets, in: StrengthEntry.setsRange) {
            Text("\(entry.sets) sets")
                .font(ZenithiumFont.caption.monospacedDigit())
        }
        .accessibilityLabel("Set")
        .accessibilityValue("\(entry.sets)")

        Stepper(value: $entry.reps, in: StrengthEntry.repsRange) {
            Text("\(entry.reps) reps")
                .font(ZenithiumFont.caption.monospacedDigit())
        }
        .accessibilityLabel("Tekrar")
        .accessibilityValue("\(entry.reps)")

        Stepper(value: $entry.rpe, in: StrengthEntry.rpeRange, step: 0.5) {
            Text("RPE \(ZenithiumFormat.metric(entry.rpe, digits: 1))")
                .font(ZenithiumFont.caption.monospacedDigit())
        }
        .accessibilityLabel("Algılanan zorlanma derecesi")
        .accessibilityValue(ZenithiumFormat.metric(entry.rpe, digits: 1))
    }
}
