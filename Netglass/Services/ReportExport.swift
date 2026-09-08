import Foundation

struct ReportLine: Equatable, Sendable {
    var text: String
    var stream: String
}

/// Immutable view of a console buffer plus run metadata. Formatters never
/// re-run a tool; they only render what the session already captured.
struct ReportSnapshot: Equatable, Sendable {
    var tool: ToolKind
    var commandPreview: String
    var startedAt: Date?
    var capturedAt: Date
    var finishedAt: Date?
    var status: String
    var exitCode: Int32?
    var truncated: Bool
    var hostOSNote: String
    var lines: [ReportLine]

    var duration: TimeInterval? {
        guard let startedAt else { return nil }
        return (finishedAt ?? capturedAt).timeIntervalSince(startedAt)
    }

    var transcript: String {
        lines.map(\.text).joined(separator: "\n")
    }

    static var defaultHostOSNote: String {
        "macOS \(ProcessInfo.processInfo.operatingSystemVersionString) (local Netglass diagnostic; output was not uploaded)"
    }
}

enum ReportFileFormat: String, CaseIterable, Sendable {
    case text
    case markdown
    case csv

    var fileExtension: String {
        switch self {
        case .text: return "txt"
        case .markdown: return "md"
        case .csv: return "csv"
        }
    }

    var displayName: String {
        switch self {
        case .text: return "Plain Text"
        case .markdown: return "Markdown"
        case .csv: return "CSV"
        }
    }
}

enum ReportFormatter {
    static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static func render(_ snapshot: ReportSnapshot, format: ReportFileFormat) -> String {
        switch format {
        case .text: return plainText(snapshot)
        case .markdown: return markdown(snapshot)
        case .csv: return csv(snapshot)
        }
    }

    static func suggestedFilename(_ snapshot: ReportSnapshot, format: ReportFileFormat) -> String {
        let stamp = isoFormatter.string(from: snapshot.capturedAt)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        return "\(snapshot.tool.rawValue)-\(stamp).\(format.fileExtension)"
    }

