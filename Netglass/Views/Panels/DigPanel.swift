import SwiftUI

struct DigPanel: View {
    @Bindable var form: DigForm
    let binaries: [LocatedBinary]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if binaries.isEmpty {
                MissingBinaryCard(tool: .dig)
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    FieldLabel("Name")
                    GlassField {
                        TextField("example.com", text: $form.name)
                    }

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            FieldLabel("Record")
                            Picker("Record", selection: $form.recordType) {
                                ForEach(["A", "AAAA", "MX", "NS", "TXT", "CNAME", "SOA", "PTR", "SRV", "CAA"], id: \.self) { type in
                                    Text(type).tag(type)
                                }
                            }
                            .labelsHidden()
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            FieldLabel("Engine", hint: "Uses whatever is installed")
                            Picker("Engine", selection: $form.engine) {
                                ForEach(availableEngines) { engine in
                                    Text(engine.title).tag(engine)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }

                    FieldLabel("Nameserver", hint: "Optional. Leave empty for the system resolver.")
                    GlassField {
                        TextField("1.1.1.1", text: $form.nameserver)
                    }

                    if form.engine == .dig {
                        Toggle("Short answers", isOn: $form.shortOutput)
                        Toggle("Trace from the root", isOn: $form.trace)
                    }
                }
            }
        }
        .onAppear { preferInstalledEngine() }
        .onChange(of: binaries) { preferInstalledEngine() }
    }

    private var availableEngines: [DigEngine] {
        let names = Set(binaries.map(\.name))
        let installed = DigEngine.allCases.filter { names.contains($0.rawValue) }
        return installed.isEmpty ? DigEngine.allCases : installed
    }

    private func preferInstalledEngine() {
        let names = Set(binaries.map(\.name))
        if !names.contains(form.engine.rawValue), let first = availableEngines.first {
            form.engine = first
        }
    }
}
