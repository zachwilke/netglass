import Foundation
#if canImport(Darwin)
import Darwin
#endif

struct BinaryLocator: Sendable {
    static let systemRoots = [
        "/usr/sbin",
        "/usr/bin",
        "/sbin",
        "/bin"
    ]

    static let brewRoots = [
        "/opt/homebrew/sbin",
        "/opt/homebrew/bin",
        "/usr/local/sbin",
        "/usr/local/bin",
        "/opt/local/sbin",
        "/opt/local/bin"
    ]

    var extraRoots: [String] = []
    var preferSystemFirst = true

    func locate(_ names: [String]) -> [LocatedBinary] {
        var found: [LocatedBinary] = []
        var seen = Set<String>()
        for directory in searchDirectories() {
            if Self.isRejectedLocation(directory) { continue }
            for name in names {
                let url = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(name)
                guard isAcceptableBinary(url) else { continue }
                let standardized = url.standardizedFileURL
                if seen.insert(standardized.path).inserted {
                    found.append(LocatedBinary(name: name, url: standardized))
                }
            }
        }
        return found
    }

    func locate(name: String) -> LocatedBinary? {
        locate([name]).first
    }

    static func sanitizeExtraRoot(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.contains("\0") { return nil }
        if trimmed.contains("..") { return nil }
        guard trimmed.hasPrefix("/") else { return nil }
        let standardized = URL(fileURLWithPath: trimmed).standardizedFileURL.path
        if isRejectedLocation(standardized) { return nil }
        return standardized
    }

    static func isRejectedLocation(_ path: String) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let blockedExact = ["/tmp", "/var/tmp", "/private/tmp", "/private/var/tmp"]
        if blockedExact.contains(standardized) { return true }
        let blockedPrefixes = ["/tmp/", "/var/tmp/", "/private/tmp/", "/private/var/tmp/"]
        if blockedPrefixes.contains(where: { standardized.hasPrefix($0) }) { return true }
        return isWorldWritable(standardized)
    }

    private func searchDirectories() -> [String] {
        let preferred = preferSystemFirst
            ? Self.systemRoots + Self.brewRoots
            : Self.brewRoots + Self.systemRoots
        let extras = extraRoots.compactMap(Self.sanitizeExtraRoot)
        var directories = preferred + extras
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for item in path.split(separator: ":").map(String.init) {
                if let sanitized = Self.sanitizeExtraRoot(item) {
                    directories.append(sanitized)
                }
            }
        }
        var unique: [String] = []
        var seen = Set<String>()
        for directory in directories where seen.insert(directory).inserted {
            unique.append(directory)
        }
        return unique
    }

    private func isAcceptableBinary(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: url.path)
        else { return false }
        let resolved = url.resolvingSymlinksInPath()
        if Self.isRejectedLocation(resolved.path) { return false }
        if Self.isWorldWritable(url.path) || Self.isWorldWritable(resolved.path) { return false }
        return true
    }

    static func isWorldWritable(_ path: String) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let posix = attributes[.posixPermissions] as? NSNumber
        else { return false }
        return (posix.uint16Value & 0o002) != 0
    }
}

enum InterfaceEnumerator {
    static func list() -> [String] {
#if canImport(Darwin)
        if let names = darwinInterfaces(), !names.isEmpty {
            return names
        }
#endif
        return ["any", "en0", "lo0"]
    }

#if canImport(Darwin)
    private static func darwinInterfaces() -> [String]? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var names: [String] = []
        var pointer = ifaddr
        while let current = pointer {
            let name = String(cString: current.pointee.ifa_name)
            if !name.isEmpty, !names.contains(name) {
                names.append(name)
            }
            pointer = current.pointee.ifa_next
        }
        names.sort()
        names.insert("any", at: 0)
        if !names.contains("en0") { names.append("en0") }
        if !names.contains("lo0") { names.append("lo0") }
        return names
    }
#endif
}
