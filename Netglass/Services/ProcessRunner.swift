import Foundation
#if canImport(Darwin)
import Darwin
#endif

enum ProcessEvent: Sendable {
    case started(pid: Int32)
    case lines([StreamedLine])
    case exited(code: Int32)
    case failed(String)
}

final class ProcessRunner: @unchecked Sendable {
    static let coalesceInterval: TimeInterval = 0.033
    static let coalesceLineLimit = 48

    private let queue = DispatchQueue(label: "dev.pinefall.netglass.process")
    private var process: Process?
    private var groupPID: Int32 = 0
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var pending: [StreamedLine] = []
    private var flushWork: DispatchWorkItem?
    private var onEvent: (@Sendable (ProcessEvent) -> Void)?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var stdinHandle: FileHandle?

    var isRunning: Bool {
        queue.sync { process?.isRunning == true }
    }

    func start(spec: CommandSpec, onEvent: @escaping @Sendable (ProcessEvent) -> Void) {
        queue.async { [weak self] in
            self?._start(spec: spec, onEvent: onEvent)
        }
    }

    func cancel() {
        queue.async { [weak self] in
            guard let self else { return }
            guard let process = self.process, process.isRunning else { return }
            let pid = self.groupPID != 0 ? self.groupPID : process.processIdentifier
#if canImport(Darwin)
            _ = killpg(pid, SIGTERM)
#endif
            process.terminate()
            self.queue.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                guard let self, let current = self.process, current.isRunning else { return }
#if canImport(Darwin)
                _ = killpg(pid, SIGKILL)
#endif
                current.terminate()
            }
        }
    }

    private func _start(spec: CommandSpec, onEvent: @escaping @Sendable (ProcessEvent) -> Void) {
        if process?.isRunning == true {
            onEvent(.failed("A process is already running for this tool."))
            return
        }

        if let problem = spec.preflightError() {
            onEvent(.failed(problem))
            return
        }

        let process = Process()
        process.executableURL = spec.executable
        process.arguments = spec.arguments
        process.currentDirectoryURL = spec.workingDirectory ?? FileManager.default.temporaryDirectory
        process.environment = Self.diagnosticEnvironment()

        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin

        stdoutBuffer = Data()
        stderrBuffer = Data()
        pending = []
        flushWork?.cancel()
        flushWork = nil
        self.onEvent = onEvent
        stdoutHandle = stdout.fileHandleForReading
        stderrHandle = stderr.fileHandleForReading
        stdinHandle = stdin.fileHandleForWriting

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.queue.async {
                self?.consume(data, stream: .stdout)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.queue.async {
                self?.consume(data, stream: .stderr)
            }
        }

        process.terminationHandler = { [weak self] finished in
            self?.queue.async {
                self?.finish(status: finished.terminationStatus)
            }
        }

        do {
            try process.run()
            self.process = process
            let pid = process.processIdentifier
#if canImport(Darwin)
            _ = setpgid(pid, pid)
#endif
            groupPID = pid
            onEvent(.started(pid: pid))
            if let stdinText = spec.stdinText, let data = stdinText.data(using: .utf8) {
                try? stdin.fileHandleForWriting.write(contentsOf: data)
            }
            try? stdin.fileHandleForWriting.close()
            stdinHandle = nil
        } catch {
            teardownIO()
            onEvent(.failed(error.localizedDescription))
            self.process = nil
            self.onEvent = nil
        }
    }

    private func consume(_ data: Data, stream: OutputLine.Stream) {
        guard !data.isEmpty else { return }
        switch stream {
        case .stdout:
            extractLines(from: data, into: &stdoutBuffer, stream: .stdout)
        case .stderr:
            extractLines(from: data, into: &stderrBuffer, stream: .stderr)
        case .system:
            break
        }
    }

    private func extractLines(from data: Data, into buffer: inout Data, stream: OutputLine.Stream) {
        buffer.append(data)
        while let range = buffer.range(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex...range.lowerBound)
            enqueue(stream: stream, data: lineData)
        }
        if buffer.count > ConsoleText.maxPartialBytes {
            enqueue(stream: stream, data: buffer)
            buffer.removeAll(keepingCapacity: true)
        }
    }

    private func enqueue(stream: OutputLine.Stream, data: Data) {
        let line = ConsoleText.sanitize(decode(data).trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
        pending.append(StreamedLine(stream: stream, text: line))
        if pending.count >= Self.coalesceLineLimit {
            flushPending()
            return
        }
        if flushWork == nil {
            let work = DispatchWorkItem { [weak self] in
                self?.flushWork = nil
                self?.flushPending()
            }
            flushWork = work
            queue.asyncAfter(deadline: .now() + Self.coalesceInterval, execute: work)
        }
    }

    private func flushPending() {
        flushWork?.cancel()
        flushWork = nil
        guard !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        onEvent?(.lines(batch))
    }

    private func finish(status: Int32) {
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        if !stdoutBuffer.isEmpty {
            enqueue(stream: .stdout, data: stdoutBuffer)
            stdoutBuffer.removeAll()
        }
        if !stderrBuffer.isEmpty {
            enqueue(stream: .stderr, data: stderrBuffer)
            stderrBuffer.removeAll()
        }
        flushPending()
        onEvent?(.exited(code: status))
        teardownIO()
        process = nil
        groupPID = 0
        onEvent = nil
    }

    private func teardownIO() {
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        try? stdoutHandle?.close()
        try? stderrHandle?.close()
        try? stdinHandle?.close()
        stdoutHandle = nil
        stderrHandle = nil
        stdinHandle = nil
    }

    private func decode(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(decoding: data, as: UTF8.self)
    }

    static func diagnosticEnvironment() -> [String: String] {
        let source = ProcessInfo.processInfo.environment
        var environment: [String: String] = [:]
        for key in ["HOME", "TMPDIR", "USER", "LOGNAME", "LANG", "LC_CTYPE"] {
            if let value = source[key], !value.isEmpty {
                environment[key] = value
            }
        }
        environment["LC_ALL"] = "C"
        environment["PATH"] = trustedPATH()
        return environment
    }

    static func trustedPATH() -> String {
        (
            BinaryLocator.systemRoots
                + BinaryLocator.brewRoots
                + ["/usr/sbin", "/usr/bin", "/sbin", "/bin"]
        )
        .uniqued()
        .joined(separator: ":")
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
