import XCTest
@testable import NetglassCore

final class ReportExportTests: XCTestCase {
    private let when = Date(timeIntervalSince1970: 1_788_904_800) // 2026-09-08T22:00:00Z

    func testMarkdownStructureIncludesMetadataAndFencedOutput() {
        let snapshot = makeSnapshot(
            tool: .ping,
            preview: "/sbin/ping -c 3 1.1.1.1",
            status: "Finished · 0",
            exitCode: 0,
            lines: ["64 bytes from 1.1.1.1: icmp_seq=0 ttl=57 time=12.3 ms"]
        )
        let md = ReportFormatter.markdown(snapshot)
        XCTAssertTrue(md.hasPrefix("# Ping\n"))
        XCTAssertTrue(md.contains("| When | 2026-09-08T22:00:00Z |"))
        XCTAssertTrue(md.contains("| Command | `/sbin/ping -c 3 1.1.1.1` |"))
        XCTAssertTrue(md.contains("| Status | Finished · 0 |"))
        XCTAssertTrue(md.contains("| Duration | 2.0 s |"))
        XCTAssertTrue(md.contains("| Truncated | no |"))
        XCTAssertTrue(md.contains("```text\n64 bytes from 1.1.1.1: icmp_seq=0 ttl=57 time=12.3 ms\n```\n"))
        XCTAssertFalse(md.contains("Ring buffer"))
    }

    func testMarkdownNotesTruncation() {
        var snapshot = makeSnapshot(tool: .whois, lines: ["whois example.com"])
        snapshot.truncated = true
        let md = ReportFormatter.markdown(snapshot)
        XCTAssertTrue(md.contains("yes — last 5000 lines"))
        XCTAssertTrue(md.contains("Ring buffer kept the newest 5,000 lines."))
    }

    func testPlainTextIncludesArgvAndTranscript() {
        let text = ReportFormatter.plainText(makeSnapshot(
            tool: .curl,
            preview: "/usr/bin/curl -I https://example.com",
            status: "Finished · 0",
            lines: ["HTTP/2 200"]
        ))
        XCTAssertTrue(text.contains("Tool:      Headers"))
        XCTAssertTrue(text.contains("Command:   /usr/bin/curl -I https://example.com"))
        XCTAssertTrue(text.contains("HTTP/2 200"))
    }

    func testCSVFallbackIsLineNumberAndText() {
        let snapshot = makeSnapshot(
            tool: .whois,
            lines: ["Domain Name: EXAMPLE.COM", "note, with comma"]
        )
        let table = ReportFormatter.csvTable(snapshot)
        XCTAssertEqual(table.kind, .fallback)
        XCTAssertEqual(table.header, ["line_number", "text"])
        XCTAssertEqual(table.rows, [
            ["1", "Domain Name: EXAMPLE.COM"],
            ["2", "note, with comma"],
        ])
        let rendered = ReportFormatter.csv(snapshot)
        XCTAssertEqual(rendered, "line_number,text\n1,Domain Name: EXAMPLE.COM\n2,\"note, with comma\"\n")
    }

    func testCSVEmptySnapshotStillHasHeader() {
        let snapshot = makeSnapshot(tool: .netcat, lines: [])
        XCTAssertEqual(ReportFormatter.csv(snapshot), "line_number,text\n")
    }

    func testCSVPingParsesTimingLines() {
        let snapshot = makeSnapshot(
            tool: .ping,
            lines: [
                "PING 1.1.1.1 (1.1.1.1): 56 data bytes",
                "64 bytes from 1.1.1.1: icmp_seq=0 ttl=57 time=12.3 ms",
                "64 bytes from 1.1.1.1: icmp_seq=1 ttl=57 time=11.8 ms",
                "--- 1.1.1.1 ping statistics ---",
            ]
        )
        let table = ReportFormatter.csvTable(snapshot)
        XCTAssertEqual(table.kind, .ping)
        XCTAssertEqual(table.header, ["icmp_seq", "ttl", "bytes", "time_ms", "host"])
        XCTAssertEqual(table.rows, [
            ["0", "57", "64", "12.3", "1.1.1.1"],
            ["1", "57", "64", "11.8", "1.1.1.1"],
        ])
    }

    func testCSVPingParsesHostnameAndIPv6() {
        let snapshot = makeSnapshot(
            tool: .ping,
            lines: [
                "64 bytes from example.com (1.1.1.1): icmp_seq=2 ttl=57 time=9.1 ms",
                "64 bytes from 2001:db8::1: icmp_seq=3 ttl=54 time=8.0ms",
            ]
        )
        let table = ReportFormatter.csvTable(snapshot)
        XCTAssertEqual(table.kind, .ping)
        XCTAssertEqual(table.rows[0][4], "example.com (1.1.1.1)")
        XCTAssertEqual(table.rows[1], ["3", "54", "64", "8.0", "2001:db8::1"])
    }

    func testCSVPingFallsBackWithoutTimingLines() {
        let snapshot = makeSnapshot(tool: .ping, lines: ["ping: cannot resolve example.invalid"])
        XCTAssertEqual(ReportFormatter.csvTable(snapshot).kind, .fallback)
    }

