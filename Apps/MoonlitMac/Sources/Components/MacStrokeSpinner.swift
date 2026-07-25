import SwiftUI

/// The app's loading indicator — a clean rotating ring in the style of the
/// "Stroke (ProgressView)" HTML variant: a faint white track with a single
/// bright white arc sweeping around it at a steady linear pace. Replaces the
/// default macOS `ProgressView()` spinner so loading looks consistent
/// everywhere.
struct MacStrokeSpinner: View {
    var size: CGFloat = 28
    var color: Color = .white

    private var lineWidth: CGFloat { max(2, size * 0.1) }

    @State private var isSpinning = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.14), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) {
                isSpinning = true
            }
        }
    }
}
