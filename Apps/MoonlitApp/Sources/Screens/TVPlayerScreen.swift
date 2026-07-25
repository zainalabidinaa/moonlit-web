import SwiftUI
import AVKit
import MoonlitCore

#if os(tvOS)
struct TVPlayerScreen: View {
    let launch: PlayerLaunch
    let onDismiss: () -> Void
    @State private var player = AVPlayer()
    @State private var didFail = false

    var body: some View {
        ZStack {
            if didFail {
                VStack(spacing: 24) {
                    Text("Unable to play this stream")
                        .font(.title2)
                        .foregroundStyle(.white)
                    Button("Back") { onDismiss() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
        }
        .onAppear { play(launch: launch) }
        .onDisappear {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
    }

    private func play(launch: PlayerLaunch) {
        guard !launch.sourceUrl.isEmpty,
              let url = URL(string: launch.sourceUrl) else {
            didFail = true
            return
        }
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": launch.sourceHeaders ?? [:]
        ])
        let item = AVPlayerItem(asset: asset)

        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = launch.title as NSString
        titleItem.extendedLanguageTag = "und"
        item.externalMetadata = [titleItem]

        player.replaceCurrentItem(with: item)
        player.play()
    }
}
#endif
