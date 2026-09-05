import SwiftUI

/// Plots recorded stage timestamps. Aggregate durations cannot reconstruct a hypnogram.
struct HypnogramView: View {
    let record: BiometricDaySnapshot
    var source: (any HealthDataProviding)? = nil
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 180
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var recordedSegments: [SleepSegment] = []
    @State private var selectedDate: Date?
    @State private var isLoading = true
    @State private var readFailed = false

    private let stages: [SleepStage] = [.awake, .asleepREM, .asleepCore, .asleepDeep]
    private var window: DateInterval? {
        guard let start = record.sleepStart, let end = record.wakeTime, end > start else { return nil }
        return DateInterval(start: start, end: end)
    }
    private var selectedStage: SleepStage? {
        guard let selectedDate else { return nil }
        return recordedSegments.first { $0.start <= selectedDate && $0.end > selectedDate }?.stage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithiumSpacing.m) {
            HStack {
                Text("GECE BOYUNCA").zenithiumEyebrow()
                Spacer()
                if let selectedDate {
                    Text("\(clock(selectedDate)) · \(selectedStage?.displayName ?? "Ölçüm yok")")
                        .zenithiumCaption()
                }
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(stages, id: \.self) { stage in
                        Text(stage == .asleepCore ? "Hafif" : stage.displayName)
                            .font(ZenithiumFont.caption)
                            .foregroundStyle(ZenithiumColor.textSecondary)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
                .frame(width: 44)
                GeometryReader { proxy in
                    timeline
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 8).onChanged { value in
                            guard let window, proxy.size.width > 0, !recordedSegments.isEmpty else { return }
                            let fraction = min(max(value.location.x / proxy.size.width, 0), 1)
                            selectedDate = window.start.addingTimeInterval(window.duration * fraction)
                        }.onEnded { _ in selectedDate = nil })
                }
            }
            .frame(height: chartHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Uyku evrelerinin zaman çizelgesi")
            .accessibilityValue(recordedSegments.isEmpty ? "Evre zamanları mevcut değil." : "\(recordedSegments.count) kayıtlı evre. Derin uyku \(ZenithiumFormat.spokenDuration(seconds: record.deepSeconds)); REM \(ZenithiumFormat.spokenDuration(seconds: record.remSeconds)).")

            HStack {
                Text(record.sleepStart.map(clock) ?? "—")
                Spacer()
                Text(record.wakeTime.map(clock) ?? "—")
            }
            .font(ZenithiumFont.caption.monospacedDigit())
            .foregroundStyle(ZenithiumColor.textSecondary)
            .padding(.leading, 52)
            if recordedSegments.isEmpty {
                Text(isLoading ? "Evre zamanları okunuyor…" : (readFailed ? "Evre zamanları okunamadı. Toplam süre ve evre dağılımın aşağıda." : "Bu kayıt için evre zamanları yok. Toplam süre ve evre dağılımın aşağıda."))
                    .zenithiumCaption()
            }
        }
        .task(id: record.computedAt) { await loadTimeline() }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isLoading)
    }

    private var timeline: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            func y(_ stage: SleepStage) -> CGFloat {
                let index = stages.firstIndex(of: stage) ?? 2
                return (CGFloat(index) + 0.5) * size.height / 4
            }
            for stage in stages {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y(stage)))
                line.addLine(to: CGPoint(x: size.width, y: y(stage)))
                context.stroke(line, with: .color(ZenithiumColor.hairline), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
            }
            guard let window else { return }
            func x(_ date: Date) -> CGFloat {
                CGFloat(date.timeIntervalSince(window.start) / window.duration) * size.width
            }
            var previous: SleepSegment?
            for segment in recordedSegments {
                let left = max(0, x(segment.start))
                let right = min(size.width, x(segment.end))
                guard right > left else { continue }
                let tint = ZenithiumColor.color(for: segment.stage)
                let rect = CGRect(x: left, y: y(segment.stage) - 9, width: right - left, height: 18)
                context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(tint.opacity(0.28)))
                var line = Path()
                line.move(to: CGPoint(x: left, y: y(segment.stage)))
                line.addLine(to: CGPoint(x: right, y: y(segment.stage)))
                context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                if let prior = previous, abs(prior.end.timeIntervalSince(segment.start)) < 1 {
                    var join = Path()
                    join.move(to: CGPoint(x: left, y: y(prior.stage)))
                    join.addLine(to: CGPoint(x: left, y: y(segment.stage)))
                    context.stroke(join, with: .color(ZenithiumColor.textSecondary.opacity(0.35)), lineWidth: 1)
                }
                previous = segment
            }
            if let selectedDate {
                var cursor = Path()
                cursor.move(to: CGPoint(x: x(selectedDate), y: 0))
                cursor.addLine(to: CGPoint(x: x(selectedDate), y: size.height))
                context.stroke(cursor, with: .color(ZenithiumColor.textPrimary.opacity(0.6)), lineWidth: 1)
            }
        }
    }

    private func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "tr_TR"), timeZone: TimeZone(identifier: record.timeZoneIdentifier) ?? .current))
    }

    private func loadTimeline() async {
        recordedSegments = []
        selectedDate = nil
        isLoading = true
        readFailed = false
        defer { isLoading = false }
        guard let window else { return }
        let provider: any HealthDataProviding = source ?? HealthKitService()
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = TimeZone(identifier: record.timeZoneIdentifier) ?? .current
        do {
            let overnight = try await provider.fetchOvernightBiometrics(for: window, calendar: calendar, previousWakeTime: nil)
            guard !Task.isCancelled else { return }
            recordedSegments = overnight.sleepSegments
                .filter { $0.stage != .inBed && $0.end > window.start && $0.start < window.end }
                .resolvedNonOverlapping
                .sorted { $0.start < $1.start }
        } catch {
            guard !Task.isCancelled else { return }
            readFailed = true
        }
    }
}

extension HypnogramView {
    func asZenithiumChart() -> some View { self }
}
