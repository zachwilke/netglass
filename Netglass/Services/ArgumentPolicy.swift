import Foundation

enum ArgumentPolicy: Sendable {
    static let nmapAllowedFlags: Set<String> = [
        "-Pn", "-n", "-v", "-vv", "-F", "-sT", "-sV", "-sn",
        "--reason", "--open", "-T2", "-T3", "-T4"
    ]

    static let nmapBlockedPrefixes = [
        "--script", "-oN", "-oX", "-oG", "-oA", "-oS", "-iL", "--resume",
        "-b", "--datadir", "--privileged", "--unprivileged", "-sS", "-sA",
        "-sW", "-sM", "-sO", "-sY", "-sZ", "--ftp-bounce", "--spoof",
        "-D", "-S", "--source-port", "--proxies", "--disable-arp-ping",
        "-A", "-O", "-sU", "-p-", "--top-ports="
    ]

    static let maxTopPorts = 100
    static let maxExplicitPorts = 64
    static let maxRangeSpan = 256

    static func nmapExtras(_ raw: String) throws -> [String] {
        let tokens = tokenize(raw)
        if tokens.count > 12 { throw ValidationError.tooManyExtraArguments }
        var result: [String] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token.count > 64 { throw ValidationError.disallowedArgument(token) }
            if isBlocked(token) {
                throw ValidationError.disallowedArgument(token)
            }
            if token == "-p-" || token.hasPrefix("-p-") {
                throw ValidationError.disallowedArgument(token)
            }
            if nmapAllowedFlags.contains(token) {
                result.append(token)
                index += 1
                continue
            }
            if token == "-p" || token == "--top-ports" {
                guard index + 1 < tokens.count else { throw ValidationError.disallowedArgument(token) }
                let value = tokens[index + 1]
                if token == "--top-ports" {
                    try validateTopPorts(value)
                } else {
                    try validatePortSpec(value)
                }
                result.append(contentsOf: [token, value])
                index += 2
                continue
            }
            if token.hasPrefix("-p"), token.count > 2 {
                try validatePortSpec(String(token.dropFirst(2)))
                result.append(token)
                index += 1
                continue
            }
            throw ValidationError.disallowedArgument(token)
        }
        return result
    }

    static func isBlocked(_ token: String) -> Bool {
        nmapBlockedPrefixes.contains { prefix in
            if token == prefix || token.hasPrefix(prefix + "=") { return true }
            if prefix.hasPrefix("--") { return token.hasPrefix(prefix) }
            if prefix.count == 2, token.hasPrefix(prefix), token != prefix {
                return !nmapAllowedFlags.contains(token)
            }
            return false
        }
    }

    static func tokenize(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    static func validateTopPorts(_ raw: String) throws {
        guard let value = Int(raw), (1...maxTopPorts).contains(value) else {
            throw ValidationError.disallowedArgument(raw)
        }
    }

    static func validatePortSpec(_ raw: String) throws {
        if raw == "-" || raw.hasPrefix("-") { throw ValidationError.disallowedArgument(raw) }
        let allowed = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ",-"))
        guard !raw.isEmpty, raw.count <= 80, raw.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw ValidationError.disallowedArgument(raw)
        }
        if raw.hasPrefix(",") || raw.hasSuffix(",") || raw.contains(",,") || raw.contains("--") {
            throw ValidationError.disallowedArgument(raw)
        }
        var total = 0
        for part in raw.split(separator: ",") {
            let piece = String(part)
            if piece.isEmpty { throw ValidationError.disallowedArgument(raw) }
            if let dash = piece.firstIndex(of: "-") {
                let startText = String(piece[..<dash])
                let endText = String(piece[piece.index(after: dash)...])
                guard let start = Int(startText), let end = Int(endText),
                      (1...65535).contains(start), (1...65535).contains(end),
                      start <= end
                else {
                    throw ValidationError.disallowedArgument(raw)
                }
                let span = end - start + 1
                if span > maxRangeSpan { throw ValidationError.disallowedArgument(raw) }
                total += span
            } else {
                guard let port = Int(piece), (1...65535).contains(port) else {
                    throw ValidationError.disallowedArgument(raw)
                }
                total += 1
            }
            if total > maxExplicitPorts { throw ValidationError.disallowedArgument(raw) }
        }
    }
}
