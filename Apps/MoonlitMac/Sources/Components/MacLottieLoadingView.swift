import SwiftUI

/// The app's loading spinner — two counter-rotating trimmed arcs in white,
/// pure SwiftUI Shapes (no image/Lottie asset). Replaces the old Lottie
/// dot-ring, which read as a lopsided crescent at the larger sizes it was
/// used at across the app. Kept this file/type name so none of the 11 call
/// sites needed to change.
struct MacLottieLoadingView: View {
    var size: CGFloat = 44
    var color: Color = .white

    @State private var isAnimating = false

    private var lineWidth: CGFloat { max(2, size / 14) }

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .overlay(
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(color.opacity(0.4), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: size * 0.5, height: size * 0.5)
                    .rotationEffect(.degrees(isAnimating ? -360 : 0))
            )
            .frame(width: size, height: size)
            .onAppear {
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}
