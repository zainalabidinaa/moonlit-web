import SwiftUI
import MoonlitCore

struct AdminDashboard: View {
    @StateObject private var adminService = AdminService.shared
    @State private var selectedSection: AdminSection = .dashboard

    enum AdminSection: String, CaseIterable {
        case dashboard = "Dashboard"
        case inviteCodes = "Invite Codes"
        case users = "Users"
    }

    var body: some View {
        ZStack {
            MoonlitTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Picker("Section", selection: $selectedSection) {
                    ForEach(AdminSection.allCases, id: \.self) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .colorMultiply(MoonlitTheme.accent)

                switch selectedSection {
                case .dashboard:
                    AdminStatsView(stats: adminService.stats)
                case .inviteCodes:
                    AdminInviteCodesView()
                case .users:
                    AdminUsersView()
                }
            }
        }
        .navigationTitle("Admin Panel")
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
        .task {
            await adminService.loadStats()
            await adminService.loadInviteCodes()
            await adminService.loadAllUsers()
        }
    }
}

struct AdminStatsView: View {
    let stats: AdminStats

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                StatCard(title: "Total Users", value: "\(stats.totalUsers)", icon: "person.2", color: .blue)
                StatCard(title: "Profiles", value: "\(stats.totalProfiles)", icon: "person.crop.circle", color: .purple)
                StatCard(title: "Invite Codes", value: "\(stats.activeInviteCodes)", icon: "ticket", color: .green)
                StatCard(title: "Watchlist", value: "\(stats.totalWatchlistItems)", icon: "bookmark", color: .orange)
                StatCard(title: "Watched", value: "\(stats.totalWatchedItems)", icon: "checkmark.circle", color: .pink)
                StatCard(title: "Active Users", value: "\(stats.activeUsers)", icon: "person.fill.checkmark", color: .teal)
            }
            .padding()
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
            Text(title)
                .font(.caption)
                .foregroundColor(MoonlitTheme.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(MoonlitTheme.surface)
        .cornerRadius(MoonlitTheme.radiusCard)
    }
}

struct AdminInviteCodesView: View {
    @StateObject private var adminService = AdminService.shared
    @State private var showGenerateSheet = false
    @State private var maxUses = 1

    var body: some View {
        ZStack {
            MoonlitTheme.background.ignoresSafeArea()

            List {
                Section {
                    Button {
                        showGenerateSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(MoonlitTheme.accent)
                            Text("Generate New Invite Code")
                                .foregroundColor(MoonlitTheme.accent)
                        }
                    }
                }

                Section("Active Codes (\(activeCodes.count))") {
                    ForEach(adminService.inviteCodes) { code in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(code.code)
                                .font(.system(.headline, design: .monospaced))
                                .foregroundColor(.white)
                            HStack {
                                Text("Created: \(code.createdAt, style: .date)")
                                    .font(.caption2)
                                    .foregroundColor(MoonlitTheme.textTertiary)
                                if code.isUsed {
                                    Text("Used")
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                } else if code.isActive {
                                    Text("Active")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }
                        }
#if os(iOS)
                        .swipeActions {
                            if !code.isUsed && code.isActive {
                                Button("Revoke") {
                                    Task { try await adminService.revokeInviteCode(code.code) }
                                }
                                .tint(.red)
                            }
                        }
#endif
                        .listRowBackground(MoonlitTheme.surface)
                    }
                }
                .listRowBackground(MoonlitTheme.surface)
            }
#if os(iOS)
            .scrollContentBackground(.hidden)
#endif
        }
        .sheet(isPresented: $showGenerateSheet) {
            NavigationStack {
                ZStack {
                    MoonlitTheme.background.ignoresSafeArea()

                    VStack(spacing: 20) {
                        Text("Generate Invite Code")
                            .font(.headline)
                            .foregroundColor(.white)

#if os(iOS)
                        Stepper("Max Uses: \(maxUses)", value: $maxUses, in: 1...100)
                            .foregroundColor(.white)
                            .padding(.horizontal)
#endif

                        Button {
                            Task {
                                let _ = try await adminService.generateInviteCode(maxUses: maxUses)
                                showGenerateSheet = false
                            }
                        } label: {
                            Text("Generate")
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .glassProminentButtonStyle(cornerRadius: MoonlitTheme.radiusCard)
                        .padding(.horizontal)

                        Spacer()
                    }
                    .padding(.top)
                }
                .navigationTitle("New Code")
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showGenerateSheet = false }
                    }
                }
            }
        }
    }

    private var activeCodes: [InviteCode] {
        adminService.inviteCodes.filter { $0.isActive && !$0.isUsed }
    }
}

struct AdminUsersView: View {
    @StateObject private var adminService = AdminService.shared

    var body: some View {
        ZStack {
            MoonlitTheme.background.ignoresSafeArea()

            List {
                ForEach(adminService.allUsers) { user in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.email)
                            .foregroundColor(.white)
                        Text("Joined: \(user.createdAt, style: .date)")
                            .font(.caption)
                            .foregroundColor(MoonlitTheme.textSecondary)
                        Text("ID: \(user.id)")
                            .font(.caption2)
                            .foregroundColor(MoonlitTheme.textTertiary)
                    }
                    .listRowBackground(MoonlitTheme.surface)
                }
            }
#if os(iOS)
            .scrollContentBackground(.hidden)
#endif
        }
    }
}
