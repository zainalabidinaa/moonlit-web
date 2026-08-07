import SwiftUI
import MoonlitCore

/// Moonlit's own dark, branded replacement for Sparkle's stock AppKit update
/// dialogs — hosted in a borderless `NSWindow` by `MoonlitUpdateUserDriver`
/// so it looks like the rest of the app instead of a plain Aqua alert.
struct UpdateFlowView: View {
    @ObservedObject var state: UpdateFlowState
    let appName: String

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(28)
        }
        .frame(width: 420)
        .macDarkGlassCard(cornerRadius: MoonlitTheme.radiusLarge)
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.2), value: phaseTag)
    }

    /// A cheap discriminator so `.animation(value:)` has something Equatable
    /// to compare — `UpdatePhase` itself isn't, since its associated data
    /// (release notes HTML, progress) isn't meaningfully comparable either.
    private var phaseTag: Int {
        switch state.phase {
        case .checking: 0
        case .updateAvailable: 1
        case .downloading: 2
        case .extracting: 3
        case .readyToInstall: 4
        case .installing: 5
        case .installed: 6
        case .notFound: 7
        case .error: 8
        case .permissionRequest: 9
        case nil: -1
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .checking:
            statusScreen(
                icon: "arrow.triangle.2.circlepath",
                spinning: true,
                title: "Checking for Updates…",
                subtitle: nil
            ) {
                secondaryButton("Cancel") {
                    state.onCancel?()
                }
            }

        case .permissionRequest:
            permissionScreen

        case .updateAvailable(let item):
            updateAvailableScreen(item)

        case .downloading(let progress):
            statusScreen(
                icon: "arrow.down.circle",
                spinning: progress == nil,
                title: "Downloading Update…",
                subtitle: progress.map { "\(Int($0 * 100))%" }
            ) {
                if let progress {
                    ProgressView(value: progress)
                        .tint(.white)
                        .padding(.top, 4)
                }
                secondaryButton("Cancel") {
                    state.onCancel?()
                }
            }

        case .extracting(let progress):
            statusScreen(
                icon: "shippingbox",
                spinning: true,
                title: "Preparing Update…",
                subtitle: progress.map { "\(Int($0 * 100))%" }
            ) { EmptyView() }

        case .readyToInstall:
            statusScreen(
                icon: "checkmark.circle",
                spinning: false,
                title: "Ready to Install",
                subtitle: "\(appName) will relaunch to finish updating."
            ) {
                HStack(spacing: 10) {
                    secondaryButton("Later") { state.onChoice?(.dismiss) }
                    primaryButton("Relaunch Now") { state.onChoice?(.install) }
                }
            }

        case .installing(let terminated):
            statusScreen(
                icon: "gearshape.2",
                spinning: true,
                title: "Installing Update…",
                subtitle: terminated ? nil : "\(appName) is about to quit."
            ) { EmptyView() }

        case .installed:
            statusScreen(
                icon: "checkmark.circle.fill",
                spinning: false,
                title: "Update Installed",
                subtitle: nil
            ) {
                primaryButton("Done") { state.onAcknowledge?() }
            }

        case .notFound(let message):
            statusScreen(
                icon: "checkmark.circle",
                spinning: false,
                title: "You're Up to Date",
                subtitle: message.isEmpty ? nil : message
            ) {
                primaryButton("OK") { state.onAcknowledge?() }
            }

        case .error(let message):
            statusScreen(
                icon: "exclamationmark.triangle",
                spinning: false,
                title: "Update Error",
                subtitle: message
            ) {
                primaryButton("OK") { state.onAcknowledge?() }
            }

        case nil:
            EmptyView()
        }
    }

    // MARK: - Screens

    private var permissionScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white)
            Text("Automatically Check for Updates?")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .foregroundStyle(.white)
            Text("\(appName) can check for updates in the background and let you know when a new version is ready. You can change this anytime in Settings.")
                .font(.system(size: 13))
                .foregroundStyle(MoonlitTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                secondaryButton("Don't Check") { state.onPermissionReply?(false) }
                primaryButton("Check Automatically") { state.onPermissionReply?(true) }
            }
            .padding(.top, 6)
        }
    }

    private func updateAvailableScreen(_ item: UpdateItemInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(item.isCritical ? "Critical Update Available" : "New Version Available")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                Spacer()
            }
            Text("\(appName) \(item.displayVersion)")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.08), in: Capsule())
                .foregroundStyle(.white.opacity(0.85))

            if let notesHTML = item.notesHTML, let attributed = try? AttributedString(
                markdown: notesHTML.strippingBasicHTML()
            ) {
                ScrollView {
                    Text(attributed)
                        .font(.system(size: 13))
                        .foregroundStyle(MoonlitTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }

            HStack(spacing: 10) {
                if !item.isInformationOnly {
                    secondaryButton("Skip") { state.onChoice?(.skip) }
                }
                secondaryButton(item.isInformationOnly ? "Close" : "Later") {
                    state.onChoice?(.dismiss)
                }
                if item.isInformationOnly {
                    Spacer()
                } else {
                    primaryButton("Update") { state.onChoice?(.install) }
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func statusScreen<Footer: View>(
        icon: String,
        spinning: Bool,
        title: String,
        subtitle: String?,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(spacing: 14) {
            ZStack {
                if spinning {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                        .tint(.white)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 34))
                        .foregroundStyle(.white)
                }
            }
            .frame(height: 40)

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(MoonlitTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            footer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Buttons

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(MoonlitPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .frame(height: 34)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(MoonlitTheme.textSecondary)
            .frame(height: 34)
            .padding(.horizontal, 4)
    }
}

private extension String {
    /// The appcast `<description>` is arbitrary HTML; Sparkle's stock UI
    /// hosts it in a `WKWebView`. Rather than pull in WebKit for a handful
    /// of release-note paragraphs, strip tags down to Markdown-ish text
    /// good enough for `AttributedString(markdown:)`.
    func strippingBasicHTML() -> String {
        var text = self
        text = text.replacingOccurrences(of: "<li>", with: "• ")
        text = text.replacingOccurrences(of: "</li>", with: "\n")
        text = text.replacingOccurrences(of: "<br>", with: "\n")
        text = text.replacingOccurrences(of: "<br/>", with: "\n")
        text = text.replacingOccurrences(of: "</p>", with: "\n\n")
        text = text.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
