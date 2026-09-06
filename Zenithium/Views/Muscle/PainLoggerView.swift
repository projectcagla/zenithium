//
//  PainLoggerView.swift
//  Zenithium
//
//  Logging discomfort on a body region. Faz 32.
//
//  Reached by long-pressing a region on the body map, which is the one place in the app
//  where "this bit" is already selected. The sheet asks four short questions and gets out of
//  the way; a long form is how a pain log stops being kept.
//
//  §12 is enforced in the sheet itself: past a severity of seven the training context is
//  replaced by the clinician prompt, before anything is saved, so the user sees the app's
//  own limit at the moment it becomes relevant.
//

import SwiftUI

struct PainLoggerView: View {

    let muscle: MuscleGroup
    let onSave: (PainEntry) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var severity = 3.0
    @State private var laterality: BodyLaterality = .left
    @State private var quality: PainQuality = .ache
    @State private var loggedAt = Date()
    @State private var note = ""
    @State private var isSaving = false

    private var crossesThreshold: Bool {
        Int(severity.rounded()) >= PainEntry.clinicianThreshold
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: ZenithiumSpacing.s) {
                        HStack {
                            Text("Şiddet")
                                .foregroundStyle(ZenithiumColor.textPrimary)
                            Spacer()
                            Text("\(Int(severity.rounded()))/10")
                                .font(ZenithiumFont.body.monospacedDigit())
                                .foregroundStyle(crossesThreshold ? ZenithiumColor.yellow : ZenithiumColor.textSecondary)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                            ForEach(1...10, id: \.self) { level in
                                Button { severity = Double(level) } label: {
                                    Text("\(level)")
                                        .font(ZenithiumFont.dataValue)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(Int(severity) == level ? ZenithiumColor.accent.opacity(0.2) : ZenithiumColor.surfaceElevated))
                                        .foregroundStyle(Int(severity) == level ? ZenithiumColor.accent : ZenithiumColor.textSecondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Ağrı şiddeti \(level) / 10")
                                .accessibilityAddTraits(Int(severity) == level ? .isSelected : [])
                            }
                        }
                        Button("Ağrı yok · 0") { severity = 0 }
                            .font(ZenithiumFont.caption)
                            .frame(minHeight: 44)
                            .buttonStyle(.plain)

                    }
                } header: {
                    Text(muscle.displayName)
                } footer: {
                    // Shown before saving, not after: the user should see where the app's
                    // usefulness ends at the moment it becomes relevant to them.
                    Text(crossesThreshold
                         ? "7 ve üzeri şiddet için Zenithium yük bağlamı sunmaz. Bunun ne olduğunu söyleyemem — bir hekime göster."
                         : "Kendi ölçeğinde, kendi hissettiğin şiddet. Zenithium bunu yalnızca kaydeder ve antrenman yükünle karşılaştırır.")
                }

                Section("Ayrıntı") {
                    Picker("Taraf", selection: $laterality) {
                        ForEach(BodyLaterality.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    Picker("Nasıl", selection: $quality) {
                        ForEach(PainQuality.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    DatePicker("Ne zaman", selection: $loggedAt, in: ...Date())
                    TextField("Not", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .scrollContentBackground(.hidden)
            .background(ZenithiumColor.background.ignoresSafeArea())
            .navigationTitle("Ağrı kaydı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        isSaving = true
                        Task {
                            await onSave(
                                PainEntry(
                                    muscle: muscle,
                                    laterality: laterality,
                                    severity: Int(severity.rounded()),
                                    quality: quality,
                                    loggedAt: loggedAt,
                                    note: note.trimmingCharacters(in: .whitespaces)
                                )
                            )
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .tint(ZenithiumColor.accent)
    }
}
