import Cocoa

nonisolated enum DragModifier: String, Codable, CaseIterable, Identifiable {
    case controlShift, commandShift, shift
    var id: String { rawValue }
    var label: String {
        switch self {
        case .controlShift: "⌃ Control + ⇧ Shift"
        case .commandShift: "⌘ Command + ⇧ Shift"
        case .shift: "⇧ Shift"
        }
    }
    func matches(_ flags: NSEvent.ModifierFlags) -> Bool {
        let relevant = flags.intersection([.control, .shift, .command, .option])
        switch self {
        case .controlShift: return relevant == [.control, .shift]
        case .commandShift: return relevant == [.command, .shift]
        case .shift: return relevant == [.shift]
        }
    }
}

// Pure geometry/state logic shared by the native event controller and regression tests.
struct WindowDragIntent {
    nonisolated enum Phase { case candidate, dragging, eligible, armed, committing, cancelled }
    let initialFrame: CGRect // AX coordinates.
    let initialPointer: CGPoint // AppKit coordinates.
    let screenFrame: CGRect
    private(set) var phase: Phase = .candidate
    private var hasUsedModifier = false
    private var hasConfirmedWindowDrag = false

    init(initialFrame: CGRect, initialPointer: CGPoint, screenFrame: CGRect) {
        self.initialFrame = initialFrame
        self.initialPointer = initialPointer
        self.screenFrame = screenFrame
    }

    mutating func update(frame: CGRect, pointer: CGPoint, modifier: Bool, insideTarget: Bool) {
        guard phase != .cancelled, phase != .committing else { return }
        guard screenFrame.contains(pointer),
              abs(frame.width - initialFrame.width) <= 2, abs(frame.height - initialFrame.height) <= 2 else {
            cancel(); return
        }
        if hasUsedModifier && !modifier { cancel(); return }
        if !hasConfirmedWindowDrag {
            let dx = frame.minX - initialFrame.minX, dy = frame.minY - initialFrame.minY
            let px = pointer.x - initialPointer.x, py = pointer.y - initialPointer.y
            guard hypot(dx, dy) >= 6, hypot(px, py) >= 8,
                  abs(dx - px) <= 28, abs(dy + py) <= 28 else {
                phase = .candidate
                return
            }
            // AX and mouse events arrive independently; recognition is latched for
            // this mouse-down session. Safety/cancellation checks above still apply.
            hasConfirmedWindowDrag = true
        }
        if modifier {
            hasUsedModifier = true
            phase = insideTarget ? .armed : .eligible
        } else { phase = .dragging }
    }

    mutating func release(modifier: Bool, insideTarget: Bool) -> Bool {
        guard modifier, insideTarget, phase == .armed || phase == .eligible else { cancel(); return false }
        phase = .committing
        return true
    }

    mutating func cancel() { phase = .cancelled }
}
