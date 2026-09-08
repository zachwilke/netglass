import Foundation

enum ValidationError: LocalizedError, Equatable, Sendable {
    case empty(field: String)
    case invalidHost(String)
    case invalidPort
    case invalidCount(field: String)
    case invalidInterval
    case invalidInterface
    case invalidFilter
    case invalidURL
    case credentialsInURL
    case disallowedArgument(String)
    case tooManyExtraArguments
    case massScanPrefix
    case invalidHeader
    case secretHeader(String)
    case invalidRecordType
    case payloadTooLarge
    case tooManyHeaders
    case unsafeWritePath

    var errorDescription: String? {
        switch self {
        case .empty(let field):
            return "\(field) is required."
        case .invalidHost(let value):
            return "“\(value)” is not a safe host, address, or name."
        case .invalidPort:
            return "Port must be an integer from 1 to 65535."
        case .invalidCount(let field):
            return "\(field) is out of range."
        case .invalidInterval:
            return "Interval must be between 0.2 and 10 seconds. Values under 1s usually need root on macOS."
        case .invalidInterface:
            return "Interface must look like en0, lo0, bridge0, or any."
        case .invalidFilter:
            return "Capture filter contains characters Netglass will not pass through."
        case .invalidURL:
            return "URL must be http or https with a host, and no spaces."
        case .credentialsInURL:
            return "Leave usernames and passwords out of the URL. Netglass will not put credentials on the process list."
        case .disallowedArgument(let token):
            return "Argument “\(token)” is blocked. Netglass only forwards a small, tame flag set."
        case .tooManyExtraArguments:
            return "Too many extra arguments. Keep the advanced line short."
        case .massScanPrefix:
            return "That prefix is too wide. Netglass allows at most a /24 IPv4 or /120 IPv6 scan target."
        case .invalidHeader:
            return "Headers must look like Name: value, one per line, without control characters."
        case .secretHeader(let name):
            return "Refusing to send “\(name)” — it would appear on the local process list. Use Terminal for authenticated calls."
        case .invalidRecordType:
            return "Choose a DNS record type from the list."
        case .payloadTooLarge:
            return "Payload is limited to 4 KB so this stays a diagnostic send, not a dump tool."
        case .tooManyHeaders:
            return "Too many extra headers. Netglass accepts at most 16."
        case .unsafeWritePath:
            return "That output path is not a user-chosen capture location Netglass will write to."
        }
    }
}

enum InputValidator: Sendable {
    private static let shellMeta = CharacterSet(charactersIn: " \t\n\r;|&$<>`(){}[]!*?\"'\\,#")
    private static let asciiLetters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    private static let hostExtras = CharacterSet(charactersIn: ".-_")
    private static let ipv6Extras = CharacterSet(charactersIn: ":")
    private static let allowedRecordTypes: Set<String> = [
        "A", "AAAA", "MX", "NS", "TXT", "CNAME", "SOA", "PTR", "SRV", "CAA", "ANY"
    ]

