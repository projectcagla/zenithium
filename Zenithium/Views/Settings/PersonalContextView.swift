import SwiftUI

struct PersonalContextView: View {
    @State var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [PersonalContextEntry] = []
    @State private var initialized = false

    private func binding<Value>(_ kind: PersonalContextKind, get: @escaping (PersonalContextEntry) -> Value,
                                set: @escaping (inout PersonalContextEntry, Value) -> Void, fallback: Value) -> Binding<Value> {
        Binding(get: { entries.first(where: { $0.kind == kind }).map(get) ?? fallback }, set: { value in
            guard let index = entries.firstIndex(where: { $0.kind == kind }) else { return }
            set(&entries[index], value)
        })
    }

    var body: some View {
        Form {
            Section {
                Text("Geçici koşullarını kendin kaydet. Etkin kayıtlar günlük antrenman önerisini sınırlar; toparlanma puanını veya ölçümlerini değiştirmez. Hastalık kaydı yoğun antrenman önerisini durdurur. Diğer koşullar yük artışını sınırlar.")
            }
            ForEach(PersonalContextKind.allCases) { kind in
                Section {
                    Toggle(kind.title, isOn: Binding(get: { entries.contains { $0.kind == kind } }, set: { enabled in
                        if enabled {
                            let now = Date()
                            entries.append(PersonalContextEntry(kind: kind,
                                through: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now,
                                note: "", startedAt: now))
                        } else { entries.removeAll { $0.kind == kind } }
                    }))
                    if entries.contains(where: { $0.kind == kind }) {
                        DatePicker("Başlangıç", selection: binding(kind, get: { $0.startedAt ?? Date() }, set: { $0.startedAt = $1 }, fallback: Date()))
                        DatePicker("Bitiş", selection: binding(kind, get: { $0.through }, set: { $0.through = $1 }, fallback: Date()))
                        TextField("İsteğe bağlı not", text: binding(kind, get: { $0.note }, set: { $0.note = $1 }, fallback: ""), axis: .vertical)
                            .lineLimit(2...5)
                    }
                }
            }
            Section {
                Text("Notların yalnızca cihazında tutulur ve arşivine dahildir. Not metni hesaplanmaz; yalnızca seçtiğin koşul ve tarih aralığı kullanılır. Bu kayıtlar tanı veya tıbbi uygunluk değerlendirmesi değildir.")
                if let error = viewModel.saveError { Text(error.localizedDescription).foregroundStyle(ZenithiumColor.red) }
                Button("Bağlamı kaydet") {
                    Task {
                        await viewModel.setPreferences { $0.contexts = entries }
                        if viewModel.saveError == nil { dismiss() }
                    }
                }
            }
        }
        .navigationTitle("Benim bağlamım")
        .tint(ZenithiumColor.accent)
        .disabled(viewModel.isSaving)
        .task {
            guard !initialized else { return }
            entries = viewModel.state.value?.preferences.contexts ?? []
            initialized = true
        }
    }
}
