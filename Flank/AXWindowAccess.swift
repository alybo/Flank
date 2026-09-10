import ApplicationServices
import Foundation

enum WindowAccessError: LocalizedError {
    case accessibility(AXError)
    case operationFailed(WindowAccessOperation, AXError)
    case invalidGeometry
    case positionNotApplied

    var errorDescription: String? {
        switch self {
        case .accessibility(let error):
            return Self.describe(error)
        case .operationFailed(let operation, let error):
            return "\(operation.label): \(Self.describe(error))"
        case .invalidGeometry:
            return "Приложение вернуло некорректное положение окна. Повторите возврат."
        case .positionNotApplied:
            return "Приложение не переместило окно в нужное положение. Повторите возврат."
        }
    }

    var isUnsupportedRaise: Bool {
        guard case .operationFailed(.raise, let error) = self else { return false }
        return error == .actionUnsupported || error == .attributeUnsupported
    }

    private static func describe(_ error: AXError) -> String {
        let reason: String
        switch error {
        case .attributeUnsupported: reason = "приложение не поддерживает запрошенное свойство окна"
        case .actionUnsupported: reason = "приложение не поддерживает запрошенное действие с окном"
        case .apiDisabled: return "Доступ Accessibility отключён (\(error.rawValue)). Проверьте разрешение в системных настройках."
        case .invalidUIElement: reason = "ссылка на окно больше недействительна"
        case .cannotComplete: reason = "приложение не ответило на запрос"
        default: reason = "операция с окном не выполнена"
        }
        return "\(reason) (\(error.rawValue)). Повторите возврат окна."
    }
}

enum WindowAccessOperation {
    case readPosition, readSize, setPosition, raise
    var label: String {
        switch self {
        case .readPosition: "Чтение положения окна"
        case .readSize: "Чтение размера окна"
        case .setPosition: "Перемещение окна"
        case .raise: "Поднятие окна на передний план"
        }
    }
}

protocol WindowAccessing {
    func position(of window: AXUIElement) throws -> CGPoint
    func frame(of window: AXUIElement) throws -> CGRect
    func setPosition(of window: AXUIElement, to point: CGPoint) throws
    func raise(_ window: AXUIElement) throws
}

struct AXWindowAccess: WindowAccessing {
    func position(of window: AXUIElement) throws -> CGPoint {
        let value = try value(of: window, attribute: kAXPositionAttribute, type: .cgPoint, operation: .readPosition)
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point), point.x.isFinite, point.y.isFinite else {
            throw WindowAccessError.invalidGeometry
        }
        return point
    }

    func frame(of window: AXUIElement) throws -> CGRect {
        let point = try position(of: window)
        let size = try value(of: window, attribute: kAXSizeAttribute, type: .cgSize, operation: .readSize)
        var dimensions = CGSize.zero
        guard AXValueGetValue(size, .cgSize, &dimensions),
              point.x.isFinite, point.y.isFinite,
              dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width > 0, dimensions.height > 0 else {
            throw WindowAccessError.invalidGeometry
        }
        return CGRect(origin: point, size: dimensions)
    }

    func setPosition(of window: AXUIElement, to point: CGPoint) throws {
        guard point.x.isFinite, point.y.isFinite else { throw WindowAccessError.invalidGeometry }
        var position = point
        guard let value = AXValueCreate(.cgPoint, &position) else { throw WindowAccessError.invalidGeometry }
        try check(AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value), operation: .setPosition)
    }

    func raise(_ window: AXUIElement) throws {
        try check(AXUIElementPerformAction(window, kAXRaiseAction as CFString), operation: .raise)
    }

    private func value(of window: AXUIElement, attribute: String, type: AXValueType, operation: WindowAccessOperation) throws -> AXValue {
        var raw: CFTypeRef?
        try check(AXUIElementCopyAttributeValue(window, attribute as CFString, &raw), operation: operation)
        guard let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { throw WindowAccessError.invalidGeometry }
        let value = raw as! AXValue // Safe after checking the Core Foundation type ID.
        guard AXValueGetType(value) == type else { throw WindowAccessError.invalidGeometry }
        return value
    }

    private func check(_ error: AXError, operation: WindowAccessOperation) throws {
        guard error == .success else { throw WindowAccessError.operationFailed(operation, error) }
    }
}
