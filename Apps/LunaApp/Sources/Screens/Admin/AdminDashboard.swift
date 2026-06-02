import SwiftUI
import LunaCore

struct AdminDashboard: View {
    @StateObject private var adminService = AdminService.shared
    @State private var selectedSection: AdminSection = .dashboard

    enum AdminSection: String, CaseIterable {
        case dashboard = "Dashboard"
        case inviteCodes = "Invite Codes"
        case users = "Users"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LunaTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    Picker("Section", selection: $selectedSection) {
                        ForEach(AdminSection.allCases, id: \.self) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    .colorMultiply(LunaTheme.accent)

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
            .navigationBarTitleDisplayMode(.large)
            .task {
                await adminService.loadStats()
                await adminService.loadInviteCodes()
                await adminService.loadAllUsers()
            }
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
                .foregroundColor(LunaTheme.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(LunaTheme.surface)
        .cornerRadius(12)
    }
}

struct AdminInviteCodesView: View {
    @StateObject private var adminService = AdminService.shared
    @State private var showGenerateSheet = false
    @State private var maxUses = 1

    var body: some View {
        ZStack {
            LunaTheme.background.ignoresSafeArea()

            List {
                Section {
                    Button {
                        showGenerateSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(LunaTheme.accent)
                            Text("Generate New Invite Code")
                                .foregroundColor(LunaTheme.accent)
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
                                    .foregroundColor(LunaTheme.textTertiary)
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
                        .swipeActions {
                            if !code.isUsed && code.isActive {
                                Button("Revoke") {
                                    Task { try await adminService.revokeInviteCode(code.code) }
                                }
                                .tint(.red)
                            }
                        }
                        .listRowBackground(LunaTheme.surface)
                    }
                }
                .listRowBackground(LunaTheme.surface)
            }
            .scrollContentBackground(.hidden)
        }
        .sheet(isPresented: $showGenerateSheet) {
            NavigationStack {
                ZStack {
                    LunaTheme.background.ignoresSafeArea()

                    VStack(spacing: 20) {
                        Text("Generate Invite Code")
                            .font(.headline)
                            .foregroundColor(.white)

                        Stepper("Max Uses: \(maxUses)", value: $maxUses, in: 1...100)
                            .foregroundColor(.white)
                            .padding(.horizontal)

                        Button {
                            Task {
                                let _ = try await adminService.generateInviteCode(maxUses: maxUses)
                                showGenerateSheet = false
                            }
                        } label: {
                            Text("Generate")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(LunaTheme.accent)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)

                        Spacer()
                    }
                    .padding(.top)
                }
                .navigationTitle("New Code")
                .navigationBarTitleDisplayMode(.inline)
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
            LunaTheme.background.ignoresSafeArea()

            List {
                ForEach(adminService.allUsers) { user in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.email)
                            .foregroundColor(.white)
                        Text("Joined: \(user.createdAt, style: .date)")
                            .font(.caption)
                            .foregroundColor(LunaTheme.textSecondary)
                        Text("ID: \(user.id)")
                            .font(.caption2)
                            .foregroundColor(LunaTheme.textTertiary)
                    }
                    .listRowBackground(LunaTheme.surface)
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}