    func testCSVDigParsesAnswerSection() {
        let snapshot = makeSnapshot(
            tool: .dig,
            lines: [
                "; <<>> DiG <<>> example.com",
                ";; ANSWER SECTION:",
                "example.com.\t\t300\tIN\tA\t93.184.216.34",
                "example.com.\t\t300\tIN\tAAAA\t2606:2800:220:1:248:1893:25c8:1946",
                ";; Query time: 18 msec",
            ]
        )
        let table = ReportFormatter.csvTable(snapshot)
        XCTAssertEqual(table.kind, .dig)
        XCTAssertEqual(table.header, ["section", "name", "ttl", "class", "type", "rdata"])
        XCTAssertEqual(table.rows.count, 2)
        XCTAssertEqual(table.rows[0], ["ANSWER", "example.com.", "300", "IN", "A", "93.184.216.34"])
        XCTAssertEqual(table.rows[1][4], "AAAA")
    }

    func testCSVNmapParsesPortTable() {
        let snapshot = makeSnapshot(
            tool: .nmap,
            lines: [
                "Starting Nmap 7.95",
                "Nmap scan report for example.com (93.184.216.34)",
                "Host is up (0.012s latency).",
                "PORT     STATE SERVICE",
                "80/tcp   open  http",
                "443/tcp  open  https",
                "22/tcp   closed ssh",
            ]
        )
        let table = ReportFormatter.csvTable(snapshot)
        XCTAssertEqual(table.kind, .nmap)
        XCTAssertEqual(table.header, ["host", "port", "protocol", "state", "service"])
        XCTAssertEqual(table.rows, [
            ["example.com (93.184.216.34)", "80", "tcp", "open", "http"],
            ["example.com (93.184.216.34)", "443", "tcp", "open", "https"],
            ["example.com (93.184.216.34)", "22", "tcp", "closed", "ssh"],
        ])
    }

    func testCSVNmapFallsBackWithoutPorts() {
        let snapshot = makeSnapshot(tool: .nmap, lines: ["Host is up (0.01s latency)."])
        XCTAssertEqual(ReportFormatter.csvTable(snapshot).kind, .fallback)
    }

    func testCSVEscapesQuotesAndNewlines() {
        XCTAssertEqual(ReportFormatter.csvField("plain"), "plain")
        XCTAssertEqual(ReportFormatter.csvField("a,b"), "\"a,b\"")
        XCTAssertEqual(ReportFormatter.csvField("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    func testAICopyHasInstructionHeaderAndOutput() {
        let snapshot = makeSnapshot(
            tool: .dig,
            preview: "/opt/homebrew/bin/dig example.com A",
            status: "Finished · 0",
            lines: ["; ANSWER", "example.com. 300 IN A 93.184.216.34"]
        )
        let payload = ReportFormatter.aiCopy(snapshot)
        XCTAssertTrue(payload.contains("You are helping diagnose a local network issue."))
        XCTAssertTrue(payload.contains("ran a local CLI tool as argv (no shell)"))
        XCTAssertTrue(payload.contains("Do not invent packet captures"))
        XCTAssertTrue(payload.contains("- Tool: Dig"))
        XCTAssertTrue(payload.contains("- Host OS: macOS (test)"))
        XCTAssertTrue(payload.contains("- Command (argv): /opt/homebrew/bin/dig example.com A"))
        XCTAssertTrue(payload.contains("- Status: Finished · 0"))
        XCTAssertTrue(payload.contains("```\n; ANSWER\nexample.com. 300 IN A 93.184.216.34\n```\n"))
        XCTAssertFalse(payload.lowercased().contains("authorization"))
        XCTAssertFalse(payload.contains("AWS_"))
    }

    func testSuggestedFilenameUsesToolAndUTCStamp() {
        let name = ReportFormatter.suggestedFilename(
            makeSnapshot(tool: .ping, lines: ["ok"]),
            format: .markdown
        )
        XCTAssertEqual(name, "ping-20260908T220002Z.md")
    }

    func testMissingCommandPreviewIsExplicit() {
        let snapshot = makeSnapshot(tool: .traceroute, preview: "", lines: ["hop"])
        XCTAssertTrue(ReportFormatter.plainText(snapshot).contains("Command:   (not recorded)"))
        XCTAssertTrue(ReportFormatter.aiCopy(snapshot).contains("Command (argv): (not recorded)"))
    }

    private func makeSnapshot(
        tool: ToolKind,
        preview: String = "/usr/bin/example",
        status: String = "Finished · 0",
        exitCode: Int32? = 0,
        truncated: Bool = false,
        lines: [String]
    ) -> ReportSnapshot {
        ReportSnapshot(
            tool: tool,
            commandPreview: preview,
            startedAt: when,
            capturedAt: when.addingTimeInterval(2),
            finishedAt: when.addingTimeInterval(2),
            status: status,
            exitCode: exitCode,
            truncated: truncated,
            hostOSNote: "macOS (test)",
            lines: lines.map { ReportLine(text: $0, stream: "stdout") }
        )
    }
}
