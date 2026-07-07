import SwiftUI
import MoonlitCore

struct Mac4KButton: View {
    let streamRepo: StreamRepository
    let currentSourceUrl: String
    let onSwitchTo4K: (Bool) -> Void

    @State private var show4KChoice = false

    private var has4K: Bool {
        StreamSourceSelector.has4KPlaybackCandidate(
            in: streamRepo.streams,
            excludingSourceUrl: currentSourceUrl
        )
    }

    private var best4K: StreamItem? {
        StreamSourceSelector.best4KStream(
            from: streamRepo.streams,
            excluding: streamRepo.streams.first(where: { $0.url == currentSourceUrl })
        )
    }

    var body: some View {
        if has4K {
            Button {
                show4KChoice = true
            } label: {
                Image(systemName: "4k.tv")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityLabel("4K available")
            .confirmationDialog("4K Playback", isPresented: $show4KChoice, titleVisibility: .visible) {
                Button("Use 4K This Time") {
                    onSwitchTo4K(false)
                }
                Button("Always Prefer 4K") {
                    onSwitchTo4K(true)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Switch to the best available 4K source. Choose whether to prefer 4K for future playback or just this once.")
            }
        }
    }
}
