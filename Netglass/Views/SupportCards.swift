import AppKit
import SwiftUI

struct FieldLabel: View {
    var title: String
    var hint: String?

    init(_ title: String, hint: String? = nil) {
        self.title = title
        self.hint = hint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.medium))
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct MissingBinaryCard: View {
    let tool: ToolKind

    var body: some View {
        GlassCard {
            Label {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(tool.title) isn’t installed")
                        .font(.headline)
                    Text(tool.installHint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let formula = tool.brewFormula {
                        HStack(spacing: 8) {
                            Text("brew install \(formula)")
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("brew install \(formula)", forType: .string)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .imageScale(.large)
            }
        }
    }
}

struct PrivilegeCard: View {
    var tool: ToolKind
    var discovered: Bool

    var body: some View {
        GlassCard {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(discovered ? "This run needs higher privileges" : "Privilege note")
                        .font(.headline)
                    Text(copy)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: discovered ? "lock.trianglebadge.exclamationmark" : "lock.shield")
                    .foregroundStyle(discovered ? .red : .secondary)
                    .imageScale(.large)
            }
        }
    }

    private var copy: String {
        if tool == .tcpdump {
            return "tcpdump needs BPF access. Netglass will not ask for your password or ship a setuid helper. Install Wireshark’s ChmodBPF package, or run the previewed command in Terminal with sudo after you have reviewed it. App Sandbox is off in the default build."
        }
        return "Some nmap probes need raw sockets and will fail as your user. Default presets use TCP connect (-sT) or ping scan (-sn) so they stay usable without root."
    }
}

struct NoteCard: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        GlassCard {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .imageScale(.large)
            }
        }
    }
}
