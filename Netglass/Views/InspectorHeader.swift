import SwiftUI

struct StatusPill: View {
    var session: ToolSession

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(session.state.label)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status")
        .accessibilityValue(session.state.label)
    }

    private var color: Color {
        switch session.state {
        case .idle: return Color.secondary.opacity(0.45)
        case .running: return Color.accentColor
        case .succeeded: return Color.green
        case .failed, .errored: return Color.red
        case .cancelled: return Color.orange
        }
    }
}
