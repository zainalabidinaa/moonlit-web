import Foundation

public enum ToastStyle: Sendable {
    case info
    case success
    case error
    case warning
}

public struct ToastItem: Identifiable, Sendable {
    public let id = UUID()
    public let message: String
    public let style: ToastStyle
    public let duration: TimeInterval

    public init(message: String, style: ToastStyle = .info, duration: TimeInterval = 2.5) {
        self.message = message
        self.style = style
        self.duration = duration
    }
}
