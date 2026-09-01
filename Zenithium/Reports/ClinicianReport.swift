//
//  ClinicianReport.swift
//  Zenithium
//
//  The report you hand a doctor. Faz 27.
//
//  This is the reverse direction of Faz 23, and it is the feature that makes Zenithium's
//  §12 position coherent rather than merely cautious. The app is not allowed to interpret —
//  fine. What it *can* do is make the twelve weeks of data legible enough that the person
//  who is allowed to interpret has something to work with. "Nabzım bazen yükseliyor" becomes
//  a page.
//
//  Three rules the content obeys, and they are the same three §12 has always set:
//
//  * Numbers, ranges and dates. No interpretation, no flags, no conclusions.
//  * Where a value sits against a published range is stated; whether that is good is not.
//  * Every section says how much data it is built on, so nothing looks more certain than it is.
//
//  The document is built on device and handed to the share sheet. It is never uploaded, and
//  there is no service behind it — the same as everything else here.
//

import Foundation

/// One row of a trend table.
struct ReportTrendRow: Sendable, Equatable, Hashable, Identifiable {

    let label: String

    /// Mean across the window, already formatted.
    let mean: String

    /// Range across the window, already formatted.
    let range: String

    /// How many days carried a value.
    let sampleCount: Int

    /// Direction over the window, when a line could be fitted.
    let trend: String?

    var id: String { label }
}

/// One section of the report.
struct ReportSection: Sendable, Equatable, Hashable, Identifiable {

    let title: String

    /// A sentence about what the section contains and how much of it there is.
    let caption: String?

    let rows: [ReportTrendRow]

    /// Free-text lines, for sections that are not tables.
    let lines: [String]

    var id: String { title }

    init(title: String, caption: String? = nil, rows: [ReportTrendRow] = [], lines: [String] = []) {
        self.title = title
        self.caption = caption
        self.rows = rows
        self.lines = lines
    }

    var isEmpty: Bool { rows.isEmpty && lines.isEmpty }
}

/// The assembled report, before it becomes a document.
struct ClinicianReport: Sendable, Equatable {

    /// The window covered.
    let start: Date
    let end: Date

    let sections: [ReportSection]

    /// The §12 notice. Not optional, and rendered first — a clinician opening this needs to
    /// know within one line what produced it and what it is not.
    let disclaimer: String

    var isEmpty: Bool { sections.allSatisfy(\.isEmpty) }
}
