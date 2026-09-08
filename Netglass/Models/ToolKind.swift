import Foundation

enum ToolKind: String, CaseIterable, Identifiable, Sendable {
    case ping
    case dig
    case traceroute
    case nmap
    case netcat
    case tcpdump
    case whois
    case curl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ping: return "Ping"
        case .dig: return "Dig"
        case .traceroute: return "Traceroute"
        case .nmap: return "Nmap"
        case .netcat: return "Netcat"
        case .tcpdump: return "Tcpdump"
        case .whois: return "Whois"
        case .curl: return "Headers"
        }
    }

    var subtitle: String {
        switch self {
        case .ping: return "Echo requests"
        case .dig: return "DNS lookups"
        case .traceroute: return "Path to a host"
        case .nmap: return "Polite port checks"
        case .netcat: return "Connect or listen"
        case .tcpdump: return "Packet capture"
        case .whois: return "Registration records"
        case .curl: return "HTTP response headers"
        }
    }

    var systemImage: String {
        switch self {
        case .ping: return "waveform.path.ecg"
        case .dig: return "text.magnifyingglass"
        case .traceroute: return "point.topleft.down.to.point.bottomright.curvepath"
        case .nmap: return "rectangle.grid.2x2"
        case .netcat: return "cable.connector"
        case .tcpdump: return "dot.radiowaves.left.and.right"
        case .whois: return "person.text.rectangle"
        case .curl: return "doc.text.magnifyingglass"
        }
    }

    var isSecondary: Bool {
        switch self {
        case .whois, .curl: return true
        default: return false
        }
    }

    var prefersSystemBinary: Bool {
        switch self {
        case .nmap, .dig: return false
        default: return true
        }
    }

    var binaryNames: [String] {
        switch self {
        case .ping: return ["ping", "ping6"]
        case .dig: return ["dig", "host", "nslookup"]
        case .traceroute: return ["traceroute", "traceroute6"]
        case .nmap: return ["nmap"]
        case .netcat: return ["nc", "netcat"]
        case .tcpdump: return ["tcpdump"]
        case .whois: return ["whois"]
        case .curl: return ["curl"]
        }
    }

    var brewFormula: String? {
        switch self {
        case .nmap: return "nmap"
        case .dig: return "bind"
        case .whois: return "whois"
        default: return nil
        }
    }

    var installHint: String {
        switch self {
        case .nmap:
            return "Install with Homebrew: brew install nmap"
        case .dig:
            return "macOS used to ship dig via BIND. Install with: brew install bind"
        case .whois:
            return "whois is usually preinstalled. Otherwise: brew install whois"
        case .curl:
            return "curl is preinstalled on macOS."
        case .ping, .traceroute, .netcat, .tcpdump:
            return "This tool ships with macOS. If it is missing, check Command Line Tools or restore the system binary."
        }
    }

    var needsPrivilegeNote: Bool {
        self == .tcpdump || self == .nmap
    }
}
