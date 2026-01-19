import Foundation

struct EdgeSettings: Codable, Equatable {
    // Stable identifier (preferred). nil = “Ничего”
    var selectedBundleID: String? = nil

    // Legacy (PID changes every launch). Kept only for migration.
    var selectedPID: Int? = nil

    var enableHideOnCursorLeave: Bool = true
    var cursorLeaveHideDelay: TimeInterval = 2.5

    var revealDelay: TimeInterval = 0.0  // задержка перед выездом при наведении на край

    var enableHideOnInactivity: Bool = true
    var inactivityHideDelay: TimeInterval = 3.0

    var isEnabled: Bool = true

    var overlayWidth: Double = 6.0
    var gripWidth: Double = 4.0

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
        case overlayWidth
        case gripWidth
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
        overlayWidth = try container.decodeIfPresent(Double.self, forKey: .overlayWidth) ?? 6.0
        gripWidth = try container.decodeIfPresent(Double.self, forKey: .gripWidth) ?? 4.0
    }
}
