import Foundation

/// Conservative rejection is intentional: rejected prose falls back to engine-owned text.
enum NarrationGuard {
    static func containsNoQuantity(_ text: String) -> Bool {
        guard !text.contains(where: { $0.isNumber }), !text.contains("%") else { return false }
        let words = text.lowercased(with: Locale(identifier: "tr_TR"))
            .components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        let quantities = ["sıfır", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz", "on", "yirmi", "otuz", "kırk", "elli", "altmış", "yetmiş", "seksen", "doksan", "yüz", "bin", "milyon", "yarım", "çeyrek", "kat", "yüzde", "saat", "dakika", "puan", "kilogram"]
        return !words.contains { word in quantities.contains { word.hasPrefix($0) } }
    }
}
