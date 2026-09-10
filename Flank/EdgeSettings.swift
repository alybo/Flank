import Foundation

struct EdgeSettings: Codable, Equatable {
    // Legacy app preference; never used to bind a window automatically.
    var selectedBundleID: String? = nil

    // Legacy (PID changes every launch). Kept only for migration.
    var selectedPID: Int? = nil

    var enableHideOnCursorLeave: Bool = true
    var cursorLeaveHideDelay: TimeInterval = 2.5

    var revealDelay: TimeInterval = 0.0  // задержка перед выездом при наведении на край

    var enableHideOnInactivity: Bool = true
    var inactivityHideDelay: TimeInterval = 3.0

    var isEnabled: Bool = true
    var side: DockState.Side = .right

    var overlayWidth: Double = 6.0
    var gripWidth: Double = 4.0
    var enableRevealIndicator: Bool = false
    var enableDragToDock: Bool = true
    var dragModifier: DragModifier = .controlShift

    init() {}

    enum CodingKeys: String, CodingKey {
        case selectedBundleID
        case selectedPID
        case enableHideOnCursorLeave
        case cursorLeaveHideDelay
        case revealDelay
        case enableHideOnInactivity
        case inactivityHideDelay
        case isEnabled
        case side
        case overlayWidth
        case gripWidth
        case enableRevealIndicator
        case enableDragToDock
        case dragModifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        selectedBundleID = try container.decodeIfPresent(String.self, forKey: .selectedBundleID)
        selectedPID = try container.decodeIfPresent(Int.self, forKey: .selectedPID)
        enableHideOnCursorLeave = try container.decodeIfPresent(Bool.self, forKey: .enableHideOnCursorLeave) ?? true
        cursorLeaveHideDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .cursorLeaveHideDelay) ?? 2.5
        revealDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .revealDelay) ?? 0.0
        enableHideOnInactivity = try container.decodeIfPresent(Bool.self, forKey: .enableHideOnInactivity) ?? true
        inactivityHideDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .inactivityHideDelay) ?? 3.0
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        let sideName = try container.decodeIfPresent(String.self, forKey: .side)
        side = sideName.flatMap(DockState.Side.init(rawValue:)) ?? .right
        overlayWidth = try container.decodeIfPresent(Double.self, forKey: .overlayWidth) ?? 6.0
        gripWidth = try container.decodeIfPresent(Double.self, forKey: .gripWidth) ?? 4.0
        enableRevealIndicator = try container.decodeIfPresent(Bool.self, forKey: .enableRevealIndicator) ?? false
        enableDragToDock = try container.decodeIfPresent(Bool.self, forKey: .enableDragToDock) ?? true
        let modifierName = try container.decodeIfPresent(String.self, forKey: .dragModifier)
        dragModifier = modifierName.flatMap(DragModifier.init(rawValue:)) ?? .controlShift
        self = validated()
    }

    func validated() -> EdgeSettings {
        var result = self
        func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        result.cursorLeaveHideDelay = clamp(cursorLeaveHideDelay, 0...10, fallback: 2.5)
        result.inactivityHideDelay = clamp(inactivityHideDelay, 0...20, fallback: 3)
        result.revealDelay = clamp(revealDelay, 0...5, fallback: 0)
        result.overlayWidth = clamp(overlayWidth, 2...20, fallback: 6)
        result.gripWidth = clamp(gripWidth, 1...16, fallback: 4)
        if let pid = selectedPID, pid <= 0 || pid > Int(Int32.max) { result.selectedPID = nil }
        return result
    }
}
