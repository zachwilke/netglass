import Foundation
import Observation

enum IPFamily: String, CaseIterable, Identifiable, Sendable {
    case system
    case v4
    case v6

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Auto"
        case .v4: return "IPv4"
        case .v6: return "IPv6"
        }
    }
}

@MainActor
@Observable
final class PingForm {
    var host = "1.1.1.1"
    var count = 5
    var interval = 1.0
    var family: IPFamily = .system
    var continuous = false
    var numeric = false

    func build(binaries: [LocatedBinary]) throws -> CommandSpec {
        let host = try InputValidator.host(self.host)
        let interval = try InputValidator.interval(self.interval)
        if !continuous {
            _ = try InputValidator.count(count, field: "Count", range: 1...10_000)
        }

        let v6 = family == .v6
        let name = v6 ? "ping6" : "ping"
        guard let binary = binaries.first(where: { $0.name == name }) ?? binaries.first(where: { $0.name == "ping" }) else {
            throw ValidationError.empty(field: "ping")
        }

        var arguments: [String] = []
        if !continuous {
            arguments += ["-c", String(count)]
        }
        arguments += ["-i", formatInterval(interval)]
        if numeric { arguments.append("-n") }
        if family == .v4, binary.name == "ping" {
            // Apple's ping selects IPv4 when given an IPv4 target; keep host-only for portability.
        }
        arguments.append(host)
        return CommandSpec(executable: binary.url, arguments: arguments)
    }

    private func formatInterval(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.1f", value)
    }
}

enum DigEngine: String, CaseIterable, Identifiable, Sendable {
    case dig
    case host
    case nslookup

    var id: String { rawValue }
    var title: String { rawValue }
}

@MainActor
@Observable
final class DigForm {
    var name = "example.com"
    var recordType = "A"
    var nameserver = ""
    var engine: DigEngine = .dig
    var shortOutput = true
    var trace = false

    func build(binaries: [LocatedBinary]) throws -> CommandSpec {
        let name = try InputValidator.host(self.name, field: "Name")
        let type = try InputValidator.recordType(recordType)
        let server = try InputValidator.nameserver(nameserver)

        let preferred = binaries.first(where: { $0.name == engine.rawValue }) ?? binaries.first
        guard let binary = preferred else { throw ValidationError.empty(field: "resolver") }

        switch binary.name {
        case "host":
            var arguments = ["-t", type]
            arguments.append(name)
            if let server { arguments.append(server) }
            return CommandSpec(executable: binary.url, arguments: arguments)
        case "nslookup":
            var arguments = ["-type=\(type)", name]
            if let server { arguments.append(server) }
            return CommandSpec(executable: binary.url, arguments: arguments)
        default:
            var arguments: [String] = []
            if let server { arguments.append("@\(server)") }
            arguments += [name, type]
            if shortOutput { arguments.append("+short") }
            if trace { arguments.append("+trace") }
            arguments += ["+time=5", "+tries=2"]
            return CommandSpec(executable: binary.url, arguments: arguments)
        }
    }
}

@MainActor
@Observable
final class TracerouteForm {
    var host = "1.1.1.1"
    var family: IPFamily = .system
    var maxHops = 30
    var queries = 1
    var numeric = true
    var icmp = false

    func build(binaries: [LocatedBinary]) throws -> CommandSpec {
        let host = try InputValidator.host(self.host)
        _ = try InputValidator.count(maxHops, field: "Max hops", range: 1...64)
        _ = try InputValidator.count(queries, field: "Queries", range: 1...3)

        let prefer6 = family == .v6
        let binary = prefer6
            ? (binaries.first(where: { $0.name == "traceroute6" }) ?? binaries.first)
            : (binaries.first(where: { $0.name == "traceroute" }) ?? binaries.first)
        guard let binary else { throw ValidationError.empty(field: "traceroute") }

        var arguments: [String] = ["-m", String(maxHops), "-q", String(queries)]
        if numeric { arguments.append("-n") }
        if icmp, binary.name == "traceroute" { arguments.append("-I") }
        if family == .v6, binary.name == "traceroute" { arguments.append("-6") }
        arguments.append(host)
        return CommandSpec(executable: binary.url, arguments: arguments)
    }
}

enum NmapPreset: String, CaseIterable, Identifiable, Sendable {
    case hostUp
    case commonPorts
    case webPorts
    case mailPorts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hostUp: return "Host up?"
        case .commonPorts: return "Top 20 ports"
        case .webPorts: return "Web ports"
        case .mailPorts: return "Mail / DNS"
        }
    }

    var detail: String {
        switch self {
        case .hostUp: return "No port scan. Asks whether the host answers."
        case .commonPorts: return "TCP connect, polite timing, twenty common ports."
        case .webPorts: return "80, 443, 8080, 8443 with TCP connect."
        case .mailPorts: return "25, 53, 110, 143, 587, 993."
        }
    }

    func arguments() -> [String] {
        switch self {
        case .hostUp:
            return ["-sn"]
        case .commonPorts:
            return ["-sT", "-T3", "--top-ports", "20"]
        case .webPorts:
            return ["-sT", "-T3", "-p", "80,443,8080,8443"]
        case .mailPorts:
            return ["-sT", "-T3", "-p", "25,53,110,143,587,993"]
        }
    }
}

@MainActor
@Observable
final class NmapForm {
    var target = "127.0.0.1"
    var preset: NmapPreset = .hostUp
    var skipDiscovery = false
    var extra = ""

