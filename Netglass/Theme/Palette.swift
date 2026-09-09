import SwiftUI

enum Palette {
    static func streamColor(_ stream: OutputLine.Stream, scheme: ColorScheme) -> Color {
        switch stream {
        case .stdout:
            return Color.primary.opacity(scheme == .dark ? 0.92 : 0.84)
        case .stderr:
            return Color.red.opacity(0.85)
        case .system, .notice:
            return Color.accentColor.opacity(0.9)
        }
    }
}
