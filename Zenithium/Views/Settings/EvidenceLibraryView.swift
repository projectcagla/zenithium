import SwiftUI

struct EvidenceLibraryView: View {
    var body: some View {
        List {
            Section {
                Text("Toparlanma ve yük, kişisel verilerden hesaplanan modellerdir. Klinik ölçüm veya gelecekteki performansın garantisi değildir. Kaynaklar belirli yöntemleri destekler; uygulamadaki birleşik puanın klinik olarak doğrulandığı anlamına gelmez.")
            }
            Section("Hesabı incele") {
                LabeledContent("Kişisel taban", value: "\(EngineConstants.Baseline.windowDays) günlük pencere")
                LabeledContent("Kalibrasyon", value: "14 geçerli gece")
                Text("Karar yaklaşımı: ihtiyatlı profilde yüksek yük için \(Int(DecisionPreference.cautious.pushThreshold)), gelişim odaklı profilde \(Int(DecisionPreference.progressive.pushThreshold)) toparlanma puanı gerekir. Bunlar ürünün planlama eşikleridir; sakatlanma risk sınırları değildir.")
                NavigationLink("Tüm hesap sabitleri") {
                    ScrollView([.horizontal, .vertical]) {
                        Text(EngineReferenceContent.constants)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                    }
                    .navigationTitle("Hesap sabitleri")
                    .background(ZenithiumColor.background)
                }
            }
            ForEach(EvidenceLibrary.all, id: \.id) { reference in
                Section(reference.id) {
                    Text(reference.citation).font(ZenithiumFont.callout)
                    Text(reference.grade.displayName).font(ZenithiumFont.label)
                    Text(reference.grade.explanation).font(ZenithiumFont.caption)
                    Text("Ne göstermiyor").font(ZenithiumFont.label)
                    Text(reference.doesNotShow).font(ZenithiumFont.caption)
                    if reference.needsVerification {
                        Label("Kaynak künyesi doğrulama bekliyor", systemImage: "info.circle").font(ZenithiumFont.caption)
                    }
                    if let doi = reference.doi, let url = URL(string: "https://doi.org/\(doi)") {
                        Link("Yayını aç", destination: url)
                    }
                }
            }
        }
        .navigationTitle("Hesaplar ve kanıtlar")
        .scrollContentBackground(.hidden)
        .background(ZenithiumColor.background)
    }
}
