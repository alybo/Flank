import Cocoa
import SwiftUI

final class WindowDropPanel {
    private var panel: NSPanel?
    private var hosting: NSHostingView<DropTargetView>?
    private let entrance = PanelEntranceAnimation()
    private var content: DropTargetView?
    private var targetFrame: CGRect?
    // Hit testing uses the stable destination, not an intermediate animation frame.
    var frame: CGRect? { targetFrame }

    func show(screen: NSScreen, armed: Bool, replacing: String?, side: DockState.Side = .right, detaching: Bool = false) {
        let frame = WindowGeometry.dropTargetFrame(in: screen.frame, side: side)
        guard !frame.isEmpty else { hide(); return }
        let content = DropTargetView(armed: armed, replacing: replacing, size: frame.size, side: side, detaching: detaching)
        if let hosting {
            if self.content != content { hosting.rootView = content; self.content = content }
            if targetFrame != frame {
                entrance.cancel()
                targetFrame = frame
                panel?.setFrame(frame, display: true)
                panel?.alphaValue = 1
            }
            return
        }
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true // The native drag keeps ownership of mouseUp.
        let hosting = NSHostingView(rootView: content)
        panel.contentView = hosting
        self.hosting = hosting
        self.panel = panel
        self.content = content
        targetFrame = frame
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        entrance.start { [weak panel] progress in
            panel?.setFrame(PanelEntranceAnimation.frame(at: progress, destination: frame, side: side), display: true)
            panel?.alphaValue = progress
        }
    }

    func hide() {
        entrance.cancel()
        panel?.orderOut(nil)
        panel = nil
        hosting = nil
        content = nil
        targetFrame = nil
    }
    deinit { hide() }
}

struct DropTargetView: View, Equatable {
    let armed: Bool
    let replacing: String?
    let size: CGSize
    var side: DockState.Side = .right
    var detaching = false
    var body: some View {
        HStack(spacing: 0) {
            if side == .right { contour }
            VStack(spacing: 10) {
                Text(detaching ? "Отвязать окно" : (armed ? "Отпустите окно\nздесь" : "Перетащите окно\nсюда"))
                    .font(.system(size: 12, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: 28)
                Image(systemName: (side == .right) != detaching ? "arrow.right" : "arrow.left")
                    .font(.system(size: 40, weight: .bold))
                    .frame(width: 49, height: 48)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color(red: 239 / 255, green: 239 / 255, blue: 239 / 255))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .overlay(alignment: .bottom) {
                if let replacing, !detaching {
                    Text("«\(replacing)» вернётся на экран")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center).lineLimit(3).padding(24)
                }
            }
            if side == .left { contour }
        }
        .frame(width: size.width, height: size.height)
    }

    private var contour: some View {
        Image("FigmaDropContour")
            .resizable(capInsets: EdgeInsets(top: 24, leading: 0, bottom: 24, trailing: 0), resizingMode: .stretch)
            .frame(width: 24, height: size.height)
            .scaleEffect(x: side == .right ? 1 : -1, y: 1)
            .accessibilityHidden(true)
    }
}