    static func plainText(_ snapshot: ReportSnapshot) -> String {
        var lines: [String] = [
            "Netglass report",
            "===============",
            "Tool:      \(snapshot.tool.title)",
            "When:      \(iso(snapshot.startedAt ?? snapshot.capturedAt))",
            "Command:   \(command(snapshot))",
            "Status:    \(snapshot.status)",
            "Duration:  \(durationText(snapshot))",
            "Truncated: \(snapshot.truncated ? "yes (last \(5_000) lines)" : "no")",
            "",
        ]
        if !snapshot.transcript.isEmpty {
            lines.append(snapshot.transcript)
            if !snapshot.transcript.hasSuffix("\n") {
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func markdown(_ snapshot: ReportSnapshot) -> String {
        var body = """
        # \(snapshot.tool.title)

        | Field | Value |
        | --- | --- |
        | When | \(iso(snapshot.startedAt ?? snapshot.capturedAt)) |
        | Command | `\(escapeTable(command(snapshot)))` |
        | Status | \(escapeTable(snapshot.status)) |
        | Duration | \(durationText(snapshot)) |
        | Truncated | \(snapshot.truncated ? "yes — last 5000 lines" : "no") |

        ## Output

        """
        if snapshot.truncated {
            body += "_Ring buffer kept the newest 5,000 lines._\n\n"
        }
        body += "```text\n"
        body += snapshot.transcript
        if !snapshot.transcript.hasSuffix("\n") {
            body += "\n"
        }
        body += "```\n"
        return body
    }

    static func csv(_ snapshot: ReportSnapshot) -> String {
        let table = csvTable(snapshot)
        var output = csvLine(table.header) + "\n"
        for row in table.rows {
            output += csvLine(row) + "\n"
        }
        return output
    }

    /// Clipboard payload for pasting into ChatGPT, Claude, or Cursor.
    static func aiCopy(_ snapshot: ReportSnapshot) -> String {
        var body = """
        You are helping diagnose a local network issue. The block below is output from Netglass, a macOS GUI that ran a local CLI tool as argv (no shell). Treat hostnames as potentially sensitive. Do not assume credentials, cookies, or Authorization headers are present — Netglass refuses those.

        Please: (1) summarize what the tool reported, (2) flag anything unusual or failed, (3) suggest the next *safe* diagnostic step. Do not invent packet captures, scan results, or secrets.

        ## Context
        - Tool: \(snapshot.tool.title)
        - When: \(iso(snapshot.startedAt ?? snapshot.capturedAt))
        - Host OS: \(snapshot.hostOSNote)
        - Command (argv): \(command(snapshot))
        - Status: \(snapshot.status)
        - Duration: \(durationText(snapshot))
        - Output window: \(snapshot.truncated ? "truncated to the last 5000 lines" : "complete buffered output")

        ## Output
        ```
        """
        body += snapshot.transcript
        if !snapshot.transcript.hasSuffix("\n") {
            body += "\n"
        }
        body += "```\n"
        return body
    }

    // MARK: - CSV tables

    struct CSVTable: Equatable, Sendable {
        var header: [String]
        var rows: [[String]]
        var kind: Kind

        enum Kind: String, Sendable {
            case ping
            case dig
            case nmap
            case fallback
        }
    }

    static func csvTable(_ snapshot: ReportSnapshot) -> CSVTable {
        let texts = snapshot.lines.map(\.text)
        switch snapshot.tool {
        case .ping:
            if let rows = parsePing(texts) {
                return CSVTable(
                    header: ["icmp_seq", "ttl", "bytes", "time_ms", "host"],
                    rows: rows,
                    kind: .ping
                )
            }
        case .dig:
            if let rows = parseDig(texts) {
                return CSVTable(
                    header: ["section", "name", "ttl", "class", "type", "rdata"],
                    rows: rows,
                    kind: .dig
                )
            }
        case .nmap:
            if let rows = parseNmap(texts) {
                return CSVTable(
                    header: ["host", "port", "protocol", "state", "service"],
                    rows: rows,
                    kind: .nmap
                )
            }
        default:
            break
        }
        return fallbackTable(texts)
    }

    static func fallbackTable(_ texts: [String]) -> CSVTable {
        CSVTable(
            header: ["line_number", "text"],
            rows: texts.enumerated().map { ["\($0.offset + 1)", $0.element] },
            kind: .fallback
        )
    }

    static func csvLine(_ fields: [String]) -> String {
        fields.map(csvField).joined(separator: ",")
    }

    static func csvField(_ value: String) -> String {
        if value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    // MARK: - Parsers

    private static let pingTiming = try! NSRegularExpression(
        pattern: #"^(\d+)\s+bytes from\s+(.+):\s+icmp_seq=(\d+)\s+ttl=(\d+)\s+time=([\d.]+)\s*ms"#,
        options: [.caseInsensitive]
    )

    private static let nmapPort = try! NSRegularExpression(
        pattern: #"^(\d+)/(tcp|udp|sctp)\s+(\S+)\s+(.*)$"#,
        options: [.caseInsensitive]
    )

    private static func parsePing(_ texts: [String]) -> [[String]]? {
        var rows: [[String]] = []
        for text in texts {
            let line = text.trimmingCharacters(in: .whitespaces)
            guard let match = pingTiming.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
                continue
            }
            rows.append([
                group(match, 3, in: line),
                group(match, 4, in: line),
                group(match, 1, in: line),
                group(match, 5, in: line),
                group(match, 2, in: line),
            ])
        }
        return rows.isEmpty ? nil : rows
    }

    private static func parseDig(_ texts: [String]) -> [[String]]? {
        var section: String?
        var rows: [[String]] = []
        for raw in texts {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(";;"), trimmed.uppercased().contains("SECTION") {
                let upper = trimmed.uppercased()
                if upper.contains("ANSWER") {
                    section = "ANSWER"
                } else if upper.contains("AUTHORITY") {
                    section = "AUTHORITY"
                } else if upper.contains("ADDITIONAL") {
                    section = "ADDITIONAL"
                } else {
                    section = nil
                }
                continue
            }
            if trimmed.hasPrefix(";;") || trimmed.isEmpty {
                if trimmed.hasPrefix(";;") { section = nil }
                continue
            }
            guard let section else { continue }
            let parts = trimmed.split { $0 == " " || $0 == "\t" }.map(String.init)
            guard parts.count >= 5, Int(parts[1]) != nil else { continue }
            let rdata = parts.dropFirst(4).joined(separator: " ")
            rows.append([section, parts[0], parts[1], parts[2], parts[3], rdata])
        }
        return rows.isEmpty ? nil : rows
    }

    private static func parseNmap(_ texts: [String]) -> [[String]]? {
        var host = ""
        var rows: [[String]] = []
        for raw in texts {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Nmap scan report for ") {
                host = String(line.dropFirst("Nmap scan report for ".count))
                continue
            }
            guard let match = nmapPort.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
                continue
            }
            let service = group(match, 4, in: line).trimmingCharacters(in: .whitespaces)
            rows.append([
                host,
                group(match, 1, in: line),
                group(match, 2, in: line).lowercased(),
                group(match, 3, in: line),
                service,
            ])
        }
        return rows.isEmpty ? nil : rows
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in line: String) -> String {
        guard let range = Range(match.range(at: index), in: line) else { return "" }
        return String(line[range])
    }

    // MARK: - Helpers

    private static func command(_ snapshot: ReportSnapshot) -> String {
        let preview = snapshot.commandPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        return preview.isEmpty ? "(not recorded)" : preview
    }

    static func durationText(_ snapshot: ReportSnapshot) -> String {
        guard let duration = snapshot.duration, duration >= 0, duration.isFinite else {
            return "—"
        }
        if duration < 60 {
            return String(format: "%.1f s", duration)
        }
        let minutes = Int(duration) / 60
        let seconds = duration.truncatingRemainder(dividingBy: 60)
        return String(format: "%d min %.1f s", minutes, seconds)
    }

    static func iso(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private static func escapeTable(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
