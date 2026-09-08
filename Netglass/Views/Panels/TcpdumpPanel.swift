import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TcpdumpPanel: View {
    @Bindable var form: TcpdumpForm
    let binaries: [LocatedBinary]
    @Environment(AppModel.self) private var model
    @State private var interfaces: [String] = ["any", "en0", "lo0"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if binaries.isEmpty {
                MissingBinaryCard(tool: .tcpdump)
            }

            PrivilegeCard(tool: .tcpdump, discovered: model.session(.tcpdump).sawPrivilegeError)

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            FieldLabel("Interface")
                            Picker("Interface", selection: $form.interfaceName) {
                                ForEach(interfaces, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .labelsHidden()
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            FieldLabel("Packets")
                            Stepper(value: $form.packetCount, in: 1...10_000, step: 10) {
                                Text("\(form.packetCount)").monospacedDigit()
                            }
                        }
                    }

                    FieldLabel("BPF filter", hint: "host, port, tcp, udp, and, or. No quotes or shell punctuation.")
                    GlassField {
                        TextField("port 443", text: $form.filter)
                    }

                    Picker("Destination", selection: $form.destination) {
                        ForEach(TcpdumpDestination.allCases) { destination in
                            Text(destination.title).tag(destination)
                        }
                    }
                    .pickerStyle(.segmented)

                    if form.destination == .file {
                        HStack {
                            Text(form.outputFile?.path ?? "No file chosen")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Button("Choose…") { chooseFile() }
                        }
                    }

                    Toggle("Resolve names", isOn: $form.resolveNames)
                    Toggle("Verbose", isOn: $form.verbose)
                }
            }
        }
        .onAppear {
            interfaces = InterfaceEnumerator.list()
            if !interfaces.contains(form.interfaceName) {
                form.interfaceName = interfaces.first ?? "any"
            }
        }
    }

    private func chooseFile() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "pcap") ?? .data]
        panel.nameFieldStringValue = "capture.pcap"
        if panel.runModal() == .OK {
            form.outputFile = panel.url
        }
    }
}
