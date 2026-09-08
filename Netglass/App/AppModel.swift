import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    var selectedTool: ToolKind = .ping
    var located: [ToolKind: [LocatedBinary]] = [:]
    var extraPathText: String
    var extraPathWarnings: [String] = []
    var showingAbout = false
    @ObservationIgnored
    private var refreshWork: DispatchWorkItem?

    var ping = PingForm()
    var dig = DigForm()
    var traceroute = TracerouteForm()
    var nmap = NmapForm()
    var netcat = NetcatForm()
    var tcpdump = TcpdumpForm()
    var whois = WhoisForm()
    var curl = CurlForm()

    private var sessions: [ToolKind: ToolSession] = [:]
    private let extraPathsKey = "extraSearchPaths"

    init() {
        extraPathText = UserDefaults.standard.string(forKey: extraPathsKey) ?? ""
        refreshBinaries()
    }

    func session(_ tool: ToolKind) -> ToolSession {
        if let existing = sessions[tool] { return existing }
        let created = ToolSession(tool: tool)
        sessions[tool] = created
        return created
    }

    var currentSession: ToolSession { session(selectedTool) }

    func binaries(for tool: ToolKind) -> [LocatedBinary] {
        located[tool] ?? []
    }

    func primaryBinary(for tool: ToolKind) -> LocatedBinary? {
        binaries(for: tool).first
    }

    func scheduleBinaryRefresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.refreshBinaries()
            }
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func refreshBinaries() {
        let extras = extraPathText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        extraPathWarnings = extras.compactMap { line in
            BinaryLocator.sanitizeExtraRoot(line) == nil ? line : nil
        }
        var next: [ToolKind: [LocatedBinary]] = [:]
        for tool in ToolKind.allCases {
            var locator = BinaryLocator()
            locator.extraRoots = extras
            locator.preferSystemFirst = tool.prefersSystemBinary
            next[tool] = locator.locate(tool.binaryNames)
        }
        located = next
        UserDefaults.standard.set(extraPathText, forKey: extraPathsKey)
    }

    func runSelected() {
        let tool = selectedTool
        let session = session(tool)
        let binaries = binaries(for: tool)
        guard !binaries.isEmpty else {
            session.presentError("\(tool.title) was not found on PATH or in the usual Homebrew locations.")
            return
        }
        do {
            let spec = try makeSpec(for: tool, binaries: binaries)
            if let problem = spec.preflightError() {
                session.presentError(problem)
                return
            }
            let preview = tool == .curl ? curl.preview(from: spec) : spec.preview
            session.start(spec, preview: preview)
        } catch {
            session.presentError(error.localizedDescription)
        }
    }

    func stopSelected() {
        currentSession.stop()
    }

    private func makeSpec(for tool: ToolKind, binaries: [LocatedBinary]) throws -> CommandSpec {
        switch tool {
        case .ping: return try ping.build(binaries: binaries)
        case .dig: return try dig.build(binaries: binaries)
        case .traceroute: return try traceroute.build(binaries: binaries)
        case .nmap: return try nmap.build(binaries: binaries)
        case .netcat: return try netcat.build(binaries: binaries)
        case .tcpdump: return try tcpdump.build(binaries: binaries)
        case .whois: return try whois.build(binaries: binaries)
        case .curl: return try curl.build(binaries: binaries)
        }
    }
}
