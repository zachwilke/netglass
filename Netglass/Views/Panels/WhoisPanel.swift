import SwiftUI

struct WhoisPanel: View {
    @Bindable var form: WhoisForm
    let binaries: [LocatedBinary]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if binaries.isEmpty {
                MissingBinaryCard(tool: .whois)
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    FieldLabel("Query")
                    GlassField {
                        TextField("example.com", text: $form.query)
                    }
                    FieldLabel("Whois server", hint: "Optional. Empty uses the default referral path.")
                    GlassField {
                        TextField("whois.iana.org", text: $form.server)
                    }
                }
            }
        }
    }
}
