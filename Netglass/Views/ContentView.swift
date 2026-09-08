import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailWorkspace()
                .navigationTitle(model.selectedTool.title)
                .toolbar { InspectorToolbar() }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 880, minHeight: 580)
        .sheet(isPresented: $model.showingAbout) {
            AboutSheet()
        }
    }
}

struct InspectorToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            StatusPill(session: model.currentSession)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            ExportMenu(session: model.currentSession)

            Button("Clear", systemImage: "trash") {
                model.currentSession.clear()
            }
            .disabled(model.currentSession.lines.isEmpty)
            .help("Clear output")

            Button("Stop", systemImage: "stop.fill") {
                model.stopSelected()
            }
            .disabled(!model.currentSession.isRunning)
            .keyboardShortcut(".", modifiers: [.command])
            .help("Stop the running diagnostic")

            Button("Run", systemImage: "play.fill") {
                model.runSelected()
            }
            .disabled(model.currentSession.isRunning || model.primaryBinary(for: model.selectedTool) == nil)
            .keyboardShortcut("r", modifiers: [.command])
            .help("Run this diagnostic")
        }
    }
}

struct DetailWorkspace: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VSplitView {
            ScrollView {
                panel
                    .padding(20)
                    .frame(maxWidth: 760, alignment: .leading)
            }
            .frame(minHeight: 220)

            VStack(spacing: 0) {
                CommandPreview(text: previewText)
                ConsoleView(session: model.currentSession)
            }
            .frame(minHeight: 240)
        }
    }

    @ViewBuilder
    private var panel: some View {
        switch model.selectedTool {
        case .ping:
            PingPanel(form: model.ping, binaries: model.binaries(for: .ping))
        case .dig:
            DigPanel(form: model.dig, binaries: model.binaries(for: .dig))
        case .traceroute:
            TraceroutePanel(form: model.traceroute, binaries: model.binaries(for: .traceroute))
        case .nmap:
            NmapPanel(form: model.nmap, binaries: model.binaries(for: .nmap))
        case .netcat:
            NetcatPanel(form: model.netcat, binaries: model.binaries(for: .netcat))
        case .tcpdump:
            TcpdumpPanel(form: model.tcpdump, binaries: model.binaries(for: .tcpdump))
        case .whois:
            WhoisPanel(form: model.whois, binaries: model.binaries(for: .whois))
        case .curl:
            CurlPanel(form: model.curl, binaries: model.binaries(for: .curl))
        }
    }

    private var previewText: String {
        let session = model.currentSession
        if !session.lastPreview.isEmpty { return session.lastPreview }
        return "The exact argv appears here after a successful Run."
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
        .frame(width: 1100, height: 720)
}
