//
//  PlanView.swift
//  Zenithium
//
//  Goal events and the phase leading to them. Faz 20.
//
//  Deliberately not a programme builder. Zenithium names the phase and what it is for, and
//  lets the prescription engine bias itself; writing somebody's week is a coach's job and an
//  app that pretends otherwise is guessing at a life it cannot see.
//

import SwiftUI

struct PlanView: View {

    @State var viewModel: PlanViewModel
    @State private var isAddingEvent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                ViewStateContainer(
                    state: viewModel.state,
                    loadingLabel: "Plan okunuyor",
                    retry: { await viewModel.load() },
                    requestAccess: nil
                ) { content in
                    loadedBody(content)
                }
                .padding(.horizontal, ZenithiumSpacing.l)
                .padding(.bottom, ZenithiumSpacing.xxl)
                .padding(.top, ZenithiumSpacing.s)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(ZenithiumColor.background.ignoresSafeArea())
            .navigationTitle("Plan")
            .toolbarBackground(ZenithiumColor.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isAddingEvent = true } label: {
                        Label("Etkinlik ekle", systemImage: "plus")
                    }
                    .accessibilityLabel("Etkinlik ekle")
                }
            }
            .sheet(isPresented: $isAddingEvent) {
                GoalEventEditorView(viewModel: viewModel)
            }
        }
        .zenithiumBackground(tint: ZenithiumColor.spectrumAmber, intensity: 0.3)
        .task { await viewModel.onAppear() }
    }

    @ViewBuilder
    private func loadedBody(_ content: PlanViewModel.Content) -> some View {
        VStack(spacing: ZenithiumSpacing.l) {
            if let position = content.position {
                positionCard(position, taper: content.taperSummary, projection: content.taperProjection)
                phaseTimeline(position)
            } else {
                emptyCard
            }
            if !content.events.isEmpty {
                eventsCard(content.events)
            }
        }
    }

    private var emptyCard: some View {
        SectionCard(title: "Henüz hedef yok") {
            Text("Bir yarış, Hyrox ya da kuvvet testi ekle; bugünün önerisi o tarihe göre şekillensin.")
                .font(ZenithiumFont.callout)
                .foregroundStyle(ZenithiumColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func positionCard(
        _ position: PlanPosition,
        taper: String?,
        projection: FitnessFatigue?
    ) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                HStack(spacing: ZenithiumSpacing.m) {
                    Image(systemName: position.event.kind.symbolName)
                        .font(.system(size: 18))
                        .foregroundStyle(ZenithiumColor.spectrumAmber)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                        Text(position.event.name)
                            .font(ZenithiumFont.sectionTitle)
                            .foregroundStyle(ZenithiumColor.textPrimary)
                        Text(position.event.date.formatted(date: .long, time: .omitted))
                            .font(ZenithiumFont.caption)
                            .foregroundStyle(ZenithiumColor.textTertiary)
                    }
                    Spacer(minLength: 0)
                    if !position.isPast {
                        VStack(alignment: .trailing, spacing: ZenithiumSpacing.xxs) {
                            Text("\(position.daysRemaining)")
                                .font(ZenithiumFont.arcValue(size: 28))
                                .foregroundStyle(ZenithiumColor.textPrimary)
                            Text("gün")
                                .font(ZenithiumFont.caption2)
                                .foregroundStyle(ZenithiumColor.textTertiary)
                        }
                    }
                }

                Text(PlanEngine.summary(for: position))
                    .font(ZenithiumFont.callout)
                    .foregroundStyle(ZenithiumColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let taper {
                    Text(taper)
                        .font(ZenithiumFont.footnote)
                        .foregroundStyle(ZenithiumColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The phases as a strip, with the current one marked.
    private func phaseTimeline(_ position: PlanPosition) -> some View {
        let phases: [PlanPhase] = [.base, .build, .sharpen, .taper, .event]
        return SectionCard(title: "Fazlar") {
            VStack(spacing: ZenithiumSpacing.none) {
                ForEach(phases, id: \.self) { phase in
                    HStack(alignment: .top, spacing: ZenithiumSpacing.m) {
                        Circle()
                            .fill(phase == position.phase ? ZenithiumColor.accent : ZenithiumColor.hairline)
                            .frame(width: 9, height: 9)
                            .padding(.top, ZenithiumSpacing.xs)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                            Text(phase.displayName)
                                .font(ZenithiumFont.headline)
                                .foregroundStyle(
                                    phase == position.phase
                                        ? ZenithiumColor.textPrimary
                                        : ZenithiumColor.textSecondary
                                )
                            Text(phase.purpose)
                                .font(ZenithiumFont.caption)
                                .foregroundStyle(ZenithiumColor.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, ZenithiumSpacing.s)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(phase == position.phase ? .isSelected : [])
                }
            }
        }
    }

    private func eventsCard(_ events: [GoalEvent]) -> some View {
        SectionCard(title: "Etkinlikler") {
            VStack(spacing: ZenithiumSpacing.none) {
                ForEach(events) { event in
                    HStack {
                        Image(systemName: event.kind.symbolName)
                            .font(.system(size: 12))
                            .foregroundStyle(ZenithiumColor.textTertiary)
                            .frame(width: 18)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: ZenithiumSpacing.xxs) {
                            Text(event.name)
                                .font(ZenithiumFont.callout)
                                .foregroundStyle(ZenithiumColor.textPrimary)
                            Text(event.date.formatted(date: .abbreviated, time: .omitted))
                                .font(ZenithiumFont.caption)
                                .foregroundStyle(ZenithiumColor.textTertiary)
                        }
                        Spacer()
                        Button {
                            Task { await viewModel.delete(id: event.id) }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(ZenithiumColor.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(event.name) etkinliğini sil")
                    }
                    .padding(.vertical, ZenithiumSpacing.s)

                    if event.id != events.last?.id {
                        Divider().overlay(ZenithiumColor.hairlineSoft)
                    }
                }
            }
        }
    }
}

/// The add-event sheet.
private struct GoalEventEditorView: View {

    let viewModel: PlanViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var kind: GoalEventKind = .race
    @State private var name = ""
    @State private var date = Date().addingTimeInterval(60 * 86_400)
    @State private var usesPlanStart = false
    @State private var planStart = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tür", selection: $kind) {
                        ForEach(GoalEventKind.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    TextField("Ad", text: $name)
                        .textInputAutocapitalization(.words)
                    DatePicker("Tarih", selection: $date, displayedComponents: .date)
                } header: {
                    Text("Etkinlik")
                } footer: {
                    Text("Tapering süresi türe göre değişir: yarış 14 gün, Hyrox 10, kuvvet testi 5.")
                }

                Section {
                    Toggle("Hazırlığın başlangıcını gir", isOn: $usesPlanStart)
                    if usesPlanStart {
                        DatePicker("Başlangıç", selection: $planStart, in: ...date, displayedComponents: .date)
                    }
                } footer: {
                    Text("Girmezsen 12 haftalık bir hazırlık varsayarım — dört fazı da tutacak kadar uzun, altı hafta kala hâlâ baz fazında olduğunu söylemeyecek kadar kısa.")
                }

                if let error = viewModel.saveError {
                    Section {
                        Text(error.errorDescription ?? "Kaydedilemedi.")
                            .font(ZenithiumFont.caption)
                            .foregroundStyle(ZenithiumColor.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ZenithiumColor.background.ignoresSafeArea())
            .navigationTitle("Etkinlik ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        Task {
                            await viewModel.save(
                                kind: kind,
                                name: name,
                                date: date,
                                planStart: usesPlanStart ? planStart : nil
                            )
                            if viewModel.saveError == nil { dismiss() }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSaving)
                }
            }
        }
        .tint(ZenithiumColor.accent)
    }
}
