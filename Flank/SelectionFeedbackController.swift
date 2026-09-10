import Cocoa
import SwiftUI

final class SelectionFeedbackController {
    private var panel: NSPanel?
    private let dismissal = CancellableDelay()

    func show(_ message: String, screen: NSScreen?, undo: (() -> Void)? = nil) {
        hide()
        guard let screen = screen ?? NSScreen.main else { return }
        let view = NSHostingView(rootView: HStack(spacing: 14) {
            Text(message).lineLimit(2).frame(maxWidth: 280, alignment: .leading)
            if let undo { Button("Отменить", action: undo) }
        }.padding(14))
        let size = view.fittingSize
        let frame = CGRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 24,
                           width: size.width, height: size.height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = view
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        self.panel = panel
        panel.orderFrontRegardless()
        dismissal.schedule(after: 8) { [weak self] in self?.hide() }
    }

    func hide() {
        dismissal.cancel()
        panel?.orderOut(nil)
        panel = nil
    }

    deinit { hide() }
}
