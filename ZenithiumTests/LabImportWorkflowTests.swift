import Foundation
import Testing
@testable import Zenithium

@Suite("Tahlil kayıt güvenliği")
@MainActor
struct LabImportWorkflowTests {
    private func draft() -> LabReportDraft {
        LabReportParser.parse(LabDocumentText(pages: [LabDocumentPage(pageNumber: 1,
            lines: ["Ferritin 45,237 ng/mL 30 - 400", "B12 Vitamini 350 pg/mL 200 - 900"], source: .textLayer)], fileName: "örnek.pdf"))
    }

    @Test("Yüksek güvenli satır bile kullanıcı onayı olmadan yazılmaz")
    func explicitConsent() async throws {
        let store = try ZenithiumStore(modelContainer: ModelContainerFactory.makeInMemory())
        let model = LabImportViewModel(repository: store)
        model.apply(draft())
        #expect(model.rows.count == 2)
        #expect(model.rows.allSatisfy { !$0.isSelected })
        #expect(!model.canSave)
        await model.save()
        #expect(try await store.bloodMarkers().isEmpty)
        let index = try #require(model.rows.firstIndex { $0.marker == .ferritin })
        #expect(model.rows[index].value == 45.237)
        model.rows[index].isSelected = true
        await model.save()
        let saved = try await store.bloodMarkers()
        #expect(saved.count == 1)
        #expect(saved.first?.value == 45.237)
    }

    @Test("Hata sonrası tekrar deneme kayıtları çoğaltmaz")
    func partialFailureCanRetry() async throws {
        let store = FailingLabStore()
        let model = LabImportViewModel(repository: store)
        model.apply(draft())
        for index in model.rows.indices { model.rows[index].isSelected = true }
        await model.save()
        #expect(model.phase == .reviewing)
        #expect(model.saveFailure != nil)
        #expect(model.savedIDs.count == 1)
        await model.save()
        #expect(model.phase == .finished(savedCount: 2))
        #expect(await store.bloodMarkers().count == 2)
    }

    @Test("Birim dönüşümü sonuç ve referansa aynı katsayıyı uygular")
    func conversionPreservesReference() throws {
        let result = try LabRecording.prepare(marker: .standard("totalCholesterol"), value: 5, unit: "mmol/L", reference: MarkerRange(minimum: 2, maximum: 6))
        #expect(abs(result.value - 193.35) < 0.00001)
        #expect(result.unit == "mg/dL")
        #expect(abs((result.reference.maximum ?? 0) - 232.02) < 0.00001)
    }

    @Test("Referans yoksa katalogdan uydurulmaz")
    func absentRangeStaysAbsent() async throws {
        let store = try ZenithiumStore(modelContainer: ModelContainerFactory.makeInMemory())
        let model = BloodworkViewModel(repository: store)
        await model.save(marker: .ferritin, value: 45, unitSymbol: "ng/mL", referenceRange: nil, optimalRange: nil, drawnAt: Date(), note: "")
        let item = try #require(try await store.bloodMarkers().first)
        #expect(!item.referenceRange.isBounded)
        #expect(!item.optimalRange.isBounded)
    }

    @Test("Tanınmayan birim ve ters aralık kabul edilmez")
    func invalidInputsRejected() {
        #expect(throws: (any Error).self) { try LabRecording.prepare(marker: .ferritin, value: 45, unit: "mmol/L", reference: .unbounded) }
        #expect(throws: (any Error).self) { try LabRecording.prepare(marker: .ferritin, value: 45, unit: "ng/mL", reference: MarkerRange(minimum: 400, maximum: 30)) }
    }
}

private actor FailingLabStore: BloodMarkerRepository {
    private var rows: [UUID: BloodMarkerSnapshot] = [:]
    private var hasFailed = false
    func bloodMarkers() -> [BloodMarkerSnapshot] { Array(rows.values) }
    func deleteBloodMarker(id: UUID) { rows.removeValue(forKey: id) }
    func saveBloodMarker(id: UUID, marker: BloodMarkerKind, value: Double, unitSymbol: String, referenceRange: MarkerRange, optimalRange: MarkerRange, drawnAt: Date, note: String) throws -> BloodMarkerSnapshot {
        if rows.count == 1 && !hasFailed {
            hasFailed = true
            throw ZenithiumError.persistenceWriteFailed(detail: "Kayıt testi")
        }
        let row = BloodMarkerSnapshot(id: id, marker: marker, value: value, unitSymbol: unitSymbol, referenceRange: referenceRange, optimalRange: optimalRange, drawnAt: drawnAt, note: note)
        rows[id] = row
        return row
    }
}
