import SwiftUI

struct PingPanel: View {
    @Bindable var form: PingForm
    let binaries: [LocatedBinary]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if binaries.isEmpty {
                MissingBinaryCard(tool: .ping)
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    FieldLabel("Host", hint: "Hostname or IP. No lists, no shell characters.")
                    GlassField {
                        TextField("1.1.1.1 or example.com", text: $form.host)
                    }

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            FieldLabel("Count")
                            Stepper(value: $form.count, in: 1...10_000) {
                                Text("\(form.count)")
                                    .monospacedDigit()
                            }
                            .disabled(form.continuous)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            FieldLabel("Interval", hint: "Under 1s usually needs root")
                            Slider(value: $form.interval, in: 0.2...5, step: 0.1)
                            Text("\(form.interval, specifier: \"%.1f\") s")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
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

                    Toggle("Continuous until stopped", isOn: $form.continuous)
                    Toggle("Numeric output (skip DNS)", isOn: $form.numeric)
                }
            }
        }
    }
}
