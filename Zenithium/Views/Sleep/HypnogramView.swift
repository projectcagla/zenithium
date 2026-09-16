import SwiftUI
import Charts

/// Renders original timestamps only. Reading and normalization belong to the pipeline.
struct HypnogramView: View {
    let record: BiometricDaySnapshot
    var recordedSegments: [SleepSegment] = []
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 180
    @State private var selectedDate: Date?

    private var selectedStage: SleepStage? {
        guard let selectedDate else { return nil }
        return recordedSegments.first { $0.start <= selectedDate && $0.end > selectedDate }?.stage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
            Text("GECE BOYUNCA").zenithiumEyebrow()
            if recordedSegments.isEmpty {
                Text("Bu kayıt için evre zamanları yok. Toplam süre ve evre dağılımın aşağıda.").zenithiumCaption()
            } else {
                Chart {
                    ForEach(Array(recordedSegments.enumerated()), id: \.offset) { _, segment in
                        BarMark(xStart: .value("Başlangıç", segment.start), xEnd: .value("Bitiş", segment.end),
                            y: .value("Evre", segment.stage.displayName), height: .ratio(0.55))
                            .foregroundStyle(ZenithiumColor.accent.opacity(segment.stage == .awake ? 0.4 : 0.8))
                            .cornerRadius(3)
                            .accessibilityLabel(segment.stage.displayName)
                            .accessibilityValue("\(clock(segment.start))–\(clock(segment.end)), \(ZenithiumFormat.spokenDuration(seconds: segment.end.timeIntervalSince(segment.start)))")
                    }
                    if let selectedDate {
                        RuleMark(x: .value("Seçim", selectedDate)).foregroundStyle(ZenithiumColor.textSecondary)
                    }
                }
                .chartYScale(domain: [.asleepDeep, .asleepCore, .asleepREM, .asleepUnspecified, .awake].map { (stage: SleepStage) in stage.displayName })
                .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 2)) { _ in AxisValueLabel(format: .dateTime.hour().minute()) } }
                .chartXSelection(value: $selectedDate)
                .frame(minHeight: chartHeight)
                if let selectedDate {
                    Text("\(clock(selectedDate)) · \(selectedStage?.displayName ?? "Ölçüm yok")").zenithiumCaption()
                }
                Text("Çubuklar kayıtlı evre aralıklarıdır. Boşluklar doldurulmaz; saat evreleri uyku laboratuvarı ölçümü değildir.").zenithiumCaption()
            }
        }
    }

    private func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "tr_TR"),
            timeZone: TimeZone(identifier: record.timeZoneIdentifier) ?? .current))
    }
}

extension HypnogramView {
    func asZenithiumChart() -> some View { self }
}
