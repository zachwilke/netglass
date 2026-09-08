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
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
