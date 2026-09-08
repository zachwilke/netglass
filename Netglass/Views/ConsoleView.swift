import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CommandPreview: View {
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy command")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.bar)
    }
}

struct ConsoleView: View {
    @Bindable var session: ToolSession
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Output")
                    .font(.subheadline.weight(.semibold))
                if session.truncated {
                    Text("Showing the last \(ToolSession.maxLines) lines")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Follow", isOn: $session.autoScroll)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                Button("Copy") { copy() }
                    .buttonStyle(.borderless)
                    .disabled(session.lines.isEmpty)
                Button("Save…") { save() }
                    .buttonStyle(.borderless)
                    .disabled(session.lines.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)

            Divider()

            Group {
                if session.lines.isEmpty {
                    emptyState
                } else {
                    transcript
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                session.isRunning ? "Waiting for output" : "No output yet",
                systemImage: session.isRunning ? "ellipsis.circle" : "terminal"
            )
        } description: {
            Text(session.isRunning
                 ? "The diagnostic is running. Lines will appear as they arrive."
                 : "Run a diagnostic to stream stdout and stderr here.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(session.lines) { line in
                        Text(line.text)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Palette.streamColor(line.stream, scheme: scheme))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .padding(12)
            }
            .onChange(of: session.lines.count) {
                guard session.autoScroll, let last = session.lines.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.transcript(), forType: .string)
    }

    private func save() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.plainText]
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        panel.nameFieldStringValue = "\(session.tool.rawValue)-\(stamp).log"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let safe = try InputValidator.userWritePath(url)
                try session.transcript().write(to: safe, atomically: true, encoding: .utf8)
            } catch {
                session.presentError(error.localizedDescription)
            }
        }
    }
}
