import SwiftUI

struct PlayerLockMode: View {
    @Binding var isLocked: Bool
    @Binding var showHint: Bool

    var body: some View {
        if isLocked {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    Button {
                        showHint = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.52))
                                .frame(width: 78, height: 78)
                            Circle()
                                .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                                .frame(width: 78, height: 78)
                            Image(systemName: "lock.fill")
                                .font(.title)
                                .foregroundColor(.white)
                        }
                    }

                    if showHint {
                        Text("Tap to unlock")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .onTapGesture {
                showHint = false
                withAnimation {
                    isLocked = false
                }
            }
        }
    }
}
