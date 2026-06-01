import SwiftUI
import LunaCore

struct MacLibraryView: View {
    @StateObject private var libraryRepo = LibraryRepository.shared
    @EnvironmentObject var profileManager: ProfileManager

    var body: some View {
        VStack(spacing: 0) {
            if libraryRepo.isLoading {
                Spacer()
                ProgressView().tint(LunaTheme.accent)
                Spacer()
            } else if libraryRepo.libraryItems.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 40))
                        .foregroundColor(LunaTheme.textTertiary)
                    Text("Your library is empty")
                        .font(.title2)
                        .foregroundColor(.white)
                    Text("Save movies and shows to watch later")
                        .font(.subheadline)
                        .foregroundColor(LunaTheme.textTertiary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                        ForEach(libraryRepo.libraryItems) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                ZStack(alignment: .topTrailing) {
                                    Rectangle()
                                        .fill(LunaTheme.surfaceElevated)
                                        .frame(height: 220)
                                        .cornerRadius(10)
                                        .overlay(
                                            Text(item.mediaType == "series" ? "📺" : "🎬")
                                                .font(.title)
                                        )

                                    Menu {
                                        Button("Remove from Library", role: .destructive) {
                                            Task {
                                                guard let profile = profileManager.currentProfile else { return }
                                                await libraryRepo.removeFromLibrary(profileId: profile.id, mediaId: item.mediaId)
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(.white.opacity(0.8))
                                            .shadow(radius: 2)
                                            .padding(6)
                                    }
                                    .menuStyle(.borderlessButton)
                                    .frame(width: 28, height: 28)
                                }
                                .frame(height: 220)

                                Text(item.name ?? item.mediaId)
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding()
                    .padding(.top, 48)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LunaTheme.background)
        .task {
            guard let profile = profileManager.currentProfile else { return }
            await libraryRepo.loadLibrary(profileId: profile.id)
        }
    }
}
