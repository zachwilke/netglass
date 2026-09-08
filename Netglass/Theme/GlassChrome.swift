import AppKit
import SwiftUI

struct GlassShape<S: InsettableShape>: View {
    var shape: S
    var material: Material = .ultraThinMaterial
    var strokeOpacity: Double = 0.08

    var body: some View {
        shape
            .fill(material)
            .overlay {
                shape.strokeBorder(Color.primary.opacity(strokeOpacity), lineWidth: 1)
            }
            .overlay {
                tahoeGlass(shape)
            }
    }

    @ViewBuilder
    private func tahoeGlass(_ shape: S) -> some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        }
#else
        EmptyView()
#endif
    }
}

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary.opacity(0.35))
            }
    }
}

struct GlassField<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
            }
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(nsView.window)
    }

    private func apply(_ window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = false
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .visible
    }
}

struct VisualEffectBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .contentBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}
