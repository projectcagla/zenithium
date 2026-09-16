import SwiftUI

struct RecoveryChangeView: View {
    let change: RecoveryChange?
    let note: String?
    var body: some View {
        SectionCard(title: "Dünden bugüne") {
            if let change {
                VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
                    Text("\(ZenithiumFormat.signed(change.delta, digits: 1)) puan").font(ZenithiumFont.sectionTitle)
                    Text("\(ZenithiumFormat.score(change.previousScore)) → \(ZenithiumFormat.score(change.currentScore))")
                        .zenithiumCaption()
                    ForEach(change.contributions) { item in
                        VStack(alignment: .leading, spacing: ZenithiumSpacing.xs) {
                            LabeledContent(item.driver.displayName, value: "\(ZenithiumFormat.signed(item.points, digits: 1)) puan")
                            if item.coverageChanged { Text("Ölçüm kapsamı ve yeniden ağırlıklandırma da bu satıra dahildir.").zenithiumCaption() }
                        }
                    }
                    LabeledContent("Taban ve hesap değişimi", value: "\(ZenithiumFormat.signed(change.baselineAndModelPoints, digits: 1)) puan")
                    Text("Bu satırlar modeldeki farkın hesabıdır; biyolojik nedenleri göstermez. Yuvarlama nedeniyle görünen toplam küçük fark gösterebilir.").zenithiumCaption()
                    DisclosureGroup("Fark nasıl ayrıştırıldı?") {
                        Text("Dünkü ham ölçümler bugünkü tabanla yeniden hesaplanır. Her ölçümün ağırlıklı z-skorundaki değişim, toplam değişimin puan ölçeğine çevrilme katsayısıyla çarpılır. Kalan fark; tabanın, kayıtların veya hesap sürümünün değişimidir. Katkılar toplamı tam puan farkına eşittir.")
                            .zenithiumCaption()
                    }
                }
            } else { Text(note ?? "Karşılaştırma için iki günün ölçümleri gerekiyor.").zenithiumCaption() }
        }
    }
}
