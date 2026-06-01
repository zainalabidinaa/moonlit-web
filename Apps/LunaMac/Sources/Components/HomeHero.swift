import SwiftUI
import LunaCore

struct HomeHero: View {
    let item: MetaPreview
    let rowTitle: String
    let onTap: () -> Void
    let dotCount: Int
    let activeIndex: Int
    let onDotTap: (Int) -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let banner = item.banner ?? item.poster,
                   let url = URL(string: banner) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            LunaTheme.surface
                        }
                    }
                } else {
                    LunaTheme.surface
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 480)
            .clipped()

            LinearGradient(
                colors: [.clear, LunaTheme.background.opacity(0.7), LunaTheme.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 480)

            LinearGradient(
                colors: [.black.opacity(0.5), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 480)

            VStack(alignment: .leading, spacing: 0) {
                Text(rowTitle.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(LunaTheme.accent)
                    .tracking(2)
                    .padding(.bottom, 8)

                Text(item.name)
                    .font(.system(size: 44, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.bottom, 6)

                HStack(spacing: 8) {
                    if let rating = item.imdbRating {
                        Label(rating, systemImage: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                    if let release = item.releaseInfo {
                        Text(release)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    if let genres = item.genres?.prefix(2) {
                        Text(genres.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.bottom, 18)

                HStack(spacing: 12) {
                    Button(action: onTap) {
                        Label("Watch Now", systemImage: "play.fill")
                            .font(.subheadline.bold())
                            .foregroundColor(.black)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 11)
                            .background(Color.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: onTap) {
                        Label("My List", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 11)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)

            if dotCount > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<dotCount, id: \.self) { i in
                        Button { onDotTap(i) } label: {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(i == activeIndex ? Color.white : Color.white.opacity(0.3))
                                .frame(
                                    width: i == activeIndex ? 20 : 6,
                                    height: 3
                                )
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.25), value: activeIndex)
                    }
                }
                .padding(.trailing, 20)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(height: 480)
        .clipped()
    }
}
