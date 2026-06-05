import SwiftUI

@MainActor
public final class ToastPresenter: ObservableObject {
    public static let shared = ToastPresenter()

    @Published public private(set) var current: ToastItem?
    @Published public private(set) var visible = false

    private var queue: [ToastItem] = []

    private init() {}

    public func show(_ toast: ToastItem) {
        if visible {
            queue.append(toast)
        } else {
            present(toast)
        }
    }

    public func show(message: String, style: ToastStyle = .info, duration: TimeInterval = 2.5) {
        show(ToastItem(message: message, style: style, duration: duration))
    }

    private func present(_ toast: ToastItem) {
        current = toast
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            visible = true
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(toast.duration * 1_000_000_000))
            await dismiss()
        }
    }

    public func dismiss() async {
        withAnimation(.easeOut(duration: 0.25)) {
            visible = false
        }
        try? await Task.sleep(nanoseconds: 250_000_000)
        current = nil
        guard let next = queue.first else { return }
        queue.removeFirst()
        present(next)
    }
}
