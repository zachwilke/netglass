import Sparkle
import SwiftUI

@main
struct NetglassApp: App {
    @State private var model = AppModel()
    private let updates = UpdateController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .background(WindowConfigurator())
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1140, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Netglass") { model.showingAbout = true }
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updates.controller.updater)
            }
            CommandMenu("Diagnostic") {
                Button("Run") { model.runSelected() }
                    .keyboardShortcut("r")
                    .disabled(model.currentSession.isRunning)
                Button("Stop") { model.stopSelected() }
                    .keyboardShortcut(".")
                    .disabled(!model.currentSession.isRunning)
                Divider()
                Button("Clear Output") { model.currentSession.clear() }
                    .keyboardShortcut("k")
            }
            CommandMenu("Export") {
                Button("Save Text…") { ReportShare.save(model.currentSession, format: .text) }
                    .disabled(model.currentSession.lines.isEmpty)
                Button("Save Markdown…") { ReportShare.save(model.currentSession, format: .markdown) }
                    .disabled(model.currentSession.lines.isEmpty)
                Button("Save CSV…") { ReportShare.save(model.currentSession, format: .csv) }
                    .disabled(model.currentSession.lines.isEmpty)
                Divider()
                Button("Copy for AI") { ReportShare.copyForAI(model.currentSession) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(model.currentSession.lines.isEmpty)
                Button("Copy Raw") { ReportShare.copyRaw(model.currentSession) }
                    .disabled(model.currentSession.lines.isEmpty)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
