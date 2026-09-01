//
//  BloodMarkerEditorView.swift
//  Zenithium
//
//  Entering a lab result. Spec §7 for the fields, §12 for what the screen must not do: it
//  records what the report says and nothing more.
//

import SwiftUI

struct BloodMarkerEditorView: View {

    let viewModel: BloodworkViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var marker: BloodMarkerKind = .apoB
    @State private var customName = ""
    @State private var usesCustomMarker = false
    @State private var valueText = ""
    @State private var unitSymbol = ""
    @State private var drawnAt = Date()
    @State private var note = ""
    @State private var overridesRange = false
    @State private var refMinText = ""
    @State private var refMaxText = ""

    private var resolvedMarker: BloodMarkerKind {
        let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return usesCustomMarker && !trimmed.isEmpty ? .custom(trimmed) : marker
    }

    private var parsedValue: Double? {
        Double(valueText.replacingOccurrences(of: ",", with: "."))
    }

    private var canSave: Bool {
        guard let parsedValue, parsedValue.isFinite else { return false }
        if usesCustomMarker {
            return !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !viewModel.isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                markerSection
                valueSection
                rangeSection
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
            .navigationTitle("Sonuç ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if unitSymbol.isEmpty { unitSymbol = marker.defaultUnitSymbol }
            }
        }
        .tint(ZenithiumColor.accent)
    }

    private var markerSection: some View {
        Section {
            Toggle("Listede olmayan bir şey", isOn: $usesCustomMarker)
                .accessibilityHint("Listede olmayan bir belirteci kaydet")

            if usesCustomMarker {
                TextField("Belirteç adı", text: $customName)
                    .textInputAutocapitalization(.words)
            } else {
                // Fifty markers is too many for a flat wheel, so the picker is sectioned by
                // panel — the same grouping a laboratory report prints them in.
                Picker("Belirteç", selection: $marker) {
                    ForEach(BiomarkerCatalog.byPanel, id: \.panel) { group in
                        Section(group.panel.displayName) {
                            ForEach(group.markers) { definition in
                                Text(definition.displayName)
                                    .tag(BloodMarkerKind.standard(definition.key))
                            }
                        }
                    }
                }
                .pickerStyle(.navigationLink)
                .onChange(of: marker) { _, newValue in
                    unitSymbol = newValue.defaultUnitSymbol
                }
            }
        } header: {
            Text("Belirteç")
        }
    }

    private var valueSection: some View {
        Section {
            HStack {
                TextField("Değer", text: $valueText)
                    .keyboardType(.decimalPad)
                    .font(ZenithiumFont.body.monospacedDigit())
                TextField("Birim", text: $unitSymbol)
                    .frame(maxWidth: 90)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(ZenithiumColor.textSecondary)
            }
            .accessibilityElement(children: .contain)
        } header: {
            Text("Sonuç")
        } footer: {
            Text("Değeri laboratuvarın bildirdiği gibi, onların birimiyle gir.")
        }
    }

    private var rangeSection: some View {
        Section {
            Toggle("Kendi laboratuvarımın aralığını kullan", isOn: $overridesRange)
                .accessibilityHint("Yerleşik referans aralığını raporundakiyle değiştirir")

            if overridesRange {
                HStack {
                    TextField("Alt", text: $refMinText)
                        .keyboardType(.decimalPad)
                    Text("–").foregroundStyle(ZenithiumColor.textTertiary)
                    TextField("Üst", text: $refMaxText)
                        .keyboardType(.decimalPad)
                }
                .font(ZenithiumFont.body.monospacedDigit())
            } else if resolvedMarker.hasBuiltInRanges {
                let range = resolvedMarker.referenceRange
                if let minimum = range.minimum, let maximum = range.maximum {
                    LabeledContent("Referans") {
                        Text("\(ZenithiumFormat.metric(minimum, digits: resolvedMarker.fractionDigits))–\(ZenithiumFormat.metric(maximum, digits: resolvedMarker.fractionDigits)) \(resolvedMarker.defaultUnitSymbol)")
                            .font(ZenithiumFont.callout.monospacedDigit())
                    }
                }
            }
        } header: {
            Text("Referans aralığı")
        } footer: {
            Text(SafetyCopy.bloodworkRangeCaption)
        }
    }

    private var detailsSection: some View {
        Section {
            DatePicker("Alınma tarihi", selection: $drawnAt, in: ...Date(), displayedComponents: .date)
            TextField("Not", text: $note, axis: .vertical)
                .lineLimit(1...3)
        } header: {
            Text("Ayrıntılar")
        }
    }

    private func save() async {
        guard let parsedValue else { return }
        let overrideRange: MarkerRange? = overridesRange
            ? MarkerRange(
                minimum: Double(refMinText.replacingOccurrences(of: ",", with: ".")),
                maximum: Double(refMaxText.replacingOccurrences(of: ",", with: "."))
            )
            : nil

        await viewModel.save(
            marker: resolvedMarker,
            value: parsedValue,
            unitSymbol: unitSymbol,
            referenceRange: overrideRange,
            optimalRange: nil,
            drawnAt: drawnAt,
            note: note
        )
        if viewModel.saveError == nil { dismiss() }
    }
}
