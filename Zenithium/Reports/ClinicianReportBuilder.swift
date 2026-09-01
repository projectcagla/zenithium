//
//  ClinicianReportBuilder.swift
//  Zenithium
//
//  Assembles the report. Faz 27.
//
//  Pure: takes values, returns a report. No repositories, no rendering, no PDF — which means
//  the content rules can be tested against literals, and the §12 boundary can be asserted
//  rather than reviewed by eye.
//

import Foundation

enum ClinicianReportBuilder {

    /// How far back the report reaches, in days.
    static let windowDays = 84

    /// Below this many values a row is not worth printing; a mean of three days would look
    /// like a measurement and is not one.
    static let minimumSamplesForRow = 10

    static func build(
        days: [BiometricDaySnapshot],
        vitals: [VitalReading],
        markers: [BloodMarkerSnapshot],
        sex: BiologicalSexValue,
        now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> ClinicianReport {
        let start = calendar.date(byAdding: .day, value: -windowDays, to: now) ?? now
        let window = days.filter { $0.dayStart >= start && $0.dayStart <= now }

        var sections: [ReportSection] = [
            coreSection(window),
            sleepSection(window),
            vitalsSection(vitals)
        ]
        if let labs = labSection(markers: markers, sex: sex, now: now, calendar: calendar) {
            sections.append(labs)
        }
        if let anomalies = anomalySection(window) {
            sections.append(anomalies)
        }

        return ClinicianReport(
            start: start,
            end: now,
            sections: sections.filter { !$0.isEmpty },
            disclaimer: SafetyCopy.reportDisclaimer
        )
    }

    // MARK: - Sections

    private static func coreSection(_ days: [BiometricDaySnapshot]) -> ReportSection {
        var rows: [ReportTrendRow] = []
        if let row = row(label: "İstirahat nabzı (bpm)", values: days.compactMap(\.restingHeartRate), digits: 0) {
            rows.append(row)
        }
        if let row = row(label: "HRV, SDNN (ms)", values: days.compactMap(\.heartRateVariability), digits: 0) {
            rows.append(row)
        }
        if let row = row(label: "Solunum hızı (/dk)", values: days.compactMap(\.respiratoryRate), digits: 1) {
            rows.append(row)
        }
        if let row = row(label: "Kandaki oksijen (%)", values: days.compactMap(\.oxygenSaturation), digits: 1) {
            rows.append(row)
        }
        return ReportSection(
            title: "Gece ölçümleri",
            caption: "Apple Watch tarafından uyku sırasında kaydedildi. \(days.count) günlük pencere.",
            rows: rows
        )
    }

    private static func sleepSection(_ days: [BiometricDaySnapshot]) -> ReportSection {
        var rows: [ReportTrendRow] = []
        let hours = days.map { $0.sleepDurationSeconds / 3600 }.filter { $0 > 0 }
        if let row = row(label: "Uyku süresi (saat)", values: hours, digits: 1) {
            rows.append(row)
        }
        if let row = row(label: "Uyku verimliliği (%)", values: days.compactMap(\.sleepEfficiency).map { $0 * 100 }, digits: 0) {
            rows.append(row)
        }
        let deepShare = days.compactMap { day -> Double? in
            let asleep = day.deepSeconds + day.remSeconds + day.coreSeconds
            guard asleep > 0 else { return nil }
            return (day.deepSeconds + day.remSeconds) / asleep * 100
        }
        if let row = row(label: "Derin + REM payı (%)", values: deepShare, digits: 0) {
            rows.append(row)
        }
        return ReportSection(title: "Uyku", rows: rows)
    }

    private static func vitalsSection(_ vitals: [VitalReading]) -> ReportSection {
        let rows = vitals.compactMap { reading -> ReportTrendRow? in
            let values = reading.history.map(\.value)
            guard let row = row(
                label: "\(reading.sign.displayName) (\(reading.sign.unitSymbol))",
                values: values,
                digits: reading.sign.fractionDigits
            ) else { return nil }

            guard let slope = VitalsEngine.slopePerDay(of: reading.history) else { return row }
            let perMonth = slope * 30
            let direction = perMonth > 0 ? "artış" : "azalış"
            return ReportTrendRow(
                label: row.label,
                mean: row.mean,
                range: row.range,
                sampleCount: row.sampleCount,
                trend: abs(perMonth) < pow(10, Double(-reading.sign.fractionDigits))
                    ? "değişim yok"
                    : "ayda \(ZenithiumFormat.metric(abs(perMonth), digits: reading.sign.fractionDigits)) \(direction)"
            )
        }
        return ReportSection(
            title: "Diğer ölçümler",
            caption: "Her satırın eğilimi, pencere boyunca en küçük kareler doğrusundan.",
            rows: rows
        )
    }

    /// Blood markers, with the laboratory's own band and where the value sits in it.
    ///
    /// Says *where* and never *whether*. The clinician reading this does the second part;
    /// that is the entire point of handing it to them.
    private static func labSection(
        markers: [BloodMarkerSnapshot],
        sex: BiologicalSexValue,
        now: Date,
        calendar: Calendar
    ) -> ReportSection? {
        guard !markers.isEmpty else { return nil }

        let grouped = Dictionary(grouping: markers, by: { $0.marker.storageKey })
        var lines: [String] = []

        for (_, entries) in grouped {
            let ordered = entries.sorted { $0.drawnAt < $1.drawnAt }
            guard let latest = ordered.last else { continue }

            let value = ZenithiumFormat.metric(latest.value, digits: latest.marker.fractionDigits)
            var line = "\(latest.marker.displayName): \(value) \(latest.unitSymbol)"
            line += " · \(latest.drawnAt.formatted(date: .numeric, time: .omitted))"

            let band = latest.referenceRange.isBounded
                ? latest.referenceRange
                : latest.marker.referenceRange(for: sex)
            if let minimum = band.minimum, let maximum = band.maximum {
                let digits = latest.marker.fractionDigits
                line += " · referans \(ZenithiumFormat.metric(minimum, digits: digits))–\(ZenithiumFormat.metric(maximum, digits: digits))"
                if !band.contains(latest.value) {
                    line += " · aralık dışı"
                }
            }

            if ordered.count >= 2 {
                let previous = ordered[ordered.count - 2]
                let delta = latest.value - previous.value
                let days = calendar.dateComponents([.day], from: previous.drawnAt, to: latest.drawnAt).day ?? 0
                line += " · önceki ölçüme göre \(ZenithiumFormat.signed(delta, digits: latest.marker.fractionDigits)) (\(days) gün)"
            }
            lines.append(line)
        }

        return ReportSection(
            title: "Kan değerleri",
            caption: "Kullanıcının kendi laboratuvar raporundan girildi. Yorum yok; yalnızca değer, tarih ve raporun kendi referans aralığı.",
            lines: lines.sorted()
        )
    }

    /// Days that sat outside the window's own range on several signals at once.
    ///
    /// Flagged as *dates*, not as findings. The report says "these mornings were unlike the
    /// others" and leaves every question about why to the person reading it.
    private static func anomalySection(_ days: [BiometricDaySnapshot]) -> ReportSection? {
        let restingValues = days.compactMap(\.restingHeartRate)
        let hrvValues = days.compactMap(\.heartRateVariability)
        guard restingValues.count >= minimumSamplesForRow, hrvValues.count >= minimumSamplesForRow else {
            return nil
        }
        guard let restingMean = MathSupport.mean(restingValues),
              let hrvMean = MathSupport.mean(hrvValues) else { return nil }

        let restingDeviation = deviation(of: restingValues, mean: restingMean)
        let hrvDeviation = deviation(of: hrvValues, mean: hrvMean)
        guard restingDeviation > 0, hrvDeviation > 0 else { return nil }

        var lines: [String] = []
        for day in days.sorted(by: { $0.dayStart < $1.dayStart }) {
            guard let resting = day.restingHeartRate, let hrv = day.heartRateVariability else { continue }
            let restingZ = (resting - restingMean) / restingDeviation
            let hrvZ = (hrv - hrvMean) / hrvDeviation
            guard restingZ >= 1.5, hrvZ <= -1.5 else { continue }
            lines.append(
                "\(day.dayStart.formatted(date: .numeric, time: .omitted)): istirahat nabzı \(ZenithiumFormat.metric(resting, digits: 0)) bpm (+\(ZenithiumFormat.metric(restingZ, digits: 1))σ), HRV \(ZenithiumFormat.metric(hrv, digits: 0)) ms (\(ZenithiumFormat.metric(hrvZ, digits: 1))σ)"
            )
        }
        guard !lines.isEmpty else { return nil }

        return ReportSection(
            title: "Öne çıkan günler",
            caption: "Bu tarihlerde istirahat nabzı ve HRV aynı anda pencere ortalamasından 1,5 standart sapmadan fazla ayrıldı. Bu bir bulgu değil, bir tarih listesidir.",
            lines: lines
        )
    }

    // MARK: - Helpers

    static func row(label: String, values: [Double], digits: Int) -> ReportTrendRow? {
        guard values.count >= minimumSamplesForRow,
              let mean = MathSupport.mean(values),
              let minimum = values.min(),
              let maximum = values.max() else { return nil }

        return ReportTrendRow(
            label: label,
            mean: ZenithiumFormat.metric(mean, digits: digits),
            range: "\(ZenithiumFormat.metric(minimum, digits: digits))–\(ZenithiumFormat.metric(maximum, digits: digits))",
            sampleCount: values.count,
            trend: nil
        )
    }

    private static func deviation(of values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot()
    }
}
