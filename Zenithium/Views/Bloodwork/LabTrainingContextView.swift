import SwiftUI

struct LabTrainingContextView: View {
    let context: [LabTrainingContext]
    let series: [BloodworkViewModel.MarkerSeries]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenithiumSpacing.xl) {
                Text("Aynı döneme bak").font(ZenithiumFont.title)
                Text("Tahlil sonuçların, o sabahki HRV ve önceki 28 günün antrenman yüküyle yan yana. Birlikte değişmeleri, birinin diğerine neden olduğunu göstermez.").zenithiumSecondary()
                ForEach(context) { item in
                    SectionCard(title: item.day.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "tr_TR")))) {
                        VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                            ForEach(series) { marker in
                                if let result = marker.entries.first(where: { Calendar.current.isDate($0.drawnAt, inSameDayAs: item.day) }) {
                                    LabeledContent(marker.marker.displayName, value: "\(ZenithiumFormat.metric(result.value, digits: marker.marker.fractionDigits)) \(result.unitSymbol)")
                                }
                            }
                            Divider()
                            LabeledContent("O sabah HRV", value: item.hrv.map { "\(ZenithiumFormat.metric($0, digits: 1)) ms" } ?? "Kayıt yok")
                            if let baseline = item.hrvBaseline, let z = item.hrvZ {
                                LabeledContent("Önceki gecelerin tabanı", value: "\(ZenithiumFormat.metric(baseline, digits: 1)) ms")
                                Text("\(item.hrvNights) geçerli gece · z = \(ZenithiumFormat.signed(z, digits: 2)). \(z < 0 ? "HRV bu tabanın altında." : "HRV bu tabanın üzerinde veya aynı düzeyde.")").zenithiumCaption()
                            } else { Text("Kişisel karşılaştırma: \(item.hrvNights)/14 geçerli gece. Eksik ölçümler tamamlanmaz.").zenithiumCaption() }
                            LabeledContent("Önceki 28 gün ACWR", value: item.loadRatio.map { ZenithiumFormat.metric($0, digits: 2) } ?? "Hesaplanamadı")
                            Text("Yük verisi: \(item.loadDays)/28 gün. ACWR bir yük oranıdır; yaralanma olasılığını ölçmez.").zenithiumCaption()
                            Text(SafetyCopy.clinicianPrompt).zenithiumCaption()
                        }
                    }
                }
            }.padding(ZenithiumSpacing.l)
        }
        .background(ZenithiumColor.background.ignoresSafeArea())
        .navigationTitle("Eşzamanlılık")
        .navigationBarTitleDisplayMode(.inline)
    }
}
