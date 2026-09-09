import Foundation

enum ConsoleText: Sendable {
    static let maxLineCharacters = 4_096
    static let maxPartialBytes = 65_536

    private static let ansi = try! NSRegularExpression(
        pattern: "\\u001B\\[[0-9;?=]*[ -/]*[@-~]|\\u001B\\][^\\u0007]*\\u0007|\\u001B[@-Z\\\\-_]"
    )

    static func sanitize(_ raw: String) -> String {
        let ns = raw as NSString
        let stripped = ansi.stringByReplacingMatches(
            in: raw,
            options: [],
            range: NSRange(location: 0, length: ns.length),
            withTemplate: ""
        )
        var scalars: [Unicode.Scalar] = []
        scalars.reserveCapacity(min(stripped.unicodeScalars.count, maxLineCharacters + 1))
        for scalar in stripped.unicodeScalars {
            if scalar == "\t" {
                scalars.append(scalar)
            } else if CharacterSet.controlCharacters.contains(scalar) || scalar == "\u{007F}" {
                scalars.append(" ")
            } else {
                scalars.append(scalar)
            }
            if scalars.count >= maxLineCharacters {
                return String(String.UnicodeScalarView(scalars)) + "…"
            }
        }
        return String(String.UnicodeScalarView(scalars))
    }
}

struct StreamedLine: Sendable, Equatable {
    var stream: OutputLine.Stream
    var text: String
}
