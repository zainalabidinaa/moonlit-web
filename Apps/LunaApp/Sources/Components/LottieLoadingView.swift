import SwiftUI
import Lottie

struct LottieLoadingView: View {
    var size: CGFloat = 44

    var body: some View {
        LottieAnimationPlayer(animationName: "loading-animation-gradient-line-2-colors-1")
            .frame(width: size, height: size)
            .accessibilityLabel("Loading")
    }
}

private struct LottieAnimationPlayer: UIViewRepresentable {
    let animationName: String

    func makeUIView(context: Context) -> UIView {
        // Container defeats LottieAnimationView's 800x800 intrinsic size, which
        // otherwise overrides the SwiftUI frame and draws the animation unclipped.
        let container = UIView()
        container.clipsToBounds = true

        let view = LottieAnimationView(name: animationName, bundle: .main)
        view.contentMode = .scaleAspectFit
        view.loopMode = .loop
        view.backgroundBehavior = .pauseAndRestore
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        view.play()
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        if let view = container.subviews.first as? LottieAnimationView, !view.isAnimationPlaying {
            view.play()
        }
    }
}
