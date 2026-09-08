import SwiftUI

struct NetcatPanel: View {
    @Bindable var form: NetcatForm
    let binaries: [LocatedBinary]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if binaries.isEmpty {
                MissingBinaryCard(tool: .netcat)
            }

            NoteCard(
                symbol: "hand.raised",
                title: "Diagnostic sockets only",
                message: "Netglass never exposes -e or -c. Listen mode binds one port and stops with the Stop button. Use it to check that a service accepts a connection, not as a relay."
            )

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    FieldLabel("Mode")
                    Picker("Mode", selection: $form.mode) {
                        ForEach(NetcatMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if form.mode == .connect {
                        FieldLabel("Host")
                        GlassField {
                            TextField("127.0.0.1", text: $form.host)
                        }
                    }

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            FieldLabel("Port")
                            GlassField {
                                TextField("80", text: $form.port)
                            }
                            .frame(maxWidth: 140)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            FieldLabel("Timeout")
                            Stepper(value: $form.timeout, in: 1...120) {
                                Text("\(form.timeout)s").monospacedDigit()
                            }
                            .disabled(form.mode == .listen)
                        }
                    }

                    Toggle("UDP", isOn: $form.udp)
                    if form.mode == .listen {
                        Toggle("Bind localhost only", isOn: $form.bindLocalhost)
                    }

                    FieldLabel("Optional payload", hint: "Written to stdin, then stdin is closed. 4 KB max.")
                    GlassField {
                        TextField("GET / HTTP/1.0\\r\\n\\r\\n", text: $form.payload, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
            }
        }
    }
}
