import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        @Bindable var model = model
        List(selection: Binding(
            get: { Optional(model.selectedTool) },
            set: { if let value = $0 { model.selectedTool = value } }
        )) {
            Section("Diagnostics") {
                ForEach(filtered(primary)) { tool in
                    SidebarRow(tool: tool, binaries: model.binaries(for: tool))
                        .tag(tool)
                }
            }
            Section("Also") {
                ForEach(filtered(secondary)) { tool in
                    SidebarRow(tool: tool, binaries: model.binaries(for: tool))
                        .tag(tool)
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $query, placement: .sidebar, prompt: "Filter tools")
        .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 280)
    }

    private var primary: [ToolKind] { ToolKind.allCases.filter { !$0.isSecondary } }
    private var secondary: [ToolKind] { ToolKind.allCases.filter(\.isSecondary) }

    private func filtered(_ tools: [ToolKind]) -> [ToolKind] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return tools }
        return tools.filter {
            $0.title.localizedCaseInsensitiveContains(needle)
                || $0.subtitle.localizedCaseInsensitiveContains(needle)
                || $0.rawValue.localizedCaseInsensitiveContains(needle)
        }
    }
}

struct SidebarRow: View {
    let tool: ToolKind
    let binaries: [LocatedBinary]

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(tool.title)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: tool.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel(tool.title)
        .accessibilityValue(binaries.isEmpty ? "Not installed" : "Ready")
    }

    private var statusText: String {
        if binaries.isEmpty { return "Not installed" }
        return binaries[0].name
    }
}
