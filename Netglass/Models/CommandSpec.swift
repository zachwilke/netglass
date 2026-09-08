import Foundation

struct CommandSpec: Sendable, Equatable {
    var executable: URL
    var arguments: [String]
    var workingDirectory: URL?
    var stdinText: String?

    var argv: [String] {
        [executable.path] + arguments
    }

    var preview: String {
        argv.map(Self.quoteForDisplay).joined(separator: " ")
    }

    func preflightError() -> String? {
        let url = executable.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: url.path)
        else {
            return "Executable is missing or not a regular file."
        }
        if BinaryLocator.isRejectedLocation(url.path) {
            return "Refusing to run a binary from a temporary or world-writable location."
        }
        return nil
    }

    var redactedPreview: String {
        preview
    }

    static func quoteForDisplay(_ token: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./:@+=,~%"))
        if !token.isEmpty, token.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            return token
        }
        let escaped = token.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}

struct LocatedBinary: Hashable, Sendable, Identifiable {
    let name: String
    let url: URL

    var id: String { url.path }
    var path: String { url.path }
}

struct OutputLine: Identifiable, Hashable, Sendable {
    enum Stream: String, Sendable {
        case stdout
        case stderr
        case system
    }

    let id: UInt64
    let text: String
    let stream: Stream
    let at: Date

    init(id: UInt64, text: String, stream: Stream, at: Date = Date()) {
        self.id = id
        self.text = text
        self.stream = stream
        self.at = at
    }
}

enum RunState: Equatable, Sendable {
    case idle
    case running(pid: Int32)
    case succeeded(code: Int32)
    case failed(code: Int32)
    case cancelled
    case errored(String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .running: return "Running"
        case .succeeded(let code): return "Finished · \(code)"
        case .failed(let code): return "Failed · \(code)"
        case .cancelled: return "Stopped"
        case .errored: return "Error"
        }
    }

    var exitCode: Int32? {
        switch self {
        case .succeeded(let code), .failed(let code):
            return code
        default:
            return nil
        }
    }
}
