import AppKit
import SwiftUI

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Netglass")
                        .font(.title2.weight(.semibold))
                    Text(versionLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text("A local control surface for ping, dig, traceroute, nmap, nc, and tcpdump. Tools run as argv subprocesses. Output stays on this Mac.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                labeled("Updates", "Sparkle checks GitHub Releases when a signing key is configured.")
                labeled("Privileges", "No setuid helper. tcpdump may need ChmodBPF or a reviewed sudo in Terminal.")
                labeled("Sandbox", "App Sandbox is off so Homebrew tools and BPF can run. Treat this as a developer utility.")
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 460)
    }

    private var versionLine: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    private func labeled(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(body)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView {
            Form {
                Section("Binary search") {
                    Text("Absolute directories only, one per line. Relative paths, “..”, and temporary directories are ignored. System tools prefer /usr and /sbin over Homebrew.")
                        .foregroundStyle(.secondary)
                    TextEditor(text: $model.extraPathText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                        .onChange(of: model.extraPathText) {
                            model.scheduleBinaryRefresh()
                        }
                    if !model.extraPathWarnings.isEmpty {
                        Text("Ignored: \(model.extraPathWarnings.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Button("Rescan now") { model.refreshBinaries() }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Paths", systemImage: "folder") }

            Form {
                Section("Automatic updates") {
                    Text("Netglass uses Sparkle 2. The feed is the GitHub Releases appcast for zachwilke/netglass. Checks stay off until you paste a real EdDSA public key — see Docs/SPARKLE.md.")
                        .foregroundStyle(.secondary)
                    LabeledContent("Feed") {
                        Text(UpdateController.feedURL.absoluteString)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Public key") {
                        Text(UpdateController.publicKeyConfigured ? "Configured" : "Placeholder — updates disabled")
                            .foregroundStyle(UpdateController.publicKeyConfigured ? .secondary : .orange)
                    }
                    if UpdateController.publicKeyConfigured {
                        Button("Check for Updates…") {
                            UpdateController.shared.checkForUpdates()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 480, height: 360)
        .padding(8)
    }
}
