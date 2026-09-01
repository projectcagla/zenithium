//
//  ReportDocumentRenderer.swift
//  Zenithium
//
//  Turns a `ClinicianReport` into a PDF. Faz 27.
//
//  ASSUMPTION REPORT-1: this file imports UIKit for `UIGraphicsPDFRenderer` and
//  `NSAttributedString` drawing. UIKit is not on the §2.2 framework list, and UI-5 avoided
//  it for a single string constant — but there is no Core Graphics path to laid-out,
//  paginated text, and reimplementing line breaking would be a worse trade than the import.
//  The use is confined to this file. Reversal: drop the export and keep the on-screen report.
//
//  The renderer knows nothing about health. It receives sections and draws them, so every
//  rule about what may appear in the document lives in `ClinicianReportBuilder` where it can
//  be tested.
//

import Foundation
import UIKit

enum ReportDocumentRenderer {

    /// A4 at 72 dpi, which is what `UIGraphicsPDFRenderer` works in.
    static let pageSize = CGSize(width: 595.2, height: 841.8)
    static let margin: CGFloat = 48

    /// Render a report to PDF data.
    static func render(_ report: ClinicianReport) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))

        return renderer.pdfData { context in
            var cursor = margin
            context.beginPage()

            /// Start a new page when the next block would not fit.
            func ensureRoom(for height: CGFloat) {
                if cursor + height > pageSize.height - margin {
                    context.beginPage()
                    cursor = margin
                }
            }

            func draw(_ text: String, style: TextStyle, spacingAfter: CGFloat) {
                let attributed = NSAttributedString(string: text, attributes: style.attributes)
                let available = CGSize(width: pageSize.width - margin * 2, height: .greatestFiniteMagnitude)
                let bounds = attributed.boundingRect(
                    with: available,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                ensureRoom(for: bounds.height)
                attributed.draw(
                    with: CGRect(x: margin, y: cursor, width: available.width, height: bounds.height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                cursor += bounds.height + spacingAfter
            }

            draw("Zenithium — Sağlık Özeti", style: .title, spacingAfter: 4)
            draw(
                "\(report.start.formatted(date: .long, time: .omitted)) – \(report.end.formatted(date: .long, time: .omitted))",
                style: .caption,
                spacingAfter: 14
            )
            draw(report.disclaimer, style: .disclaimer, spacingAfter: 20)

            for section in report.sections {
                draw(section.title, style: .heading, spacingAfter: 3)
                if let caption = section.caption {
                    draw(caption, style: .caption, spacingAfter: 8)
                }

                if !section.rows.isEmpty {
                    draw(
                        columns("Ölçüm", "Ortalama", "Aralık", "Gün"),
                        style: .tableHeader,
                        spacingAfter: 2
                    )
                    for row in section.rows {
                        var line = columns(row.label, row.mean, row.range, "\(row.sampleCount)")
                        if let trend = row.trend { line += "  (\(trend))" }
                        draw(line, style: .body, spacingAfter: 2)
                    }
                }

                for line in section.lines {
                    draw("• " + line, style: .body, spacingAfter: 2)
                }
                cursor += 14
            }
        }
    }

    /// Pad the columns into a monospaced grid.
    ///
    /// A drawn table would need measurement passes and column arithmetic for four columns of
    /// short strings; a monospaced font and fixed widths gets the same result in one line and
    /// cannot drift out of alignment.
    private static func columns(_ label: String, _ mean: String, _ range: String, _ count: String) -> String {
        pad(label, 34) + pad(mean, 12) + pad(range, 16) + count
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width
            ? String(text.prefix(width - 1)) + " "
            : text + String(repeating: " ", count: width - text.count)
    }

    /// The document's four text styles.
    enum TextStyle {
        case title
        case heading
        case body
        case caption
        case tableHeader
        case disclaimer

        var attributes: [NSAttributedString.Key: Any] {
            switch self {
            case .title:
                return [
                    .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
                    .foregroundColor: UIColor.black
                ]
            case .heading:
                return [
                    .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                    .foregroundColor: UIColor.black
                ]
            case .body:
                return [
                    .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                    .foregroundColor: UIColor.darkGray
                ]
            case .tableHeader:
                return [
                    .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .semibold),
                    .foregroundColor: UIColor.black
                ]
            case .caption:
                return [
                    .font: UIFont.systemFont(ofSize: 9, weight: .regular),
                    .foregroundColor: UIColor.gray
                ]
            case .disclaimer:
                return [
                    .font: UIFont.systemFont(ofSize: 8.5, weight: .regular),
                    .foregroundColor: UIColor.darkGray
                ]
            }
        }
    }
}