    static func trimmed(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func host(_ raw: String, field: String = "Host") throws -> String {
        let value = trimmed(raw)
        if value.isEmpty { throw ValidationError.empty(field: field) }
        if value.count > 253 { throw ValidationError.invalidHost(value) }
        if value.hasPrefix("-") { throw ValidationError.invalidHost(value) }

        if value.hasPrefix("["), value.hasSuffix("]"), value.count >= 4 {
            let inner = String(value.dropFirst().dropLast())
            return try ipv6(inner, original: value)
        }

        if value.contains(":"), looksLikeIPv6(value) {
            return try ipv6(value, original: value)
        }

        if isIPv4(value) { return value }
        return try hostname(value)
    }

    static func scanTarget(_ raw: String) throws -> String {
        let value = trimmed(raw)
        if value.isEmpty { throw ValidationError.empty(field: "Target") }
        if let slash = value.lastIndex(of: "/") {
            let address = String(value[..<slash])
            let prefixText = String(value[value.index(after: slash)...])
            guard let prefix = Int(prefixText) else { throw ValidationError.invalidHost(value) }
            if isIPv4(address) {
                guard prefix >= 24, prefix <= 32 else { throw ValidationError.massScanPrefix }
                return "\(address)/\(prefix)"
            }
            if looksLikeIPv6(address) {
                guard prefix >= 120, prefix <= 128 else { throw ValidationError.massScanPrefix }
                _ = try ipv6(address, original: value)
                return "\(address)/\(prefix)"
            }
            throw ValidationError.invalidHost(value)
        }
        return try host(value, field: "Target")
    }

    static func port(_ raw: String) throws -> Int {
        let value = trimmed(raw)
        if value.isEmpty { throw ValidationError.empty(field: "Port") }
        guard let port = Int(value), (1...65535).contains(port) else {
            throw ValidationError.invalidPort
        }
        return port
    }

    static func count(_ value: Int, field: String, range: ClosedRange<Int>) throws -> Int {
        guard range.contains(value) else { throw ValidationError.invalidCount(field: field) }
        return value
    }

    static func interval(_ value: Double) throws -> Double {
        guard value >= 0.2, value <= 10 else { throw ValidationError.invalidInterval }
        return value
    }

    static func networkInterface(_ raw: String) throws -> String {
        let value = trimmed(raw)
        if value.isEmpty { throw ValidationError.empty(field: "Interface") }
        if value == "any" { return value }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard let first = value.first, first.isLetter,
              value.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              value.count <= 32
        else {
            throw ValidationError.invalidInterface
        }
        return value
    }

    static func bpfFilter(_ raw: String) throws -> String? {
        let value = trimmed(raw)
        if value.isEmpty { return nil }
        if value.count > 200 { throw ValidationError.invalidFilter }
        if value.hasPrefix("-") { throw ValidationError.invalidFilter }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " \t._-:/()"))
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw ValidationError.invalidFilter
        }
        let keywords = value.split(whereSeparator: { $0.isWhitespace })
        let allowedWords: Set<String> = [
            "and", "or", "not", "host", "port", "net", "src", "dst", "tcp", "udp",
            "icmp", "icmp6", "arp", "ether", "portrange", "len", "greater", "less",
            "proto", "gateway", "broadcast", "multicast", "inbound", "outbound"
        ]
        for word in keywords {
            let token = String(word)
            if token.hasPrefix("-") { throw ValidationError.invalidFilter }
            let lowered = token.lowercased()
            if lowered.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":" }) { continue }
            if allowedWords.contains(lowered) { continue }
            if lowered.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }) {
                continue
            }
            throw ValidationError.invalidFilter
        }
        return value
    }

    static func httpURL(_ raw: String) throws -> String {
        let value = trimmed(raw)
        if value.isEmpty { throw ValidationError.empty(field: "URL") }
        if value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0 == " " }) {
            throw ValidationError.invalidURL
        }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty
        else {
            throw ValidationError.invalidURL
        }
        if url.user != nil || url.password != nil {
            throw ValidationError.credentialsInURL
        }
        if value.count > 2_048 { throw ValidationError.invalidURL }
        _ = try self.host(host, field: "URL host")
        return value
    }

    static func recordType(_ raw: String) throws -> String {
        let value = trimmed(raw).uppercased()
        guard allowedRecordTypes.contains(value) else { throw ValidationError.invalidRecordType }
        return value
    }

    static func nameserver(_ raw: String) throws -> String? {
        let value = trimmed(raw)
        if value.isEmpty { return nil }
        if value.hasPrefix("@") {
            return try host(String(value.dropFirst()), field: "Nameserver")
        }
        return try host(value, field: "Nameserver")
    }

    static func whoisQuery(_ raw: String) throws -> String {
        let value = trimmed(raw)
        if value.isEmpty { throw ValidationError.empty(field: "Query") }
        if value.count > 253 { throw ValidationError.invalidHost(value) }
        if value.unicodeScalars.contains(where: { shellMeta.contains($0) }) {
            throw ValidationError.invalidHost(value)
        }
        if value.hasPrefix("-") { throw ValidationError.invalidHost(value) }
        return value
    }

    static func payload(_ raw: String) throws -> String? {
        if raw.isEmpty { return nil }
        guard raw.utf8.count <= 4096 else { throw ValidationError.payloadTooLarge }
        if raw.contains("\0") { throw ValidationError.payloadTooLarge }
        return raw
    }

    static let rejectedHeaderNames: Set<String> = [
        "authorization", "proxy-authorization", "cookie", "set-cookie",
        "x-api-key", "x-auth-token", "x-amz-security-token"
    ]

    static func httpHeaders(_ raw: String) throws -> [String] {
        let lines = raw.split(whereSeparator: \.isNewline).map { trimmed(String($0)) }.filter { !$0.isEmpty }
        if lines.count > 16 { throw ValidationError.tooManyHeaders }
        var headers: [String] = []
        for line in lines {
            if line.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
                throw ValidationError.invalidHeader
            }
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw ValidationError.invalidHeader }
            let name = trimmed(String(parts[0]))
            let value = trimmed(String(parts[1]))
            guard !name.isEmpty, name.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-") }) else {
                throw ValidationError.invalidHeader
            }
            guard !value.isEmpty, value.count <= 512 else { throw ValidationError.invalidHeader }
            if rejectedHeaderNames.contains(name.lowercased()) {
                throw ValidationError.secretHeader(name)
            }
            headers.append("\(name): \(value)")
        }
        return headers
    }

    static func redactHeaderValues(_ headers: [String]) -> [String] {
        headers.map { header in
            let parts = header.split(separator: ":", maxSplits: 1)
            guard let name = parts.first else { return header }
            if rejectedHeaderNames.contains(name.lowercased()) {
                return "\(name): ••••"
            }
            return header
        }
    }

    static func userWritePath(_ url: URL) throws -> URL {
        let resolved = url.resolvingSymlinksInPath()
        let path = resolved.path
        if path.isEmpty { throw ValidationError.unsafeWritePath }
        if BinaryLocator.isRejectedLocation(path) { throw ValidationError.unsafeWritePath }
        let blockedPrefixes = [
            "/etc", "/private/etc", "/usr", "/bin", "/sbin", "/System",
            "/Library", "/private/var/root", "/var/root"
        ]
        for prefix in blockedPrefixes {
            if path == prefix || path.hasPrefix(prefix + "/") {
                throw ValidationError.unsafeWritePath
            }
        }
        return resolved
    }

    private static func hostname(_ value: String) throws -> String {
        if value.unicodeScalars.contains(where: { $0 > Unicode.Scalar(127) }) {
            throw ValidationError.invalidHost(value)
        }
        if value.unicodeScalars.contains(where: { shellMeta.contains($0) && $0 != "." && $0 != "-" && $0 != "_" }) {
            throw ValidationError.invalidHost(value)
        }
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty, labels.count <= 127 else { throw ValidationError.invalidHost(value) }
        for label in labels {
            if label.isEmpty { throw ValidationError.invalidHost(value) }
            if label.count > 63 { throw ValidationError.invalidHost(value) }
            if label.hasPrefix("-") || label.hasSuffix("-") { throw ValidationError.invalidHost(value) }
            let allowed = CharacterSet.alphanumerics.union(hostExtras)
            guard label.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                throw ValidationError.invalidHost(value)
            }
        }
        return value
    }

    private static func ipv6(_ value: String, original: String) throws -> String {
        var address = value
        var zone: String?
        if let percent = value.firstIndex(of: "%") {
            zone = String(value[value.index(after: percent)...])
            address = String(value[..<percent])
            if let zone {
                do {
                    _ = try networkInterface(zone)
                } catch {
                    throw ValidationError.invalidHost(original)
                }
            }
        }
        if address.unicodeScalars.contains(where: { !(CharacterSet.hexadecimalDigits.contains($0) || $0 == ":") }) {
            throw ValidationError.invalidHost(original)
        }
        if address.contains(":::"), address != "::" {
            throw ValidationError.invalidHost(original)
        }
        let halves = address.split(separator: "::", omittingEmptySubsequences: false)
        if halves.count > 2 { throw ValidationError.invalidHost(original) }
        if let zone {
            return "\(address)%\(zone)"
        }
        return address
    }

    private static func isIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let number = Int(part), (0...255).contains(number), String(number) == part else {
                return false
            }
            return true
        }
    }

    private static func looksLikeIPv6(_ value: String) -> Bool {
        guard value.contains(":") else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.hexadecimalDigits.contains($0) || $0 == ":" || $0 == "%"
        }
    }
}

private extension CharacterSet {
    static let hexadecimalDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
}
