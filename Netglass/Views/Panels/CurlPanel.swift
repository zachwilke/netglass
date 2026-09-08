import SwiftUI

struct CurlPanel: View {
    @Bindable var form: CurlForm
    let binaries: [LocatedBinary]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if binaries.isEmpty {
                MissingBinaryCard(tool: .curl)
            }

            NoteCard(
                symbol: "eye.slash",
                title: "Headers only, no secrets in the URL",
                message: "This runs curl -I and prints response headers. Userinfo in the URL is rejected. Authorization, Cookie, and similar secret headers are refused entirely so they never appear on the process list."
            )

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    FieldLabel("URL")
                    GlassField {
                        TextField("https://example.com", text: $form.url)
                    }
                    Toggle("Follow redirects", isOn: $form.followRedirects)
                    Toggle("Allow insecure TLS", isOn: $form.insecure)
                    FieldLabel("Extra request headers", hint: "One Name: value per line.")
                    GlassField {
                        TextEditor(text: $form.headers)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 72)
                    }
                }
            }
        }
    }
}
