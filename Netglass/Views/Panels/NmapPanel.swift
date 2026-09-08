import SwiftUI

struct NmapPanel: View {
    @Bindable var form: NmapForm
    let binaries: [LocatedBinary]
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if binaries.isEmpty {
                MissingBinaryCard(tool: .nmap)
            }

            PrivilegeCard(tool: .nmap, discovered: model.session(.nmap).sawPrivilegeError)

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    FieldLabel("Target", hint: "Single host, or IPv4 /24 and narrower.")
                    GlassField {
                        TextField("127.0.0.1", text: $form.target)
                    }

                    FieldLabel("Preset")
                    Picker("Preset", selection: $form.preset) {
                        ForEach(NmapPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text(form.preset.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Toggle("Treat host as up (-Pn)", isOn: $form.skipDiscovery)
                        .disabled(form.preset == .hostUp)

                    FieldLabel("Advanced flags", hint: "Optional. Allowlisted only: -Pn -n -v -sV -F -p …")
                    GlassField {
                        TextField("-v --reason", text: $form.extra)
                    }
                }
            }
        }
    }
}
