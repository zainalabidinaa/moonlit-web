import SwiftUI
import MoonlitCore

/// Add / edit an IPTV source. Port of a reference `playlist-form.tsx` — a 3-way
/// M3U / Xtream / EPG toggle with the fields each kind needs.
struct MacIPTVSourceFormView: View {
    /// Non-nil when editing an existing source.
    var existing: IPTVPlaylistSource?
    var onSave: (IPTVPlaylistSource) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var kind: IPTVSourceKind
    @State private var name: String
    @State private var url: String
    @State private var epgUrl: String
    @State private var server: String
    @State private var username: String
    @State private var password: String

    init(existing: IPTVPlaylistSource? = nil, onSave: @escaping (IPTVPlaylistSource) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _kind = State(initialValue: existing?.kind ?? .m3u)
        _name = State(initialValue: existing?.name ?? "")
        _url = State(initialValue: existing?.url ?? "")
        _epgUrl = State(initialValue: existing?.epgUrl ?? "")
        _server = State(initialValue: existing?.xtream?.server ?? "")
        _username = State(initialValue: existing?.xtream?.username ?? "")
        _password = State(initialValue: existing?.xtream?.password ?? "")
    }

    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch kind {
        case .m3u: return !url.trimmingCharacters(in: .whitespaces).isEmpty
        case .xtream:
            return ![server, username, password].contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        case .epg: return !url.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(existing == nil ? "Add Playlist" : "Edit Playlist")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(MoonlitTheme.textPrimary)

            kindPicker

            VStack(alignment: .leading, spacing: 14) {
                field("Name", text: $name, placeholder: "My Playlist")

                switch kind {
                case .m3u:
                    field("Playlist URL", text: $url, placeholder: "https://example.com/playlist.m3u8")
                    field("EPG URL (optional)", text: $epgUrl, placeholder: "https://example.com/epg.xml")
                case .xtream:
                    field("Server URL", text: $server, placeholder: "http://example.com:8080")
                    field("Username", text: $username, placeholder: "username")
                    secureField("Password", text: $password, placeholder: "password")
                    field("EPG URL (optional)", text: $epgUrl, placeholder: "https://example.com/xmltv.php")
                case .epg:
                    field("XMLTV URL", text: $url, placeholder: "https://example.com/epg.xml")
                }
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(MoonlitTheme.textSecondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(MoonlitTheme.surface, in: Capsule())

                Button(existing == nil ? "Add" : "Save") { save() }
                    .buttonStyle(.plain)
                    .foregroundColor(isValid ? .black : MoonlitTheme.textTertiary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(isValid ? MoonlitTheme.accent : MoonlitTheme.surface, in: Capsule())
                    .disabled(!isValid)
            }
        }
        .padding(28)
        .frame(width: 460)
        .background(MoonlitTheme.background)
    }

    private var kindPicker: some View {
        HStack(spacing: 6) {
            ForEach(IPTVSourceKind.allCases, id: \.self) { option in
                let isSelected = kind == option
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { kind = option }
                } label: {
                    Text(option.displayName)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? .black : MoonlitTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isSelected ? MoonlitTheme.accent : MoonlitTheme.surface, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(MoonlitTheme.textTertiary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(MoonlitTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(MoonlitTheme.surface, in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl))
                .autocorrectionDisabled()
        }
    }

    private func secureField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(MoonlitTheme.textTertiary)
            SecureField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(MoonlitTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(MoonlitTheme.surface, in: RoundedRectangle(cornerRadius: MoonlitTheme.radiusControl))
        }
    }

    private func save() {
        guard isValid else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let source: IPTVPlaylistSource
        switch kind {
        case .m3u:
            source = IPTVPlaylistSource(
                id: existing?.id ?? UUID().uuidString,
                name: trimmedName,
                url: url.trimmingCharacters(in: .whitespaces),
                epgUrl: epgUrl.trimmingCharacters(in: .whitespaces).nilIfEmpty,
                kind: .m3u,
                createdAt: existing?.createdAt ?? Date()
            )
        case .xtream:
            source = IPTVPlaylistSource(
                id: existing?.id ?? UUID().uuidString,
                name: trimmedName,
                url: "",
                epgUrl: epgUrl.trimmingCharacters(in: .whitespaces).nilIfEmpty,
                kind: .xtream,
                xtream: XtreamCredentials(
                    server: server.trimmingCharacters(in: .whitespaces),
                    username: username.trimmingCharacters(in: .whitespaces),
                    password: password.trimmingCharacters(in: .whitespaces)
                ),
                createdAt: existing?.createdAt ?? Date()
            )
        case .epg:
            source = IPTVPlaylistSource(
                id: existing?.id ?? UUID().uuidString,
                name: trimmedName,
                url: url.trimmingCharacters(in: .whitespaces),
                epgUrl: url.trimmingCharacters(in: .whitespaces),
                kind: .epg,
                createdAt: existing?.createdAt ?? Date()
            )
        }
        onSave(source)
        dismiss()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
