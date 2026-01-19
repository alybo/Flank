import Foundation
import CoreGraphics

struct WindowInfo: Identifiable {
    let id: Int // CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let title: String
    let bounds: CGRect
}

enum WindowLister {
    static func listWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return infoList.compactMap { dict in
            guard
                let windowID = dict[kCGWindowNumber as String] as? Int,
                let pid = dict[kCGWindowOwnerPID as String] as? Int,
                let ownerName = dict[kCGWindowOwnerName as String] as? String,
                let boundsDict = dict[kCGWindowBounds as String] as? [String: Any]
            else { return nil }

            let title = (dict[kCGWindowName as String] as? String) ?? ""
            let bounds = CGRect(
                x: boundsDict["X"] as? CGFloat ?? 0,
                y: boundsDict["Y"] as? CGFloat ?? 0,
                width: boundsDict["Width"] as? CGFloat ?? 0,
                height: boundsDict["Height"] as? CGFloat ?? 0
            )

            // Отфильтруем мусор: окна без размера или без заголовка можно оставить, но MVP проще с заголовком
            if bounds.width < 50 || bounds.height < 50 { return nil }

            return WindowInfo(id: windowID, ownerPID: pid_t(pid), ownerName: ownerName, title: title, bounds: bounds)
        }
    }
}
