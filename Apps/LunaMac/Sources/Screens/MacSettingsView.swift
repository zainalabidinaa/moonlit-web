import SwiftUI
import LunaCore

struct MacSettingsView: View {
    @EnvironmentObject var profileManager: ProfileManager
    @StateObject private var addonRepo = AddonRepository.shared
    @State private var newUrl = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let profile = profileManager.currentProfile {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(profile.avatarColor.map { Color(hex: $0) } ?? LunaTheme.accent)
                            .frame(width: 48, height: 48)
                            .overlay(
                                Text(String(profile.name.prefix(1).uppercased()))
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(profile.isAdmin ? "Admin" : "User")
                                .font(.caption)
                                .foregroundColor(LunaTheme.textTertiary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LunaTheme.surface)
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.top, 56)

                    Button("Switch Profile") {
                        profileManager.currentProfile = nil
                    }
                    .font(.subheadline)
                    .foregroundColor(LunaTheme.textSecondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("Addons (\(addonRepo.managedAddons.count))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(LunaTheme.textTertiary)
                        .tracking(1)
                        .textCase(.uppercase)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 6)

                    VStack(spacing: 0) {
                        ForEach(addonRepo.managedAddons) { addon in
                            HStack {
                                Text(addon.displayName)
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                Spacer()
                                Circle()
                                    .fill(addon.enabled ? Color.green : LunaTheme.textTertiary)
                                    .frame(width: 8, height: 8)
                                Text(addon.enabled ? "Enabled" : "Disabled")
                                    .font(.caption)
                                    .foregroundColor(addon.enabled ? .green : LunaTheme.textTertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(LunaTheme.surface)
                            if addon.id != addonRepo.managedAddons.last?.id {
                                Divider().background(Color.white.opacity(0.06))
                            }
                        }

                        HStack(spacing: 8) {
                            TextField("Add addon URL...", text: $newUrl)
                                .textFieldStyle(.plain)
                                .padding(8)
                                .background(LunaTheme.background)
                                .cornerRadius(6)
                                .foregroundColor(.white)
                            Button("Install") {
                                Task {
                                    await addonRepo.installAddon(url: newUrl)
                                    newUrl = ""
                                }
                            }
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(newUrl.isEmpty ? LunaTheme.surfaceElevated : LunaTheme.accent)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                            .disabled(newUrl.isEmpty)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(LunaTheme.surface)
                    }
                    .cornerRadius(10)
                    .padding(.horizontal)
                }

                Button("Sign Out") {
                    Task { await profileManager.signOut() }
                }
                .foregroundColor(.red)
                .font(.subheadline)
                .padding(.horizontal, 20)
                .padding(.top, 24)

                Text("Luna for macOS · v1.0")
                    .font(.caption2)
                    .foregroundColor(LunaTheme.textTertiary)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer().frame(height: 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LunaTheme.background)
    }
}
