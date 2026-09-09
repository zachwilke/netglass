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
                GlassShape(shape: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        window.backgroundColor = .clear
        window.isOpaque = false
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .visible
        installBackdrop(in: window)
    }

    /// The backdrop belongs at the bottom of the window's own content view, so
    /// it covers the full frame including the toolbar strip and the edges.
    /// Hung off a SwiftUI `.background` it only covers laid-out content, and
    /// anything outside that becomes a see-through gap rather than frosted.
    private func installBackdrop(in window: NSWindow) {
        guard let contentView = window.contentView else { return }
        let id = NSUserInterfaceItemIdentifier("netglass.backdrop")
        if contentView.subviews.contains(where: { $0.identifier == id }) { return }
        let backdrop = NSVisualEffectView()
        backdrop.identifier = id
        backdrop.material = .underWindowBackground
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.frame = contentView.bounds
        backdrop.autoresizingMask = [.width, .height]
        contentView.addSubview(backdrop, positioned: .below, relativeTo: nil)
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
