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
}
