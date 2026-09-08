import AppKit
import SwiftUI

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
                if let notice = session.exportNotice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
                Toggle("Follow", isOn: $session.autoScroll)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                ExportMenu(session: session)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .animation(.easeOut(duration: 0.2), value: session.exportNotice)

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

}
