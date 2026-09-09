import Foundation
import Observation

@MainActor
@Observable
final class ToolSession {
    static let maxLines = 5_000

    let tool: ToolKind
    var lines: [OutputLine] = []
    var state: RunState = .idle
    var lastPreview = ""
    var startedAt: Date?
    var finishedAt: Date?
    var autoScroll = true
    var truncated = false
    var sawPrivilegeError = false
    var cancelRequested = false
    var exportNotice: String?

    @ObservationIgnored
    private let runner = ProcessRunner()
    @ObservationIgnored
    private var nextLineID: UInt64 = 1
    @ObservationIgnored
    private var noticeWork: DispatchWorkItem?

    init(tool: ToolKind) {
        self.tool = tool
    }

    var isRunning: Bool { state.isRunning }

    func start(_ spec: CommandSpec, preview: String? = nil) {
        guard !isRunning else { return }
        lastPreview = preview ?? spec.preview
        startedAt = Date()
        finishedAt = nil
        cancelRequested = false
        sawPrivilegeError = false
        appendNotice("Started \(lastPreview)")
        runner.start(spec: spec) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        cancelRequested = true
        appendNotice("Stopping…")
        runner.cancel()
    }

    func clear() {
        lines.removeAll(keepingCapacity: true)
        truncated = false
        if !isRunning {
            state = .idle
            sawPrivilegeError = false
        }
    }

    func presentError(_ message: String) {
        state = .errored(message)
        appendSystem(message)
    }

    func transcript() -> String {
        lines.map(\.text).joined(separator: "\n")
    }

    func makeSnapshot(now: Date = Date(), hostOSNote: String = ReportSnapshot.defaultHostOSNote) -> ReportSnapshot {
        ReportSnapshot(
            tool: tool,
            commandPreview: lastPreview,
            startedAt: startedAt,
            capturedAt: now,
            finishedAt: finishedAt,
            status: state.label,
            exitCode: state.exitCode,
            truncated: truncated,
            hostOSNote: hostOSNote,
            lines: lines.map { ReportLine(text: $0.text, stream: $0.stream.rawValue) }
        )
    }

    func flashExportNotice(_ text: String) {
        exportNotice = text
        noticeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                if self?.exportNotice == text {
                    self?.exportNotice = nil
                }
            }
        }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    private func handle(_ event: ProcessEvent) {
        switch event {
        case .started(let pid):
            state = .running(pid: pid)
        case .lines(let batch):
            append(batch)
        case .exited(let code):
            finishedAt = Date()
            if cancelRequested {
                state = .cancelled
                appendNotice("Stopped.")
            } else if code == 0 {
                state = .succeeded(code: code)
                appendNotice("Finished with status 0.")
            } else {
                state = .failed(code: code)
                appendNotice("Finished with status \(code).")
            }
            cancelRequested = false
        case .failed(let message):
            finishedAt = Date()
            state = .errored(message)
            appendSystem(message)
        }
    }

    private func appendSystem(_ text: String) {
        append([StreamedLine(stream: .system, text: text)])
    }

    private func appendNotice(_ text: String) {
        append([StreamedLine(stream: .notice, text: text)])
    }

    private func append(_ batch: [StreamedLine]) {
        guard !batch.isEmpty else { return }
        let now = Date()
        var next = lines
        next.reserveCapacity(min(Self.maxLines, next.count + batch.count))
        for item in batch {
            if item.stream == .stderr, PrivilegeHints.looksLikePrivilegeError(item.text) {
                sawPrivilegeError = true
            }
            next.append(OutputLine(id: nextLineID, text: item.text, stream: item.stream, at: now))
            nextLineID += 1
        }
        if next.count > Self.maxLines {
            next = Array(next.suffix(Self.maxLines))
            truncated = true
        }
        lines = next
    }
}

enum PrivilegeHints {
    static func looksLikePrivilegeError(_ text: String) -> Bool {
        let hay = text.lowercased()
        return hay.contains("permission denied")
            || hay.contains("operation not permitted")
            || hay.contains("you don't have permission")
            || hay.contains("requires root")
            || hay.contains("are you root")
            || hay.contains("biocsetif")
            || hay.contains("not enough privileges")
            || hay.contains("couldn't get unprivileged")
            || hay.contains("socket: operation not permitted")
            || hay.contains("you need to be root")
    }
}