    func build(binaries: [LocatedBinary]) throws -> CommandSpec {
        let target = try InputValidator.scanTarget(self.target)
        guard let binary = binaries.first else { throw ValidationError.empty(field: "nmap") }
        var arguments = preset.arguments()
        if skipDiscovery, preset != .hostUp {
            arguments.append("-Pn")
        }
        arguments += try ArgumentPolicy.nmapExtras(extra)
        arguments.append(target)
        return CommandSpec(executable: binary.url, arguments: arguments)
    }
}

enum NetcatMode: String, CaseIterable, Identifiable, Sendable {
    case connect
    case listen

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

@MainActor
@Observable
final class NetcatForm {
    var mode: NetcatMode = .connect
    var host = "127.0.0.1"
    var port = "80"
    var udp = false
    var timeout = 8
    var payload = ""
    var bindLocalhost = true

    func build(binaries: [LocatedBinary]) throws -> CommandSpec {
        let port = try InputValidator.port(self.port)
        _ = try InputValidator.count(timeout, field: "Timeout", range: 1...120)
        let payload = try InputValidator.payload(self.payload)
        guard let binary = binaries.first else { throw ValidationError.empty(field: "nc") }

        var arguments: [String] = ["-v"]
        if udp { arguments.append("-u") }

        switch mode {
        case .connect:
            let host = try InputValidator.host(self.host)
            arguments += ["-w", String(timeout), host, String(port)]
            return CommandSpec(executable: binary.url, arguments: arguments, stdinText: payload)
        case .listen:
            arguments.append("-l")
            if bindLocalhost {
                arguments.append("127.0.0.1")
            }
            arguments.append(String(port))
            return CommandSpec(executable: binary.url, arguments: arguments, stdinText: payload)
        }
    }
}

enum TcpdumpDestination: String, CaseIterable, Identifiable, Sendable {
    case live
    case file

    var id: String { rawValue }
    var title: String { self == .live ? "Live text" : "Save pcap" }
}

@MainActor
@Observable
final class TcpdumpForm {
    var interfaceName = "any"
    var packetCount = 40
    var resolveNames = false
    var verbose = false
    var filter = ""
    var destination: TcpdumpDestination = .live
    var outputFile: URL?

    func build(binaries: [LocatedBinary]) throws -> CommandSpec {
        let interfaceName = try InputValidator.networkInterface(self.interfaceName)
        let maxPackets = destination == .live ? 10_000 : 50_000
        _ = try InputValidator.count(packetCount, field: "Packet count", range: 1...maxPackets)
        let filter = try InputValidator.bpfFilter(self.filter)
        guard let binary = binaries.first else { throw ValidationError.empty(field: "tcpdump") }

        var arguments: [String] = ["-i", interfaceName, "-c", String(packetCount)]
        if !resolveNames { arguments.append("-nn") }
        if verbose { arguments.append("-v") }

        switch destination {
        case .live:
            arguments.append("-l")
        case .file:
            guard let outputFile else { throw ValidationError.empty(field: "Capture file") }
            let safe = try InputValidator.userWritePath(outputFile)
            arguments += ["-w", safe.path]
        }

        if let filter {
            arguments += ["--", filter]
        }
        return CommandSpec(executable: binary.url, arguments: arguments)
    }
}

@MainActor
@Observable
final class WhoisForm {
    var query = "example.com"
    var server = ""

    func build(binaries: [LocatedBinary]) throws -> CommandSpec {
        let query = try InputValidator.whoisQuery(self.query)
        guard let binary = binaries.first else { throw ValidationError.empty(field: "whois") }
        var arguments: [String] = []
        let server = try InputValidator.nameserver(self.server)
        if let server {
            arguments += ["-h", server]
        }
        arguments.append(query)
        return CommandSpec(executable: binary.url, arguments: arguments)
    }
}

@MainActor
@Observable
final class CurlForm {
    var url = "https://example.com"
    var followRedirects = false
    var insecure = false
    var headers = ""

    func build(binaries: [LocatedBinary]) throws -> CommandSpec {
        let url = try InputValidator.httpURL(self.url)
        let headers = try InputValidator.httpHeaders(self.headers)
        guard let binary = binaries.first else { throw ValidationError.empty(field: "curl") }

        var arguments = ["-sS", "-D", "-", "-o", "/dev/null", "-I"]
        if followRedirects { arguments.append("-L") }
        if insecure { arguments.append("-k") }
        for header in headers {
            arguments += ["-H", header]
        }
        arguments.append(url)
        return CommandSpec(executable: binary.url, arguments: arguments)
    }

    func preview(from spec: CommandSpec) -> String {
        let redacted = (try? InputValidator.httpHeaders(headers)).map(InputValidator.redactHeaderValues) ?? []
        var displayArgs: [String] = []
        var skipNext = false
        var headerIndex = 0
        for argument in spec.arguments {
            if skipNext {
                skipNext = false
                if headerIndex < redacted.count {
                    displayArgs.append(CommandSpec.quoteForDisplay(redacted[headerIndex]))
                    headerIndex += 1
                }
                continue
            }
            displayArgs.append(CommandSpec.quoteForDisplay(argument))
            if argument == "-H" { skipNext = true }
        }
        return ([spec.executable.path] + displayArgs).joined(separator: " ")
    }
}
