import SwiftUI
import MoonlitCore

/// One app version's release notes, grouped the same way the changelog is
/// grouped everywhere else Moonlit talks about a release (commit prefixes,
/// the appcast description): new capability, improvement, or fix.
struct ReleaseNote: Identifiable {
    enum Category {
        case new, improved, fixed

        var label: String {
            switch self {
            case .new: "New"
            case .improved: "Improved"
            case .fixed: "Fixed"
            }
        }
        var tint: Color {
            switch self {
            case .new: Color(red: 0.50, green: 0.72, blue: 0.63)
            case .improved: Color(red: 0.56, green: 0.69, blue: 0.85)
            case .fixed: Color(red: 0.79, green: 0.56, blue: 0.50)
            }
        }
    }

    let id = UUID()
    let category: Category
    let title: String
    let detail: String?

    init(_ category: Category, _ title: String, detail: String? = nil) {
        self.category = category
        self.title = title
        self.detail = detail
    }
}

/// Release notes for the version currently shipping. Update this alongside
/// `MARKETING_VERSION` in project.yml — `WhatsNewStore` compares the two to
/// decide whether to show the sheet, so a version bump with no entry here
/// just shows nothing.
enum ReleaseNotesCatalog {
    static let current: [ReleaseNote] = [
        ReleaseNote(.new, "Welcome to Moonlit for Mac", detail: "Browse, stream, and manage your media library right on your desktop."),
    ]
}

/// Tracks which version's notes were last shown, so the sheet appears once
/// per update rather than every launch.
@MainActor
final class WhatsNewStore: ObservableObject {
    static let shared = WhatsNewStore()

    private static let lastSeenKey = "moonlit.whatsNew.lastSeenVersion"

    @Published var isPresented = false

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    func presentIfNeeded() {
        guard !ReleaseNotesCatalog.current.isEmpty else { return }
        let lastSeen = UserDefaults.standard.string(forKey: Self.lastSeenKey)
        guard lastSeen != currentVersion else { return }
        isPresented = true
    }

    func dismiss() {
        UserDefaults.standard.set(currentVersion, forKey: Self.lastSeenKey)
        isPresented = false
    }
}

struct WhatsNewView: View {
    let version: String
    let notes: [ReleaseNote]
    let onDismiss: () -> Void

    private var grouped: [(ReleaseNote.Category, [ReleaseNote])] {
        [ReleaseNote.Category.new, .improved, .fixed].compactMap { category in
            let items = notes.filter { $0.category == category }
            return items.isEmpty ? nil : (category, items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(grouped, id: \.0.label) { category, items in
                        categorySection(category, items)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            Divider().overlay(Color.white.opacity(0.08))
            HStack {
                Spacer()
                Button("Continue", action: onDismiss)
                    .buttonStyle(MoonlitPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .frame(width: 120, height: 34)
            }
            .padding(20)
        }
        .frame(width: 480, height: 480)
        .macDarkGlassCard(cornerRadius: MoonlitTheme.radiusLarge)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What's new")
                .font(.system(size: 26, weight: .bold, design: .serif))
                .foregroundStyle(.white)
            HStack(spacing: 8) {
                Text("Version \(version)")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .foregroundStyle(.white.opacity(0.85))
                Text("Moonlit for Mac")
                    .font(.system(size: 12))
                    .foregroundStyle(MoonlitTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
        .padding(.top, 30)
        .padding(.bottom, 20)
    }

    private func categorySection(_ category: ReleaseNote.Category, _ items: [ReleaseNote]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(category.tint).frame(width: 6, height: 6)
                Text(category.label.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(category.tint)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title)
                            .font(.system(size: 13.5))
                            .foregroundStyle(.white)
                        if let detail = note.detail {
                            Text(detail)
                                .font(.system(size: 12))
                                .foregroundStyle(MoonlitTheme.textTertiary)
                        }
                    }
                }
            }
        }
    }
}

private struct WhatsNewSheetModifier: ViewModifier {
    @StateObject private var store = WhatsNewStore.shared

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $store.isPresented) {
                WhatsNewView(
                    version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                    notes: ReleaseNotesCatalog.current,
                    onDismiss: { store.dismiss() }
                )
            }
            .onAppear { store.presentIfNeeded() }
    }
}

extension View {
    /// Shows Moonlit's own "What's New" sheet once per version, separate
    /// from Sparkle's update-check UI — this is the branded announcement,
    /// Sparkle just handles getting the new build onto disk.
    func whatsNewSheet() -> some View {
        modifier(WhatsNewSheetModifier())
    }
}
