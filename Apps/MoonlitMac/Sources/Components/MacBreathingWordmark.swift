import SwiftUI

struct MacBreathingWordmark: View {
    @State private var isBright = false

    var body: some View {
        Text("M O O N L I T")
            .font(.custom("Montserrat-ExtraBold", size: 42))
            .foregroundStyle(.white)
            .kerning(4)
            .opacity(isBright ? 1 : 0.35)
            .scaleEffect(isBright ? 1 : 0.96)
            .onAppear {
                withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                    isBright = true
                }
            }
    }
}
