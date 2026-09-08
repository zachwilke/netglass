import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Save panel + pasteboard helpers for report export. Writes only the
/// current console snapshot; never re-runs a diagnostic.
enum ReportShare {
    @MainActor
    static func copyRaw(_ session: ToolSession) {
        copy(session.transcript(), notice: "Copied", on: session)
    }

    @MainActor
    static func copyForAI(_ session: ToolSession) {
        copy(ReportFormatter.aiCopy(session.makeSnapshot()), notice: "Copied for AI", on: session)
    }

    @MainActor
    static func save(_ session: ToolSession, format: ReportFileFormat) {
        let snapshot = session.makeSnapshot()
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [utType(for: format)]
        panel.nameFieldStringValue = ReportFormatter.suggestedFilename(snapshot, format: format)
        panel.message = "Choose a location for this \(format.displayName.lowercased()) report."
        panel.prompt = "Save"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let safe = try InputValidator.userWritePath(url)
            try ReportFormatter.render(snapshot, format: format).write(to: safe, atomically: true, encoding: .utf8)
            session.flashExportNotice("Saved")
        } catch {
            session.presentError(error.localizedDescription)
        }
    }

    @MainActor
    private static func copy(_ string: String, notice: String, on session: ToolSession) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        session.flashExportNotice(notice)
    }

    static func utType(for format: ReportFileFormat) -> UTType {
        switch format {
        case .text:
            return .plainText
        case .markdown:
            return UTType(filenameExtension: "md") ?? .plainText
        case .csv:
            return .commaSeparatedText
        }
    }
}

struct ExportMenu: View {
    var session: ToolSession
    var showLabel: Bool = true

    var body: some View {
        let snapshot = session.makeSnapshot()
        Menu {
            Button("Save Text…") { ReportShare.save(session, format: .text) }
            Button("Save Markdown…") { ReportShare.save(session, format: .markdown) }
            Button("Save CSV…") { ReportShare.save(session, format: .csv) }
            Divider()
            Button("Copy for AI") { ReportShare.copyForAI(session) }
            Button("Copy Raw") { ReportShare.copyRaw(session) }
            Divider()
            ShareLink(
                item: ReportFormatter.markdown(snapshot),
                subject: Text("\(session.tool.title) — Netglass"),
                message: Text("Local diagnostic report from Netglass.")
            ) {
                Label("Share Markdown", systemImage: "square.and.arrow.up")
            }
        } label: {
            if showLabel {
                Label("Export", systemImage: "square.and.arrow.up")
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .menuIndicator(.visible)
        .disabled(session.lines.isEmpty)
        .help(session.lines.isEmpty
              ? "Run a diagnostic to export its output"
              : "Save or copy this console as text, Markdown, CSV, or an AI prompt")
        .accessibilityLabel("Export")
    }
}
