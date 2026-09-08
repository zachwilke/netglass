import SwiftUI

struct TraceroutePanel: View {
    @Bindable var form: TracerouteForm
    let binaries: [LocatedBinary]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if binaries.isEmpty {
                MissingBinaryCard(tool: .traceroute)
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    FieldLabel("Host")
                    GlassField {
                        TextField("example.com", text: $form.host)
                    }

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            FieldLabel("Max hops")
                            Stepper(value: $form.maxHops, in: 1...64) {
                                Text("\(form.maxHops)").monospacedDigit()
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            FieldLabel("Queries / hop")
                            Stepper(value: $form.queries, in: 1...3) {
                                Text("\(form.queries)").monospacedDigit()
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            FieldLabel("Family")
                            Picker("Family", selection: $form.family) {
                                ForEach(IPFamily.allCases) { family in
                                    Text(family.title).tag(family)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }

                    Toggle("Numeric hops (skip reverse DNS)", isOn: $form.numeric)
                    Toggle("ICMP probes (-I)", isOn: $form.icmp)
                }
            }
        }
    }
}
