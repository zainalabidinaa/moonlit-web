import SwiftUI
import MoonlitCore

/// Circular add/remove-from-library toggle overlaid on media tiles. Observes the
/// shared LibraryRepository so its ✓ state stays live regardless of MediaCard's
/// Equatable body-skipping.
struct LibraryToggleButton: View {
    let item: MetaPreview
    var size: CGFloat = 28

    @EnvironmentObject private var profileManager: ProfileManager
    @ObservedObject private var libraryRepo = LibraryRepository.shared
    @State private var isBusy = false

    private var isSaved: Bool { libraryRepo.isInLibrary(mediaId: item.id) }

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isSaved ? "checkmark" : "plus")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(.black.opacity(0.55), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(isSaved ? 0.5 : 0.22), lineWidth: 0.75))
                .scaleEffect(isBusy ? 0.85 : 1)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isSaved)
        .help(isSaved ? "Remove from Library" : "Add to Library")
    }

    private func toggle() {
        guard let profileId = profileManager.currentProfile?.id else { return }
        isBusy = true
        Task {
            await libraryRepo.toggleLibrary(
                profileId: profileId,
                mediaId: item.id,
                mediaType: item.type.rawValue,
                name: item.name,
                poster: item.poster
            )
            isBusy = false
        }
    }
}
